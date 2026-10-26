import SwiftUI
import AppKit

enum SunburstGeometry {
    /// Annular sector. Angles are radians clockwise from 12 o'clock.
    static func sector(center: CGPoint, inner: CGFloat, outer: CGFloat, start: Double, end: Double) -> Path {
        var p = Path()
        let a0 = Angle(radians: start - .pi / 2)
        let a1 = Angle(radians: end - .pi / 2)
        p.addArc(center: center, radius: outer, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: center, radius: inner, startAngle: a1, endAngle: a0, clockwise: true)
        p.closeSubpath()
        return p
    }
}

private struct RingMetrics {
    let center: CGPoint
    let hole: CGFloat
    let ring: CGFloat

    init(size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = max(60, min(size.width, size.height) / 2 - 18)
        hole = radius * 0.24
        ring = (radius - hole) / CGFloat(SunburstLayout.maxDepth)
    }

    func radii(depth: Int) -> (CGFloat, CGFloat) {
        let inner = hole + CGFloat(depth - 1) * ring + 1
        return (inner, inner + ring - 1)
    }

    enum Hit { case center, segment(Segment), none }

    func hit(_ point: CGPoint, in segments: [Segment]) -> Hit {
        let dx = point.x - center.x
        let dy = point.y - center.y
        let r = sqrt(dx * dx + dy * dy)
        if r < hole { return .center }
        let depth = Int((r - hole) / ring) + 1
        guard depth <= SunburstLayout.maxDepth else { return .none }
        var angle = atan2(Double(dy), Double(dx)) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        if let seg = segments.first(where: { $0.depth == depth && angle >= $0.start && angle < $0.end }) {
            return .segment(seg)
        }
        return .none
    }
}

struct SunburstView: View {
    @EnvironmentObject var state: AppState
    @State private var hoverCenter = false

    var body: some View {
        GeometryReader { geo in
            let m = RingMetrics(size: geo.size)
            ZStack {
                Canvas { ctx, _ in
                    let hovered = state.hovered
                    for seg in state.segments {
                        let (inner, outer) = m.radii(depth: seg.depth)
                        let path = SunburstGeometry.sector(center: m.center, inner: inner, outer: outer,
                                                           start: seg.start, end: seg.end)
                        let isHot = hovered != nil && seg.node === hovered
                        let inHotBranch = hovered.map { h in seg.node.map { h.isAncestor(of: $0) } ?? false } ?? false
                        ctx.fill(path, with: .color(seg.color))
                        if isHot {
                            ctx.fill(path, with: .color(Color.white.opacity(0.35)))
                        } else if inHotBranch {
                            ctx.fill(path, with: .color(Color.white.opacity(0.15)))
                        } else if let node = seg.node, state.isCollected(node) {
                            ctx.fill(path, with: .color(Color.black.opacity(0.55)))
                        }
                        if seg.span > 0.003 {
                            ctx.stroke(path, with: .color(Theme.background), lineWidth: 0.8)
                        }
                    }
                    // Centre disc
                    let disc = Path(ellipseIn: CGRect(x: m.center.x - m.hole + 2, y: m.center.y - m.hole + 2,
                                                      width: (m.hole - 2) * 2, height: (m.hole - 2) * 2))
                    ctx.fill(disc, with: .color(hoverCenter && state.current?.parent != nil
                                                ? Theme.panel.opacity(0.9) : Theme.panel))
                }

                centerLabel
                    .frame(width: max(40, m.hole * 1.7), height: max(40, m.hole * 1.7))
                    .position(m.center)
                    .allowsHitTesting(false)

                if state.segments.isEmpty {
                    Text("This folder is empty")
                        .foregroundStyle(.secondary)
                        .offset(y: m.hole + 30)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    switch m.hit(point, in: state.segments) {
                    case .center:
                        hoverCenter = true
                        state.hover(nil)
                    case .segment(let seg):
                        hoverCenter = false
                        state.hover(seg.node)
                    case .none:
                        hoverCenter = false
                        state.hover(nil)
                    }
                case .ended:
                    hoverCenter = false
                    state.hover(nil)
                }
            }
            .onTapGesture(count: 1, coordinateSpace: .local) { point in
                switch m.hit(point, in: state.segments) {
                case .center:
                    state.goUp()
                case .segment(let seg):
                    if let node = seg.node {
                        if node.isDirectory { state.zoom(to: node) } else { state.reveal(node) }
                    }
                case .none:
                    break
                }
            }
            .onDrag {
                if let node = state.hovered {
                    return NSItemProvider(object: node.url as NSURL)
                }
                return NSItemProvider()
            }
            .contextMenu {
                if let node = state.hovered {
                    NodeMenu(node: node)
                }
            }
        }
    }

    @ViewBuilder
    private var centerLabel: some View {
        let shown = state.hovered ?? state.current
        VStack(spacing: 4) {
            if hoverCenter, state.current?.parent != nil {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent)
                Text("Up").font(.caption).foregroundStyle(.secondary)
            } else if let node = shown {
                Text(node.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                Text(node.size.formattedBytes)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(state.hovered == nil ? Theme.accent : state.color(for: node))
                if node.isDirectory {
                    Text("\(node.fileCount.formatted()) files")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if state.hovered != nil {
                    RiskBadge(assessment: RiskAssessor.assess(node))
                }
            }
        }
    }
}

/// Shared context-menu items for a node.
struct NodeMenu: View {
    @EnvironmentObject var state: AppState
    let node: FileNode

    var body: some View {
        if node.isDirectory {
            Button("Zoom In") { state.zoom(to: node) }
        }
        Button("Reveal in Finder") { state.reveal(node) }
        Button("Open") { state.open(node) }
        Divider()
        if state.isCollected(node) {
            Button("Remove from Collector") { state.removeFromCollector(node) }
                .disabled(!state.collector.contains { $0 === node })
        } else {
            let risk = RiskAssessor.assess(node)
            Button(risk.level == .danger ? "Add to Collector (High risk)" : "Add to Collector") {
                state.addToCollector(node)
            }
                .disabled(node.isRoot)
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
    }
}
