import SwiftUI
import UniformTypeIdentifiers

struct ResultsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            FileListView()
                .frame(width: 340)
                .background(Theme.panel)
            Divider()
            VStack(spacing: 0) {
                Breadcrumbs()
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                SunburstView()
                    .padding(12)
                StatusLine()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                RiskInfoBar()
                CollectorBar()
            }
        }
    }
}

struct Breadcrumbs: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if let current = state.current {
                    let chain = current.lineage
                    ForEach(Array(chain.enumerated()), id: \.element.id) { index, node in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Button(node.displayName) { state.zoom(to: node) }
                            .buttonStyle(.plain)
                            .foregroundStyle(node === current ? Color.primary : Color.secondary)
                            .font(.callout.weight(node === current ? .semibold : .regular))
                    }
                }
            }
        }
    }
}

struct StatusLine: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            if let root = state.root {
                Label("\(root.size.formattedBytes) scanned · \(root.fileCount.formatted()) files in \(Duration.seconds(state.scanDuration).formatted(.time(pattern: .minuteSecond)))",
                      systemImage: "checkmark.circle")
            }
            if state.unscannedBytes > 1_000_000_000 {
                Label("\(state.unscannedBytes.formattedBytes) not visible (system, other users, snapshots, or protected folders)",
                      systemImage: "eye.slash")
                    .help("Grant Full Disk Access and rescan to see more. Some of this is APFS snapshots and purgeable space that only macOS manages.")
            }
            if state.scanErrors > 0 {
                Label("\(state.scanErrors) folders unreadable", systemImage: "exclamationmark.triangle")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

// MARK: - Sidebar list

struct FileListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let current = state.current {
                header(current)
                Divider()
                List {
                    ForEach(current.children) { node in
                        FileRow(node: node, parentSize: max(1, current.size))
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                            .listRowBackground(state.hovered === node ? Color.white.opacity(0.07) : Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func header(_ node: FileNode) -> some View {
        HStack(spacing: 10) {
            Button { state.goUp() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(node.parent == nil)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(node.size.formattedBytes) · \(node.children.count.formatted()) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct FileRow: View {
    @EnvironmentObject var state: AppState
    let node: FileNode
    let parentSize: Int64

    var body: some View {
        let fraction = Double(node.size) / Double(parentSize)
        let tint = state.color(for: node)
        let collected = state.isCollected(node)

        HStack(spacing: 10) {
            Image(systemName: node.symbolName)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .strikethrough(collected)
                        .foregroundStyle(collected ? Color.secondary : Color.primary)
                    Spacer(minLength: 6)
                    RiskBadge(assessment: RiskAssessor.assess(node), compact: true)
                    Text(node.size.formattedBytes)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06))
                        Capsule().fill(tint.opacity(0.85))
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 3)
            }
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { state.hover(node) } else if state.hovered === node { state.hover(nil) }
        }
        .onTapGesture(count: 2) {
            if node.isDirectory { state.zoom(to: node) } else { state.open(node) }
        }
        .onDrag { NSItemProvider(object: node.url as NSURL) }
        .contextMenu { NodeMenu(node: node) }
        .help(node.url.path)
    }
}

// MARK: - Collector

struct CollectorBar: View {
    @EnvironmentObject var state: AppState
    @State private var targeted = false
    @State private var confirmTrash = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.collector.isEmpty ? "tray" : "tray.full.fill")
                .font(.system(size: 22))
                .foregroundStyle(targeted ? Theme.accent : Color.secondary)

            if state.collector.isEmpty {
                Text("Drag files or folders here to collect them for deletion")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.collector) { node in
                            CollectedChip(node: node)
                        }
                    }
                }
                Text(state.collectorSize.formattedBytes)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Menu {
                    Button("Move to Trash") { confirmTrash = true }
                    Button("Delete Permanently…", role: .destructive) { confirmDelete = true }
                    Divider()
                    Button("Clear Collector") { state.collector.removeAll() }
                } label: {
                    Label(state.isDeleting ? "Deleting…" : "Delete", systemImage: "trash")
                } primaryAction: {
                    confirmTrash = true
                }
                .menuStyle(.button)
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .disabled(state.isDeleting)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 62)
        .background(targeted ? Theme.accent.opacity(0.15) : Theme.panel)
        .overlay(alignment: .top) { Divider() }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in state.addToCollector(path: url.path) }
                }
            }
            return true
        }
        .confirmationDialog("Move \(state.collector.count) item(s) to the Trash?",
                            isPresented: $confirmTrash) {
            Button("Move to Trash") { state.deleteCollected(permanently: false) }
        } message: {
            Text("\(state.collectorSize.formattedBytes) will move to the Trash. You can restore them from there until you empty it." + riskWarning)
        }
        .confirmationDialog("Permanently delete \(state.collector.count) item(s)?",
                            isPresented: $confirmDelete) {
            Button("Delete Permanently", role: .destructive) { state.deleteCollected(permanently: true) }
        } message: {
            Text("\(state.collectorSize.formattedBytes) will be erased immediately. This can't be undone." + riskWarning)
        }
    }
}

extension CollectorBar {
    /// Extra warning text for risky items in the collector.
    var riskWarning: String {
        let risky = state.collector
            .map { ($0, RiskAssessor.assess($0)) }
            .filter { $0.1.level >= .review }
            .sorted { $0.1.level > $1.1.level }
        guard !risky.isEmpty else { return "" }
        let lines = risky.prefix(6).map { "• \($0.0.name) — \($0.1.level.title): \($0.1.reason)" }
        return "\n\nCheck these first:\n" + lines.joined(separator: "\n") + (risky.count > 6 ? "\n…" : "")
    }
}

/// Explains the risk of whatever is under the pointer (or the folder being viewed).
struct RiskInfoBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let node = state.hovered ?? state.current, !node.isRoot || state.hovered != nil {
            let risk = RiskAssessor.assess(node)
            HStack(spacing: 10) {
                RiskBadge(assessment: risk)
                Text(node.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(risk.reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(risk.level.color.opacity(0.07))
            .overlay(alignment: .top) { Divider() }
        }
    }
}

struct CollectedChip: View {
    @EnvironmentObject var state: AppState
    let node: FileNode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.symbolName)
                .foregroundStyle(state.color(for: node))
            Text(node.name).lineLimit(1).frame(maxWidth: 160)
            Text(node.size.formattedBytes).foregroundStyle(.secondary)
            RiskBadge(assessment: RiskAssessor.assess(node), compact: true)
            Button {
                state.removeFromCollector(node)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .help(node.url.path)
        .contextMenu { NodeMenu(node: node) }
    }
}
