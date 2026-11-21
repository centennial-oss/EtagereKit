import CoreGraphics

/// The edges of the viewport, leading and trailing in reading order, that a ring's cards run past at rest (D12).
nonisolated struct RingOverflowEdges: Hashable, Sendable {
    var leading: Bool
    var trailing: Bool

    static let none = RingOverflowEdges(leading: false, trailing: false)
}

extension RingStrip {
    /// The edges the active ring's cards run past while the card at `rotation` rests at the Anchor Spot: a card in
    /// the rest window that starts before the leading inset, or ends after the trailing one (D12).
    func overflowEdges(at rotation: Int) -> RingOverflowEdges {
        let rest = restWindow(at: rotation, isActive: true)
        let first = rotation + rest.lowerBound
        let last = rotation + rest.upperBound
        let tolerance: CGFloat = 0.5
        let leading = restEdge(of: first, at: rotation, isTrailing: false) < geometry.leadingInset - tolerance
        let trailing = restEdge(of: last, at: rotation, isTrailing: true)
            > geometry.viewportLength - geometry.trailingInset + tolerance
        return RingOverflowEdges(leading: leading, trailing: trailing)
    }

    /// The leading or trailing edge of the card at a virtual index while `rotation` rests at the anchor.
    private func restEdge(of virtualIndex: Int, at rotation: Int, isTrailing: Bool) -> CGFloat {
        let center: CGFloat
        let length: CGFloat
        if widths.isUniform {
            let slot = Double(virtualIndex - rotation)
            center = geometry.center(at: slot)
            length = geometry.length(at: slot)
        } else {
            center = geometry.center(of: virtualIndex, phase: Double(rotation), widths: widths)
            length = geometry.length(of: virtualIndex, phase: Double(rotation), widths: widths)
        }
        return center + (isTrailing ? length : -length) / 2
    }
}
