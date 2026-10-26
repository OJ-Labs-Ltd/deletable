import Darwin
import Foundation

/// Thread-safe running totals the UI polls while a scan is in flight.
final class ScanProgress: @unchecked Sendable {
    struct Snapshot {
        var files = 0
        var bytes: Int64 = 0
        var errors = 0
        var path = ""
    }

    private let lock = NSLock()
    private var state = Snapshot()
    private var cancelled = false

    func add(files: Int, bytes: Int64, path: String) {
        lock.lock()
        state.files += files
        state.bytes += bytes
        state.path = path
        lock.unlock()
    }

    func addError() {
        lock.lock(); state.errors += 1; lock.unlock()
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return state
    }
}

/// Fast allocated-size scanner.
///
/// Uses `getattrlistbulk(2)`, which returns names, types and allocated sizes for a whole
/// batch of directory entries in a single system call (no URL objects, no per-file lookups),
/// and a pool of worker threads sharing one work stack so a single huge folder can't stall
/// the scan. Hard-linked files are counted once.
enum DiskScanner {
    static func scan(root: URL, progress: ScanProgress) async -> FileNode {
        let rootNode = FileNode(name: root.lastPathComponent, isDirectory: true, rootURL: root)
        let rootPath = root.standardizedFileURL.path
        // On the boot volume, skip the other APFS volumes mounted beneath it (their
        // contents already appear through firmlinks such as /Users and /Applications).
        let excluded: Set<String> = rootPath == "/"
            ? ["/System/Volumes", "/Volumes", "/dev", "/.vol", "/.nofollow", "/.resolve"]
            : []

        // Never download cloud placeholders while scanning (IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES,
        // IOPOL_SCOPE_PROCESS, IOPOL_MATERIALIZE_DATALESS_FILES_OFF).
        _ = setiopolicy_np(3, 0, 1)

        let queue = WorkQueue(root: (rootNode, rootPath))
        let links = HardLinkSet()
        let workers = min(48, max(8, ProcessInfo.processInfo.activeProcessorCount * 3))

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for _ in 0..<workers {
                group.enter()
                let thread = Thread {
                    let reader = BulkReader()
                    while let item = queue.pop(progress: progress) {
                        let (node, path) = item
                        let subdirs = reader.read(node: node, path: path, excluded: excluded,
                                                  links: links, progress: progress)
                        queue.finish(adding: subdirs)
                    }
                    group.leave()
                }
                thread.qualityOfService = .userInitiated
                thread.stackSize = 1 << 20
                thread.start()
            }
            group.notify(queue: .global()) { done.resume() }
        }

        rootNode.finalize()
        return rootNode
    }
}

/// Shared LIFO stack of directories still to read. LIFO keeps workers deep in the tree,
/// which keeps the stack (and memory) small.
private final class WorkQueue: @unchecked Sendable {
    private let cond = NSCondition()
    private var stack: [(FileNode, String)]
    private var active = 0

    init(root: (FileNode, String)) { stack = [root] }

    func pop(progress: ScanProgress) -> (FileNode, String)? {
        cond.lock(); defer { cond.unlock() }
        while true {
            if progress.isCancelled {
                stack.removeAll()
                cond.broadcast()
                return nil
            }
            if let item = stack.popLast() {
                active += 1
                return item
            }
            if active == 0 {          // nothing queued and nobody can add more: finished
                cond.broadcast()
                return nil
            }
            cond.wait(until: Date().addingTimeInterval(0.2))
        }
    }

    func finish(adding items: [(FileNode, String)]) {
        cond.lock()
        stack.append(contentsOf: items)
        active -= 1
        if !items.isEmpty || active == 0 { cond.broadcast() }
        cond.unlock()
    }
}

/// Inodes of files with more than one hard link, so each is counted once.
private final class HardLinkSet: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<UInt64>()

    /// Returns true the first time an inode is seen.
    func insert(_ id: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return seen.insert(id).inserted
    }
}

/// Per-thread reader with its own buffer.
private final class BulkReader {
    // attr.h constants (hard-coded so the import of C macros doesn't matter).
    private static let cmnName: UInt32 = 0x0000_0001
    private static let cmnObjType: UInt32 = 0x0000_0008
    private static let cmnFlags: UInt32 = 0x0004_0000
    private static let sfDataless: UInt32 = 0x4000_0000     // cloud placeholder, no local data
    private static let cmnFileID: UInt32 = 0x0200_0000
    private static let cmnReturned: UInt32 = 0x8000_0000
    private static let dirMountStatus: UInt32 = 0x0000_0008
    private static let fileLinkCount: UInt32 = 0x0000_0001
    private static let fileAllocSize: UInt32 = 0x0000_0004
    private static let mountPoint: UInt32 = 0x0000_0001   // DIR_MNTSTATUS_MNTPOINT
    private static let vREG: UInt32 = 1, vDIR: UInt32 = 2

