import Foundation

/// One file or folder in a scanned tree. Kept deliberately small because a full
/// disk scan can create millions of these: the URL is derived from the parent chain.
final class FileNode: Identifiable, Hashable, @unchecked Sendable {
    let name: String
    let isDirectory: Bool
    var size: Int64
    var fileCount: Int
    var children: [FileNode] = []
    // unowned(unsafe): a scan creates millions of nodes and weak references are slow to
    // create; the tree is always owned from the root, so parents outlive their children.
    unowned(unsafe) var parent: FileNode?
    private let rootURL: URL?

    init(name: String, isDirectory: Bool, size: Int64 = 0, rootURL: URL? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.fileCount = isDirectory ? 0 : 1
        self.rootURL = rootURL
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }
    static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    var url: URL {
        if let rootURL { return rootURL }
        guard let parent else { return URL(fileURLWithPath: name) }
        return parent.url.appendingPathComponent(name, isDirectory: isDirectory)
    }

    var displayName: String {
        if let rootURL {
            let n = FileManager.default.displayName(atPath: rootURL.path)
            return n.isEmpty ? rootURL.path : n
        }
        return name
    }

    var isRoot: Bool { parent == nil }

    /// Root first, self last.
    var lineage: [FileNode] {
        var chain: [FileNode] = [self]
        var p = parent
        while let q = p { chain.append(q); p = q.parent }
        return chain.reversed()
    }

    func isAncestor(of other: FileNode) -> Bool {
        var p = other.parent
        while let q = p {
            if q === self { return true }
            p = q.parent
        }
        return false
    }

    /// Post-order pass after scanning: sum sizes, count files, sort children largest first.
    func finalize() {
        guard isDirectory else { return }
        var total: Int64 = 0
        var count = 0
        for child in children {
            child.finalize()
            total += child.size
            count += child.fileCount
        }
        size = total
        fileCount = count
        children.sort { $0.size > $1.size }
    }

    /// Detach after deletion and subtract this node's size from every ancestor.
    func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var p: FileNode? = parent
        while let q = p {
            q.size -= size
            q.fileCount -= fileCount
            q.children.sort { $0.size > $1.size }
            p = q.parent
        }
        self.parent = nil
    }

    /// Locate a descendant by absolute path.
    func find(path: String) -> FileNode? {
        let base = url.standardizedFileURL.path
        let target = URL(fileURLWithPath: path).standardizedFileURL.path
        if target == base { return self }
        let prefix = base == "/" ? "/" : base + "/"
        guard target.hasPrefix(prefix) else { return nil }
        var node = self
        for component in target.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == component }) else { return nil }
            node = next
        }
        return node
    }

    var symbolName: String {
        if isDirectory {
            let ext = (name as NSString).pathExtension.lowercased()
            return ["app", "bundle", "framework", "plugin", "xcarchive", "photoslibrary"].contains(ext)
                ? "shippingbox.fill" : "folder.fill"
        }
        switch (name as NSString).pathExtension.lowercased() {
        case "mp4", "mov", "mkv", "avi", "m4v", "webm": return "film.fill"
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "raw", "psd", "webp": return "photo.fill"
        case "mp3", "wav", "aac", "m4a", "flac", "aiff": return "music.note"
        case "zip", "gz", "tar", "rar", "7z", "xz", "bz2", "tgz": return "doc.zipper"
        case "dmg", "iso", "img", "pkg", "ipsw", "vmdk", "qcow2", "hdd": return "externaldrive.fill"
        case "pdf": return "doc.richtext.fill"
        default: return "doc.fill"
        }
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
