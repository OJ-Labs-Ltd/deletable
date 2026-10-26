import SwiftUI

/// One ring segment of the disk map. Angles are radians clockwise from 12 o'clock.
struct Segment: Identifiable {
    let id: Int
    let node: FileNode?      // nil = the grey "smaller items" remainder
    let depth: Int           // 1 = innermost ring
    let start: Double
    let end: Double
    let hue: Double

    var span: Double { end - start }

    var color: Color {
        guard let node else { return Color(white: 0.32) }
        let d = Double(depth - 1)
        var saturation = max(0.28, 0.78 - d * 0.09)
        let brightness = min(0.96, 0.62 + d * 0.06)
        if !node.isDirectory { saturation *= 0.45 }
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

enum SunburstLayout {
    static let maxDepth = 6
    /// Segments thinner than this (≈0.35°) are folded into a grey remainder.
    static let minSpan = 0.006

    static func build(root: FileNode) -> [Segment] {
        var out: [Segment] = []
        out.reserveCapacity(4096)
        var nextID = 0

        func walk(_ node: FileNode, depth: Int, start: Double, span: Double, hue: Double?) {
            guard depth <= maxDepth, node.isDirectory, node.size > 0 else { return }
            var angle = start
            let end = start + span
            for child in node.children {
                let childSpan = span * Double(child.size) / Double(node.size)
                if childSpan < minSpan {
                    // Children are sorted largest first, so everything after this is small too.
                    if end - angle >= minSpan * 0.5 {
                        out.append(Segment(id: nextID, node: nil, depth: depth,
                                           start: angle, end: end, hue: hue ?? 0))
                        nextID += 1
                    }
                    break
                }
                let h = hue ?? ((angle + childSpan / 2) / (2 * .pi) * 0.92)
                out.append(Segment(id: nextID, node: child, depth: depth,
                                   start: angle, end: angle + childSpan, hue: h))
                nextID += 1
                walk(child, depth: depth + 1, start: angle, span: childSpan, hue: h)
                angle += childSpan
            }
        }

        walk(root, depth: 1, start: 0, span: 2 * .pi, hue: nil)
        return out
    }
}