    private let bufferSize = 256 * 1024
    private let buffer: UnsafeMutableRawPointer
    private var request = attrlist()

    init() {
        buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
        request.bitmapcount = 5                       // ATTR_BIT_MAP_COUNT
        request.commonattr = Self.cmnReturned | Self.cmnName | Self.cmnObjType | Self.cmnFlags | Self.cmnFileID
        request.dirattr = Self.dirMountStatus
        request.fileattr = Self.fileLinkCount | Self.fileAllocSize
    }

    deinit { buffer.deallocate() }

    func read(node: FileNode, path: String, excluded: Set<String>,
              links: HardLinkSet, progress: ScanProgress) -> [(FileNode, String)] {
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else {
            progress.addError()
            return []
        }
        defer { close(fd) }

        var kids: [FileNode] = []
        var subdirs: [(FileNode, String)] = []
        var files = 0
        var bytes: Int64 = 0
        let prefix = path == "/" ? "/" : path + "/"

        while true {
            let count = getattrlistbulk(fd, &request, buffer, bufferSize, 0)
            if count < 0 { progress.addError(); break }
            if count == 0 { break }

            var entry = buffer
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                var field = entry + 4
                let common = field.loadUnaligned(as: UInt32.self)
                let dirAttrs = field.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
                let fileAttrs = field.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
                field += 20                               // attribute_set_t

                var name = ""
                if common & Self.cmnName != 0 {
                    let offset = Int(field.loadUnaligned(as: Int32.self))
                    name = String(cString: (field + offset).assumingMemoryBound(to: CChar.self))
                    field += 8                            // attrreference_t
                }
                var type: UInt32 = 0
                if common & Self.cmnObjType != 0 {
                    type = field.loadUnaligned(as: UInt32.self); field += 4
                }
                var flags: UInt32 = 0
                if common & Self.cmnFlags != 0 {
                    flags = field.loadUnaligned(as: UInt32.self); field += 4
                }
                var fileID: UInt64 = 0
                if common & Self.cmnFileID != 0 {
                    fileID = field.loadUnaligned(as: UInt64.self); field += 8
                }
                var mountStatus: UInt32 = 0
                if dirAttrs & Self.dirMountStatus != 0 {
                    mountStatus = field.loadUnaligned(as: UInt32.self); field += 4
                }
                var linkCount: UInt32 = 1
                if fileAttrs & Self.fileLinkCount != 0 {
                    linkCount = field.loadUnaligned(as: UInt32.self); field += 4
                }
                var alloc: Int64 = 0
                if fileAttrs & Self.fileAllocSize != 0 {
                    alloc = field.loadUnaligned(as: Int64.self); field += 8
                }
                entry += length

                guard !name.isEmpty else { continue }
                if type == Self.vDIR {
                    if mountStatus & Self.mountPoint != 0 { continue }
                    // iCloud / Google Drive / Dropbox folders that are only placeholders:
                    // listing them would make the provider fetch them from the network.
                    if flags & Self.sfDataless != 0 { continue }
                    let childPath = prefix + name
                    if !excluded.isEmpty && excluded.contains(childPath) { continue }
                    let child = FileNode(name: name, isDirectory: true)
                    child.parent = node
                    kids.append(child)
                    subdirs.append((child, childPath))
                } else if type == Self.vREG {
                    if linkCount > 1 && !links.insert(fileID) { alloc = 0 }
                    let child = FileNode(name: name, isDirectory: false, size: alloc)
                    child.parent = node
                    kids.append(child)
                    files += 1
                    bytes += alloc
                }
                // Symlinks, sockets, devices etc. take no meaningful space: skipped.
            }
        }

        node.children = kids
        progress.add(files: files, bytes: bytes, path: path)
        return subdirs
    }
}

/// A mounted, browsable volume shown on the home screen.
struct VolumeInfo: Identifiable {
    let id: URL
    let name: String
    let total: Int64
    let available: Int64
    let isInternal: Bool

    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func mounted() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey, .volumeIsBrowsableKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }

        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let important = v.volumeAvailableCapacityForImportantUsage ?? 0
            let available = important > 0 ? important : Int64(v.volumeAvailableCapacity ?? 0)
            return VolumeInfo(id: url,
                              name: v.volumeName ?? url.lastPathComponent,
                              total: Int64(total),
                              available: available,
                              isInternal: v.volumeIsInternal ?? false)
        }
    }
}
