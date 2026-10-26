import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    enum Screen { case home, scanning, results, clean }

    @Published var screen: Screen = .home
    @Published var volumes: [VolumeInfo] = []

    // Scan
    @Published var scanTarget: URL?
    @Published var scanStats = ScanProgress.Snapshot()
    @Published var scanStarted = Date()
    private var progress: ScanProgress?
    private var pollTask: Task<Void, Never>?

    // Results
    @Published var root: FileNode?
    @Published var current: FileNode?
    @Published var hovered: FileNode?
    @Published var segments: [Segment] = []
    @Published var unscannedBytes: Int64 = 0
    @Published var scanErrors = 0
    @Published var scanDuration: TimeInterval = 0
    private var hueByNode: [ObjectIdentifier: Double] = [:]

    // Collector
    @Published var collector: [FileNode] = []
    @Published var isDeleting = false
    @Published var alertMessage: String?
    /// Items the user can't remove without an administrator password.
    @Published var adminCandidates: [FileNode] = []
    @Published var adminPermanent = false
    @Published var showAdminPrompt = false

    init() { refreshVolumes() }

    func refreshVolumes() { volumes = VolumeInfo.mounted() }

    // MARK: Scanning

    func startScan(_ url: URL) {
        cancelScan()
        let progress = ScanProgress()
        self.progress = progress
        scanTarget = url
        scanStats = .init()
        scanStarted = Date()
        collector = []
        hovered = nil
        screen = .scanning

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.scanStats = progress.snapshot()
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }

        Task.detached(priority: .userInitiated) {
            let tree = await DiskScanner.scan(root: url, progress: progress)
            await self.finishScan(tree, progress: progress)
        }
    }

    func cancelScan() {
        progress?.cancel()
        progress = nil
        pollTask?.cancel()
        pollTask = nil
    }

    func userCancelledScan() {
        cancelScan()
        screen = root == nil ? .home : .results
    }

    private func finishScan(_ tree: FileNode, progress finished: ScanProgress) {
        // Ignore results from a scan that was cancelled or superseded by a newer one.
        guard finished === progress, !finished.isCancelled else { return }
        let errors = finished.snapshot().errors
        pollTask?.cancel()
        pollTask = nil
        progress = nil
        scanDuration = Date().timeIntervalSince(scanStarted)
        root = tree
        current = tree
        scanErrors = errors
        if let volume = volumes.first(where: { $0.id.standardizedFileURL == tree.url.standardizedFileURL }) {
            unscannedBytes = max(0, volume.used - tree.size)
        } else {
            unscannedBytes = 0
        }
        rebuildLayout()
        screen = .results
    }

    func rescan() {
        if let url = root?.url { startScan(url) }
    }

    // MARK: Navigation

    func zoom(to node: FileNode) {
        guard node.isDirectory, node !== current else { return }
        current = node
        hovered = nil
        rebuildLayout()
    }

    func goUp() {
        if let parent = current?.parent { zoom(to: parent) }
    }

    func hover(_ node: FileNode?) {
        if hovered !== node { hovered = node }
    }

    private func rebuildLayout() {
        guard let current else { segments = []; return }
        segments = SunburstLayout.build(root: current)
        var map: [ObjectIdentifier: Double] = [:]
        for seg in segments where seg.depth == 1 {
            if let node = seg.node { map[ObjectIdentifier(node)] = seg.hue }
        }
        hueByNode = map
    }

    /// Colour for a node in the list, matching its top-level wedge in the map.
    func color(for node: FileNode) -> Color {
        var n: FileNode? = node
        while let q = n {
            if let hue = hueByNode[ObjectIdentifier(q)] {
                return Color(hue: hue, saturation: node.isDirectory ? 0.7 : 0.35, brightness: 0.85)
            }
            n = q.parent
        }
        return Color(white: 0.5)
    }

    // MARK: Collector

    var collectorSize: Int64 { collector.reduce(0) { $0 + $1.size } }

    func isCollected(_ node: FileNode) -> Bool {
        collector.contains { $0 === node || $0.isAncestor(of: node) }
    }

    func addToCollector(_ node: FileNode) {
        guard !node.isRoot, !isCollected(node) else { return }
        collector.removeAll { node.isAncestor(of: $0) }
        collector.append(node)
    }

    func addToCollector(path: String) {
        if let node = root?.find(path: path) { addToCollector(node) }
    }

    func removeFromCollector(_ node: FileNode) {
        collector.removeAll { $0 === node }
    }

    func deleteCollected(permanently: Bool) {
        let items = collector.map { ($0, $0.url) }
        guard !items.isEmpty else { return }
        isDeleting = true

        Task.detached(priority: .userInitiated) {
            var removed: [FileNode] = []
            var failures: [String] = []
            var denied: [FileNode] = []
            let fm = FileManager.default
            for (node, url) in items {
                do {
                    if permanently {
                        try fm.removeItem(at: url)
                    } else {
                        try fm.trashItem(at: url, resultingItemURL: nil)
                    }
                    removed.append(node)
                } catch {
                    if AppState.isPermissionError(error) {
                        denied.append(node)
                    } else {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            let done = removed
            let failed = failures
            let needsAdmin = denied
            await self.finishDelete(removed: done, failures: failed, needsAdmin: needsAdmin,
                                    permanently: permanently)
        }
    }

    nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain && [257, 513].contains(e.code) { return true }
        if e.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(e.code) { return true }
        if let underlying = e.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }

    private func finishDelete(removed: [FileNode], failures: [String], needsAdmin: [FileNode],
                              permanently: Bool) {
        isDeleting = false
        let freed = removed.reduce(Int64(0)) { $0 + $1.size }
        for node in removed {
            if let current, node === current || node.isAncestor(of: current) {
                self.current = node.parent
            }
            if let hovered, node === hovered || node.isAncestor(of: hovered) {
                self.hovered = nil
            }
            node.removeFromParent()
        }
        collector.removeAll { c in removed.contains { $0 === c } }
        rebuildLayout()
        refreshVolumes()

        var failures = failures
        // Offer the administrator password for system-owned items, but never for high-risk ones.
        let allowed = needsAdmin.filter { RiskAssessor.assess($0).level != .danger }
        for node in needsAdmin where !allowed.contains(where: { $0 === node }) {
            failures.append("\(node.name): protected system or app data (High risk), not removed.")
        }
        if !allowed.isEmpty {
            adminPermanent = permanently
            adminCandidates = allowed
            showAdminPrompt = true
            if !failures.isEmpty {
                alertMessage = "Also couldn't remove:\n\n" + failures.prefix(8).joined(separator: "\n")
            }
            return
        }

        if !failures.isEmpty {
            alertMessage = "Couldn't remove \(failures.count) item(s):\n\n"
                + failures.prefix(8).joined(separator: "\n")
                + (failures.count > 8 ? "\n…" : "")
        } else if !permanently && freed > 0 {
            alertMessage = "Moved \(freed.formattedBytes) to the Trash. Empty the Trash to free the space."
        }
    }

    /// Removes `adminCandidates` using the standard macOS administrator password prompt.
    func removeWithAdministrator() {
        let nodes = adminCandidates
        let permanently = adminPermanent
        adminCandidates = []
        showAdminPrompt = false
        guard !nodes.isEmpty else { return }

        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let fm = FileManager.default
        let trash = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
        var commands: [String] = []
        for node in nodes {
            let source = node.url.path
            if permanently {
                commands.append("/bin/rm -rf \(q(source))")
            } else {
                var dest = trash.appendingPathComponent(node.name)
                if fm.fileExists(atPath: dest.path) {
                    let stamp = Int(Date().timeIntervalSince1970)
                    dest = trash.appendingPathComponent("\(node.name) \(stamp)")
                }
                commands.append("/bin/mv \(q(source)) \(q(dest.path))")
            }
        }
        let shell = commands.joined(separator: " && ")
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with prompt "
            + "\"Deletable wants to remove items that belong to the system.\" with administrator privileges"

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
            if code != -128 {   // -128: the user pressed Cancel
                let text = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                alertMessage = "Couldn't remove the items:\n\n\(text)"
            }
            return
        }

        let freed = nodes.reduce(Int64(0)) { $0 + $1.size }
        finishDelete(removed: nodes, failures: [], needsAdmin: [], permanently: true)
        alertMessage = permanently
            ? "Deleted \(freed.formattedBytes)."
            : "Moved \(freed.formattedBytes) to the Trash. Finder will ask for your password when you empty it."
    }

    // MARK: Finder helpers

    func reveal(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func open(_ node: FileNode) {
        NSWorkspace.shared.open(node.url)
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { startScan(url) }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
