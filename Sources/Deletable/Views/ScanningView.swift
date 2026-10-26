import SwiftUI

struct ScanningView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            SpinningRings()
                .frame(width: 180, height: 180)

            VStack(spacing: 6) {
                Text("Scanning \(state.scanTarget.map { FileManager.default.displayName(atPath: $0.path) } ?? "")")
                    .font(.title2.weight(.semibold))
                Text(state.scanStats.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 560)
            }

            HStack(spacing: 36) {
                stat(state.scanStats.bytes.formattedBytes, "found")
                stat(state.scanStats.files.formatted(), "files")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    stat(Duration.seconds(context.date.timeIntervalSince(state.scanStarted))
                            .formatted(.time(pattern: .minuteSecond)), "elapsed")
                }
            }

            Button("Cancel") { state.userCancelledScan() }
                .keyboardShortcut(.cancelAction)
                .controlSize(.large)
            Spacer()
        }
        .padding(40)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 110)
    }
}

/// Animated concentric arcs shown while scanning.
struct SpinningRings: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2
                for i in 0..<4 {
                    let inner = r * (0.3 + CGFloat(i) * 0.17)
                    let outer = inner + r * 0.13
                    let speed = (i.isMultiple(of: 2) ? 1.0 : -0.7) * (0.6 + Double(i) * 0.15)
                    let start = (t * speed).truncatingRemainder(dividingBy: 2 * .pi)
                    let span = 2 * .pi * (0.25 + 0.15 * sin(t * 0.8 + Double(i)))
                    let path = SunburstGeometry.sector(center: c, inner: inner, outer: outer,
                                                       start: start, end: start + span)
                    ctx.fill(path, with: .color(Color(hue: (Double(i) * 0.18 + 0.55).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.95)))
                }
            }
        }
    }
}
