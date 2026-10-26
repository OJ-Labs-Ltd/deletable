import SwiftUI

struct HomeView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var cleaner: Cleaner

    private let columns = [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("Volumes") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ForEach(state.volumes) { volume in
                            VolumeCard(volume: volume) { state.startScan(volume.id) }
                        }
                    }
                }

                section("Shortcuts") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        ActionCard(symbol: "house.fill", title: "Home Folder",
                                   subtitle: FileManager.default.homeDirectoryForCurrentUser.path,
                                   tint: .orange) {
                            state.startScan(FileManager.default.homeDirectoryForCurrentUser)
                        }
                        ActionCard(symbol: "folder.badge.gearshape", title: "Scan a Folder…",
                                   subtitle: "Pick any folder or external drive", tint: .teal) {
                            state.chooseFolderAndScan()
                        }
                        ActionCard(symbol: "sparkles", title: "Quick Clean",
                                   subtitle: "Caches, logs, developer junk and Trash", tint: .pink) {
                            state.screen = .clean
                            cleaner.measure()
                        }
                        if let root = state.root {
                            ActionCard(symbol: "chart.pie.fill", title: "Back to Last Scan",
                                       subtitle: "\(root.displayName) · \(root.size.formattedBytes)",
                                       tint: .purple) {
                                state.screen = .results
                            }
                        }
                    }
                }

                fullDiskAccessNote
            }
            .padding(32)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            MiniRings()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("DiskLens")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("See what's using your disk, collect what you don't need, and clear it.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                state.refreshVolumes()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            content()
        }
    }

    private var fullDiskAccessNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 6) {
                Text("For complete results, give DiskLens Full Disk Access")
                    .font(.headline)
                Text("Without it, macOS hides Mail, Messages, Safari data, the Trash and other protected folders, and their space shows up as unscanned. Add DiskLens in System Settings › Privacy & Security › Full Disk Access, then relaunch it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Privacy Settings") { AppState.openFullDiskAccessSettings() }
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
    }
}

struct VolumeCard: View {
    let volume: VolumeInfo
    let scan: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: volume.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name).font(.headline)
                    Text(volume.id.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            UsageBar(fraction: volume.usedFraction)
                .frame(height: 8)
            HStack {
                Text("\(volume.available.formattedBytes) free")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("of \(volume.total.formattedBytes)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            Button(action: scan) {
                Text("Scan").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(hovering ? Theme.accent.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

struct ActionCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(hovering ? tint.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct UsageBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent, fraction > 0.9 ? .red : .purple],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * min(1, fraction)))
            }
        }
    }
}

/// Small decorative logo used on the home screen.
struct MiniRings: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) / 2
            let rings: [(CGFloat, CGFloat, [Double])] = [
                (r * 0.34, r * 0.64, [0.42, 0.28, 0.18, 0.12]),
                (r * 0.68, r * 0.98, [0.22, 0.14, 0.06, 0.18, 0.1, 0.12, 0.08, 0.1]),
            ]
            for (inner, outer, parts) in rings {
                var a = 0.0
                for (i, part) in parts.enumerated() {
                    let span = part * 2 * .pi
                    let path = SunburstGeometry.sector(center: c, inner: inner, outer: outer,
                                                       start: a, end: a + span)
                    ctx.fill(path, with: .color(Color(hue: Double(i) / Double(parts.count) * 0.85,
                                                      saturation: inner > r * 0.5 ? 0.45 : 0.75,
                                                      brightness: 0.9)))
                    ctx.stroke(path, with: .color(Theme.background), lineWidth: 1)
                    a += span
                }
            }
        }
    }
}
