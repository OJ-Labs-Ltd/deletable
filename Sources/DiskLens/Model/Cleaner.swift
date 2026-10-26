import SwiftUI

/// A well-known location whose contents are usually safe to clear.
struct CleanCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let root: URL
    /// Only items not modified for this many days are included.
    var olderThanDays: Int? = nil
    /// Delete outright instead of moving to the Trash (used for the Trash itself).
    var permanent = false
    var selectedByDefault = true
}

@MainActor
final class Cleaner: ObservableObject {
    struct Result: Sendable {
        var size: Int64
        var itemCount: Int
        var error: String?
    }

    let categories: [CleanCategory]
    @Published var results: [String: Result] = [:]
    @Published var selected: Set<String> = []
    @Published var isMeasuring = false
    @Published var isCleaning = false
    @Published var message: String?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func p(_ rel: String) -> URL { home.appendingPathComponent(rel, isDirectory: true) }

        categories = [
            CleanCategory(id: "caches", title: "User caches",
                          detail: "App caches in ~/Library/Caches. Apps rebuild these; quit big apps first.",
                          symbol: "archivebox.fill", root: p("Library/Caches")),
            CleanCategory(id: "logs", title: "Logs",
                          detail: "Diagnostic and app logs in ~/Library/Logs.",
                          symbol: "list.bullet.rectangle.fill", root: p("Library/Logs")),
            CleanCategory(id: "derived", title: "Xcode DerivedData",
                          detail: "Build products and indexes. Xcode recreates them on the next build.",
                          symbol: "hammer.fill", root: p("Library/Developer/Xcode/DerivedData")),
            CleanCategory(id: "devicesupport", title: "iOS DeviceSupport",
                          detail: "Debug symbols for old iOS versions. Re-downloaded when a device connects.",
                          symbol: "iphone", root: p("Library/Developer/Xcode/iOS DeviceSupport")),
            CleanCategory(id: "simcaches", title: "Simulator caches",
                          detail: "CoreSimulator cache files.",
                          symbol: "ipad.and.iphone", root: p("Library/Developer/CoreSimulator/Caches")),
            CleanCategory(id: "archives", title: "Xcode Archives",
                          detail: "Archived app builds. Keep any you still need for crash symbolication.",
                          symbol: "shippingbox.fill", root: p("Library/Developer/Xcode/Archives"),
                          selectedByDefault: false),
            CleanCategory(id: "npm", title: "npm cache",
                          detail: "Downloaded packages in ~/.npm/_cacache.",
                          symbol: "cube.box.fill", root: p(".npm/_cacache")),
            CleanCategory(id: "bun", title: "Bun cache",
                          detail: "Downloaded packages in ~/.bun/install/cache.",
                          symbol: "cube.box.fill", root: p(".bun/install/cache")),
            CleanCategory(id: "gradle", title: "Gradle caches",
                          detail: "Dependency and build caches in ~/.gradle/caches.",
                          symbol: "cube.box.fill", root: p(".gradle/caches")),
            CleanCategory(id: "cocoapods", title: "CocoaPods cache",
                          detail: "Pod specs and downloads in ~/.cocoapods/repos.",
                          symbol: "cube.box.fill", root: p(".cocoapods/repos"),
                          selectedByDefault: false),
            CleanCategory(id: "downloads", title: "Old downloads",
                          detail: "Items in Downloads untouched for 90+ days. Review before cleaning.",
                          symbol: "arrow.down.circle.fill", root: p("Downloads"),
                          olderThanDays: 90, selectedByDefault: false),
            CleanCategory(id: "trash", title: "Trash",
                          detail: "Permanently deletes everything already in your Trash.",
                          symbol: "trash.fill", root: p(".Trash"), permanent: true),
        ]
        selected = Set(categories.filter(\.selectedByDefault).map(\.id))
    }

    var visibleCategories: [CleanCategory] {
        categories.filter { results[$0.id] != nil }
    }

    var selectedTotal: Int64 {
        selected.reduce(0) { $0 + (results[$1]?.size ?? 0) }
    }

    func measure() {
        guard !isMeasuring else { return }
        isMeasuring = true
        let cats = categories
        Task.detached(priority: .userInitiated) {
            var out: [String: Result] = [:]
            for cat in cats {
                guard FileManager.default.fileExists(atPath: cat.root.path) else { continue }
                do {
                    let items = try Cleaner.items(in: cat)
                    let size = items.reduce(Int64(0)) { $0 + Cleaner.allocatedSize(of: $1) }
                    out[cat.id] = Result(size: size, itemCount: items.count, error: nil)
                } catch {
                    out[cat.id] = Result(size: 0, itemCount: 0,
                                         error: "Needs Full Disk Access to read this folder.")
                }
            }
            let measured = out
            await self.finishMeasuring(measured)
        }
    }

    func cleanSelected() {
        let cats = categories.filter { selected.contains($0.id) && (results[$0.id]?.itemCount ?? 0) > 0 }
        guard !cats.isEmpty else { return }
        isCleaning = true
        Task.detached(priority: .userInitiated) {
            var freed: Int64 = 0
            var failures = 0
            let fm = FileManager.default
            for cat in cats {
                guard let items = try? Cleaner.items(in: cat) else { failures += 1; continue }
                for item in items {
                    let size = Cleaner.allocatedSize(of: item)
                    do {
                        if cat.permanent {
                            try fm.removeItem(at: item)
                        } else {
                            try fm.trashItem(at: item, resultingItemURL: nil)
                        }
                        freed += size
                    } catch {
                        failures += 1
                    }
                }
            }
            let total = freed
            let failed = failures
            let movedToTrash = cats.contains { !$0.permanent }
            await self.finishCleaning(freed: total, failures: failed, movedToTrash: movedToTrash)
        }
    }

    private func finishMeasuring(_ measured: [String: Result]) {
        results = measured
        isMeasuring = false
    }

    private func finishCleaning(freed: Int64, failures: Int, movedToTrash: Bool) {
        isCleaning = false
        var text = "Cleaned \(freed.formattedBytes)."
        if movedToTrash {
            text += " Items were moved to the Trash — empty it to reclaim the space."
        }
        if failures > 0 { text += " \(failures) item(s) were in use or protected and were skipped." }
        message = text
        measure()
    }

    // MARK: File-system helpers (run off the main thread)

    nonisolated static func items(in cat: CleanCategory) throws -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let all = try FileManager.default.contentsOfDirectory(
            at: cat.root, includingPropertiesForKeys: keys, options: [])
            .filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }
        guard let days = cat.olderThanDays else { return all }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        return all.filter { url in
            let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            return date < cutoff
        }
    }

    nonisolated static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey,
                                         .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isSymbolicLink == true { return 0 }
        if v.isDirectory != true {
            return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let walker = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in true }) else { return 0 }
        while let next = walker.nextObject() as? URL {
            guard let r = try? next.resourceValues(forKeys: keys),
                  r.isDirectory != true, r.isSymbolicLink != true else { continue }
            total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
        }
        return total
    }
}
