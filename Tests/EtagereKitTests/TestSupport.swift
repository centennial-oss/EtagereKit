import CoreGraphics
import EtagereKit
import SwiftUI
import Testing

/// A plain 16:9 card with string IDs, like a host app's video card.
nonisolated struct PlainCard: ShelfCardContent {
    let id: String
    var title: String

    init(_ id: String, title: String? = nil) {
        self.id = id
        self.title = title ?? id
    }

    var accessibilityTitle: String { title }

    @MainActor
    func makeFace(context: ShelfCardContext) -> some View {
        Text(title)
    }
}

/// The reuse card of T23: box art with integer IDs and a 0.71 aspect ratio. Nothing but its face uses SwiftUI.
/// Its conformance sits in a `nonisolated extension`, the form a host uses to keep the face in its own file
/// (`ShelfCardContent`'s documentation); a plain extension would not compile in this MainActor-default target.
nonisolated struct BoxArtCard: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
}

nonisolated extension BoxArtCard: ShelfCardContent {
    static var faceAspectRatio: CGFloat { 0.71 }

    var accessibilityTitle: String { "\(name), game" }

    @MainActor
    func makeFace(context: ShelfCardContext) -> some View {
        Rectangle()
            .fill(context.isActive ? Color.accentColor : Color.gray)
            .overlay { Text(name) }
    }
}

/// Test data and geometry builders.
nonisolated enum Fixture {
    static let anchors = RingAnchor.allCases
    static let ringSizes = [1, 2, 3, 4, 8, 40]
    static let viewportWidths: [CGFloat] = [400, 1280, 1920]

    /// Card IDs "A", "B", ... for small rings and "C0", "C1", ... for large ones.
    static func cardIDs(_ count: Int) -> [String] {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".map(String.init)
        return count <= letters.count ? Array(letters.prefix(count)) : (0..<count).map { "C\($0)" }
    }

    static func cards(_ count: Int) -> [PlainCard] {
        cardIDs(count).map { PlainCard($0) }
    }

    static func shelf(_ id: String, cardCount: Int, emptyMessage: String? = nil) -> Shelf<PlainCard> {
        Shelf(id: id, title: id.capitalized, cards: cards(cardCount).map { PlainCard("\(id)-\($0.id)") },
              emptyMessage: emptyMessage)
    }

    /// A model with one shelf per entry of `cardCounts`, shelf IDs "s0", "s1", ...
    @MainActor
    static func model(
        cardCounts: [Int], configuration: EtagereConfiguration = EtagereConfiguration()
    ) -> EtagereModel<PlainCard> {
        EtagereModel(
            shelves: cardCounts.enumerated().map { shelf("s\($0.offset)", cardCount: $0.element) },
            configuration: configuration
        )
    }

    /// The prototype's reference ring (tvOS-like, 1920 pt): w = 300, W = 390, p = 32, insets 80.
    static func referenceGeometry(anchor: RingAnchor = .leading, viewport: CGFloat = 1920) -> RingGeometry {
        RingGeometry(
            viewportLength: viewport, leadingInset: 80, trailingInset: 80,
            idleLength: 300, activeLength: 390, spacing: 32, anchor: anchor
        )
    }

    /// A shelf ring at a viewport width with that width's starting metrics (not tvOS) and the inset a host
    /// would use there.
    static func shelfGeometry(width: CGFloat, anchor: RingAnchor) -> RingGeometry {
        let metrics = EtagereMetrics.automatic.resolved(containerWidth: width, isTelevision: false)
        let inset: CGFloat = width < 500 ? 16 : 60
        var geometry = RingGeometry(
            shelfMetrics: metrics, viewportWidth: width, leadingInset: inset, trailingInset: inset,
            alignment: .leading
        )
        geometry.anchor = anchor
        return geometry
    }
}

/// One geometry case of the parameterized tests: an anchor, a ring size and a viewport width.
nonisolated struct RingCase: Sendable, CustomTestStringConvertible {
    let anchor: RingAnchor
    let itemCount: Int
    let width: CGFloat

    var testDescription: String { "\(anchor) N=\(itemCount) V=\(Int(width))" }

    var geometry: RingGeometry { Fixture.shelfGeometry(width: width, anchor: anchor) }

    /// Every anchor x N in {1, 2, 3, 4, 8, 40} x V in {400, 1280, 1920}.
    static let all: [RingCase] = Fixture.anchors.flatMap { anchor in
        Fixture.ringSizes.flatMap { size in
            Fixture.viewportWidths.map { RingCase(anchor: anchor, itemCount: size, width: $0) }
        }
    }
}

/// One anchor and viewport width (for tests that do not depend on the ring size).
nonisolated struct ViewportCase: Sendable, CustomTestStringConvertible {
    let anchor: RingAnchor
    let width: CGFloat

    var testDescription: String { "\(anchor) V=\(Int(width))" }

    var geometry: RingGeometry { Fixture.shelfGeometry(width: width, anchor: anchor) }

    static let all: [ViewportCase] = Fixture.anchors.flatMap { anchor in
        Fixture.viewportWidths.map { ViewportCase(anchor: anchor, width: $0) }
    }
}

/// Continuous slots from `lower` to `upper` in `step` increments, computed without accumulating rounding error.
nonisolated func slots(from lower: Double, through upper: Double, by step: Double) -> [Double] {
    let count = Int(((upper - lower) / step).rounded())
    return (0...count).map { lower + Double($0) * step }
}
