import SwiftUI

/// Everything the Etagere's views need to know about its space, computed once per container size (behavior §1.7,
/// §6, D7): the resolved metrics, the insets, the shelf and ring heights and both ring geometries. Pure.
nonisolated struct EtagereLayout: Equatable, Sendable {
    /// The Etagere's size, including the horizontal safe area it draws into so cards can slide off the edge.
    var size: CGSize
    var metrics: EtagereResolvedMetrics
    var aspectRatio: CGFloat
    /// Where the Anchor Spot sits from the leading edge, and where a trailing anchor sits from the trailing edge.
    var leadingInset: CGFloat
    var trailingInset: CGFloat
    /// The ShelvesRing's top and bottom insets in mode 1 and the scroll margins in mode 2.
    var topInset: CGFloat
    var bottomInset: CGFloat
    /// The shelf title's line height, measured once for the current Dynamic Type size.
    var titleHeight: CGFloat
    var titleSpacing: CGFloat

    init(
        size: CGSize, safeArea: EdgeInsets, metrics: EtagereResolvedMetrics, aspectRatio: CGFloat,
        titleHeight: CGFloat?
    ) {
        self.size = size
        self.metrics = metrics
        self.aspectRatio = aspectRatio
        let horizontal = Self.horizontalInset(for: metrics)
        leadingInset = max(safeArea.leading, horizontal)
        trailingInset = max(safeArea.trailing, horizontal)
        let vertical = Self.highlightPadding(for: metrics).height + 4
        topInset = max(safeArea.top, vertical)
        bottomInset = max(safeArea.bottom, vertical)
        self.titleHeight = titleHeight ?? Self.estimatedTitleHeight(for: metrics.titleStyle)
        titleSpacing = metrics.widthClass == .television ? 12 : 6
    }

    /// The idle card face size.
    var cardSize: CGSize { CGSize(width: metrics.cardWidth, height: metrics.cardHeight(aspectRatio: aspectRatio)) }

    /// The height every ring reserves: the enlarged card's height, so activating a shelf never reflows (§1.7).
    var ringHeight: CGFloat { metrics.reservedRingHeight(aspectRatio: aspectRatio) }

    /// One shelf: its title, the gap below it and its ring.
    var shelfHeight: CGFloat { titleHeight + titleSpacing + ringHeight }

    /// How far the Active Shelf highlight reaches around a shelf.
    var highlightPadding: CGSize { Self.highlightPadding(for: metrics) }

    var highlightCornerRadius: CGFloat { metrics.widthClass == .television ? 32 : 20 }

    /// The ShelfRing geometry of the active ring; inactive rings use `withActivity(0)`.
    func ringGeometry(_ configuration: EtagereConfiguration) -> RingGeometry {
        RingGeometry(
            shelfMetrics: metrics, viewportWidth: size.width, leadingInset: leadingInset,
            trailingInset: trailingInset, alignment: configuration.horizontalAlignment,
            fadeLength: configuration.fadeLengthInSlots
        )
    }

    /// The ShelvesRing geometry of mode 1 (behavior §2.1).
    func shelvesGeometry(_ configuration: EtagereConfiguration) -> RingGeometry {
        RingGeometry(
            shelvesViewportHeight: size.height, topInset: topInset, bottomInset: bottomInset,
            shelfHeight: shelfHeight, shelfSpacing: metrics.shelfSpacing,
            alignment: configuration.verticalAlignment, fadeLength: configuration.fadeLengthInSlots
        )
    }

    /// The inset before the Anchor Spot when there is no larger safe area.
    static func horizontalInset(for metrics: EtagereResolvedMetrics) -> CGFloat {
        switch metrics.widthClass {
        case .compact: 16
        case .medium: 24
        case .regular: 32
        case .television: 48
        }
    }

    static func highlightPadding(for metrics: EtagereResolvedMetrics) -> CGSize {
        CGSize(width: horizontalInset(for: metrics) / 2, height: (metrics.shelfSpacing * 0.4).rounded())
    }

    /// A starting title height used until the real one is measured (and by single-pass renders).
    static func estimatedTitleHeight(for style: EtagereTitleStyle) -> CGFloat {
        #if os(macOS)
        let heights: [EtagereTitleStyle: CGFloat] = [.headline: 16, .title3Bold: 19, .title2Bold: 22]
        #else
        let heights: [EtagereTitleStyle: CGFloat] = [.headline: 22, .title3Bold: 25, .title2Bold: 28]
        #endif
        return heights[style] ?? 58
    }
}

/// The continuous phase a ring renders at and the rotations its render window must cover (behavior §1.5, §1.8).
nonisolated enum RingPhase {
    /// The rotations to pass to `RingMath.renderSlots(itemCount:covering:rest:itemID:)` so the window covers the
    /// model's rotations in flight and a fractional phase (a drag, or an override for snapshots).
    static func coveredRotations(_ inFlight: ClosedRange<Int>, phase: Double) -> ClosedRange<Int> {
        guard phase.isFinite else { return inFlight }
        return min(inFlight.lowerBound, Int(phase.rounded(.down)))...max(inFlight.upperBound, Int(phase.rounded(.up)))
    }

    /// The union of two rest windows: an inactive ring may show one more card than the active one, and the ring
    /// crossfades between them as its activity animates.
    static func union(_ first: ClosedRange<Int>, _ second: ClosedRange<Int>) -> ClosedRange<Int> {
        min(first.lowerBound, second.lowerBound)...max(first.upperBound, second.upperBound)
    }

    /// The shelf activity a snapshot shows at a fractional phase: what the animated `activity` would be at that
    /// point of a shelf step, 1 at the anchor and 0 one slot away.
    static func activity(atSlot slot: Double) -> Double {
        max(0, 1 - abs(slot))
    }
}

extension ShelfCardCrossAlignment {
    /// Where idle cards sit inside the height reserved for the enlarged card.
    var stackAlignment: Alignment {
        switch self {
        case .top: .topLeading
        case .center: .leading
        case .bottom: .bottomLeading
        }
    }

    /// The point the Active ShelfCard grows from.
    var scaleAnchor: UnitPoint {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}

extension EtagereVerticalAlignment {
    /// The scroll anchor that keeps the Active Shelf in place in mode 2 (R26).
    var scrollAnchor: UnitPoint {
        switch self {
        case .top: .top
        case .center: .center
        case .bottom: .bottom
        }
    }
}

/// Fractional phases to render instead of the model's rotations, for snapshot tests and debug rendering
/// (behavior §1.7, §7.3). A phase is absolute: with a ring at rotation 0, a card phase of 0.5 is half way to the
/// next card.
@_spi(EtagereDebug)
public nonisolated struct EtagerePhaseOverride: Sendable, Equatable {
    /// The Active Shelf's ring phase.
    public var cardPhase: Double?
    /// The ShelvesRing phase (mode 1).
    public var shelfPhase: Double?

    public init(cardPhase: Double? = nil, shelfPhase: Double? = nil) {
        self.cardPhase = cardPhase
        self.shelfPhase = shelfPhase
    }
}

/// The crossfades that replace sliding (behavior §1.8, §4).
nonisolated enum EtagereCrossfade {
    /// A jump: a restore, a far tap or a reload.
    static var jump: Animation { .easeInOut(duration: 0.2) }
    /// Reduce Motion: the emphasis of the old and new active cards, the vertical ring and the mode 2 highlight.
    static var reduceMotion: Animation { .easeInOut(duration: 0.15) }
}
