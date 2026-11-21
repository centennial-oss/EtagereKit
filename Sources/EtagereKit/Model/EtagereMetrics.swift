import SwiftUI

/// The width classes of behavior §6. Chosen from the container's width (D7), never from the device idiom or the
/// orientation, so Split View, Stage Manager windows and a folding iPhone get the metrics of the space they have.
/// tvOS has its own class because its 1920 pt screen is read from across a room.
public nonisolated enum EtagereWidthClass: String, Sendable, Hashable, CaseIterable, Codable {
    /// Under 500 pt.
    case compact
    /// 500 pt to under 900 pt.
    case medium
    /// 900 pt and wider (the table's 900-1600 pt row, held at its maximum card width beyond that).
    case regular
    /// The tvOS screen.
    case television

    /// True when compiled for tvOS. This is the platform, not a device idiom: every tvOS container is a TV screen.
    public static var platformIsTelevision: Bool {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }

    /// The class for a container width; always `.television` when `isTelevision`.
    public static func forContainerWidth(
        _ width: CGFloat, isTelevision: Bool = platformIsTelevision
    ) -> EtagereWidthClass {
        if isTelevision { return .television }
        let usable = width.isNaN ? 0 : width
        if usable < 500 { return .compact }
        if usable < 900 { return .medium }
        return .regular
    }
}

/// The text style of a shelf title, per width class. `.callout` is a step below `.headline` for dense layouts
/// such as a library grid; no width class starts with it. tvOS starts with `.headline`; `.televisionTitle3`,
/// its larger starting style before 0.2.0, is still available.
public nonisolated enum EtagereTitleStyle: String, Sendable, Hashable, CaseIterable, Codable {
    case headline, title3Bold, title2Bold, televisionTitle3, callout

    public var font: Font {
        switch self {
        case .callout: .callout
        case .headline: .headline
        case .title3Bold: .title3.bold()
        case .title2Bold: .title2.bold()
        // tvOS scales `.title3` with its own type ramp.
        case .televisionTitle3: .title3
        }
    }

    /// The smaller text beside a title, such as a shelf's "Updating".
    var statusFont: Font {
        switch self {
        case .callout, .headline: .caption
        case .title3Bold, .title2Bold: .subheadline
        case .televisionTitle3: .caption
        }
    }

    /// A starting height for one line of this style, used until the Etagere measures the real one (and by
    /// single-pass renders). The measured height follows Dynamic Type; this does not.
    public var estimatedHeight: CGFloat {
        #if os(macOS)
        let heights: [Self: CGFloat] = [.callout: 15, .headline: 16, .title3Bold: 19, .title2Bold: 22]
        #elseif os(tvOS)
        let heights: [Self: CGFloat] = [.callout: 39, .headline: 48, .title3Bold: 60, .title2Bold: 72]
        #else
        let heights: [Self: CGFloat] = [.callout: 20, .headline: 22, .title3Bold: 25, .title2Bold: 28]
        #endif
        return heights[self] ?? 58
    }

    /// The text style a title scales with under Dynamic Type, also when a host sets its point size (D10).
    public var textStyle: Font.TextStyle {
        switch self {
        case .callout: .callout
        case .headline: .headline
        case .title3Bold, .televisionTitle3: .title3
        case .title2Bold: .title2
        }
    }

    /// The title's weight when a host sets its point size (D10); the style's own font has the same weight.
    public var weight: Font.Weight {
        switch self {
        case .callout: .regular
        case .headline: .semibold
        case .title3Bold, .title2Bold: .bold
        case .televisionTitle3: .medium
        }
    }

    /// The status text's size relative to a host's title point size, so it stays smaller than the title.
    static let statusSizeRatio: CGFloat = 0.8

    /// A starting line height for a title at a point size: 1.25 times the size, rounded up, as the style
    /// estimates are.
    public static func estimatedHeight(pointSize: CGFloat) -> CGFloat {
        (pointSize * 1.25).rounded(.up)
    }
}

/// Card and shelf sizes for one container width.
public nonisolated struct EtagereResolvedMetrics: Sendable, Hashable {
    public var widthClass: EtagereWidthClass
    /// `w`: the idle card width.
    public var cardWidth: CGFloat
    /// `W / w`: how much the Active ShelfCard grows.
    public var activeScale: CGFloat
    /// `p`: the gap between cards.
    public var cardSpacing: CGFloat
    /// The gap between shelves.
    public var shelfSpacing: CGFloat
    public var titleStyle: EtagereTitleStyle
    /// The shelf title's point size (D10), in place of the size of `titleStyle`'s text style. The title keeps
    /// the style's weight and still scales with Dynamic Type, relative to the style's text style; the status
    /// text beside it is 80% of it. nil, the default, uses the text style's own size; a value that is not a
    /// positive number counts as nil.
    public var titleFontSize: CGFloat?
    /// The seam bar's thickness (behavior §1.6); Increase Contrast draws it at 4 pt in the accent color.
    public var seamWidth: CGFloat
    /// The gap between a shelf's title and its cards (D10): 12 pt on tvOS, 6 pt elsewhere by default.
    public var titleSpacing: CGFloat
    /// The inset before a leading Anchor Spot and after a trailing one (D10): 16, 24 and 32 pt for the compact,
    /// medium and regular classes and 48 pt on tvOS by default. A larger horizontal safe area still wins, so the
    /// Anchor Spot stays inside it.
    public var horizontalInset: CGFloat
    /// How much of the Active ShelfCard's growth every ring keeps room for (behavior §1.7, D10), from 0 to 1.
    /// 1, the default, reserves the enlarged card's height, so nothing overlaps. Lower values keep only that part
    /// of the growth, and the Active ShelfCard grows past its ring, over the space between shelves, in the
    /// direction `ShelfCardCrossAlignment` gives (`.top` grows only downward). Values outside 0...1 are clamped.
    public var activeGrowthReserve: CGFloat

    /// - Parameters:
    ///   - titleSpacing: nil for the width class's default.
    ///   - horizontalInset: nil for the width class's default.
    public init(
        widthClass: EtagereWidthClass,
        cardWidth: CGFloat,
        activeScale: CGFloat,
        cardSpacing: CGFloat,
        shelfSpacing: CGFloat,
        titleStyle: EtagereTitleStyle,
        seamWidth: CGFloat,
        titleSpacing: CGFloat? = nil,
        horizontalInset: CGFloat? = nil,
        activeGrowthReserve: CGFloat = 1,
        titleFontSize: CGFloat? = nil
    ) {
        self.widthClass = widthClass
        self.cardWidth = cardWidth
        self.activeScale = activeScale
        self.cardSpacing = cardSpacing
        self.shelfSpacing = shelfSpacing
        self.titleStyle = titleStyle
        self.seamWidth = seamWidth
        self.titleSpacing = titleSpacing ?? Self.defaultTitleSpacing(for: widthClass)
        self.horizontalInset = horizontalInset ?? Self.defaultHorizontalInset(for: widthClass)
        self.activeGrowthReserve = activeGrowthReserve
        self.titleFontSize = titleFontSize
    }

    /// `titleFontSize` when it is a positive, finite number; otherwise nil.
    public var validTitleFontSize: CGFloat? {
        guard let size = titleFontSize, size.isFinite, size > 0 else { return nil }
        return size
    }

    /// A starting height for one title line, used until the Etagere measures the real one: the title style's
    /// estimate, or one from `titleFontSize`.
    public var estimatedTitleHeight: CGFloat {
        validTitleFontSize.map(EtagereTitleStyle.estimatedHeight(pointSize:)) ?? titleStyle.estimatedHeight
    }

    /// The title-to-cards gap a width class starts with.
    public static func defaultTitleSpacing(for widthClass: EtagereWidthClass) -> CGFloat {
        widthClass == .television ? 12 : 6
    }

    /// The horizontal inset a width class starts with.
    public static func defaultHorizontalInset(for widthClass: EtagereWidthClass) -> CGFloat {
        switch widthClass {
        case .compact: 16
        case .medium: 24
        case .regular: 32
        case .television: 48
        }
    }

    /// `W`: the Active ShelfCard's width.
    public var activeCardWidth: CGFloat { cardWidth * activeScale }

    /// The idle card height for a face aspect ratio (width / height).
    public func cardHeight(aspectRatio: CGFloat) -> CGFloat {
        aspectRatio > 0 ? cardWidth / aspectRatio : cardWidth
    }

    /// `activeGrowthReserve` clamped to 0...1; not a number counts as 1.
    public var clampedGrowthReserve: CGFloat {
        activeGrowthReserve.isNaN ? 1 : min(max(activeGrowthReserve, 0), 1)
    }

    /// The height every ring reserves: by default the enlarged card's height, so activating a shelf never
    /// reflows the page (behavior §1.7); with a lower `activeGrowthReserve`, the idle height plus that part of
    /// the growth.
    public func reservedRingHeight(aspectRatio: CGFloat) -> CGFloat {
        let height = cardHeight(aspectRatio: aspectRatio)
        return height + height * (activeScale - 1) * clampedGrowthReserve
    }

    /// How far the enlarged Active ShelfCard reaches past its ring's reserved height, top and bottom together.
    public func activeOverflow(aspectRatio: CGFloat) -> CGFloat {
        max(0, cardHeight(aspectRatio: aspectRatio) * activeScale - reservedRingHeight(aspectRatio: aspectRatio))
    }

    /// The Active Shelf highlight's reach above and below a shelf: 40% of the shelf spacing, rounded.
    public var highlightVerticalPadding: CGFloat { (shelfSpacing * 0.4).rounded() }

    /// The smallest top and bottom inset of the Etagere: the highlight's reach plus 4 pt. A larger safe area, or an
    /// Active ShelfCard that grows past its shelf, makes an inset larger.
    public var verticalInset: CGFloat { highlightVerticalPadding + 4 }

    /// The starting metrics of behavior §6 for a width class at a container width.
    public static func starting(_ widthClass: EtagereWidthClass, containerWidth: CGFloat) -> EtagereResolvedMetrics {
        let width = containerWidth.isNaN ? 0 : containerWidth
        switch widthClass {
        case .compact:
            return EtagereResolvedMetrics(
                widthClass: .compact, cardWidth: clamp(width * 0.46, 150, 230), activeScale: 1.15,
                cardSpacing: 14, shelfSpacing: 18, titleStyle: .headline, seamWidth: 3
            )
        case .medium:
            return EtagereResolvedMetrics(
                widthClass: .medium, cardWidth: clamp(width * 0.24, 170, 240), activeScale: 1.25,
                cardSpacing: 20, shelfSpacing: 24, titleStyle: .title3Bold, seamWidth: 3
            )
        case .regular:
            return EtagereResolvedMetrics(
                widthClass: .regular, cardWidth: clamp(width * 0.19, 200, 320), activeScale: 1.3,
                cardSpacing: 24, shelfSpacing: 28, titleStyle: .title2Bold, seamWidth: 3
            )
        case .television:
            return EtagereResolvedMetrics(
                widthClass: .television, cardWidth: 360, activeScale: 1.25,
                cardSpacing: 40, shelfSpacing: 36, titleStyle: .headline, seamWidth: 4
            )
        }
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

/// How the Etagere sizes its cards (behavior §6). The view resolves it with its container's size.
public nonisolated enum EtagereMetrics: Sendable, Hashable {
    /// The starting metrics for the container's width class (the default).
    case automatic
    /// One width class's starting metrics at any container width.
    case widthClass(EtagereWidthClass)
    /// Exact sizes, whatever the container.
    case fixed(EtagereResolvedMetrics)
    /// `base`'s sizes with the card width chosen so `shelves` whole shelves fill the Etagere's height (behavior
    /// §6.1, D10), using the title height the Etagere measures. Only `resolved(containerSize:...)` fits;
    /// `resolved(containerWidth:)` has no height and returns `base`'s metrics.
    indirect case fitting(shelves: Int, base: EtagereMetrics)

    /// The metrics for a container, fitting shelves to its height for `.fitting`.
    /// - Parameters:
    ///   - aspectRatio: The card face's aspect ratio (`ShelfCardContent.faceAspectRatio`).
    ///   - titleHeight: One line of the title style; nil for `EtagereResolvedMetrics.estimatedTitleHeight`.
    public func resolved(
        containerSize: CGSize,
        safeArea: EdgeInsets = EdgeInsets(),
        aspectRatio: CGFloat,
        titleHeight: CGFloat? = nil,
        cardCrossAlignment: ShelfCardCrossAlignment = .center,
        isTelevision: Bool = EtagereWidthClass.platformIsTelevision
    ) -> EtagereResolvedMetrics {
        guard case .fitting(let shelves, let base) = self else {
            return resolved(containerWidth: containerSize.width, isTelevision: isTelevision)
        }
        return base.resolved(
            containerSize: containerSize, safeArea: safeArea, aspectRatio: aspectRatio, titleHeight: titleHeight,
            cardCrossAlignment: cardCrossAlignment, isTelevision: isTelevision
        ).fitting(
            shelves: shelves, in: containerSize.height, aspectRatio: aspectRatio, titleHeight: titleHeight,
            safeArea: safeArea, cardCrossAlignment: cardCrossAlignment
        )
    }

    public func resolved(
        containerWidth: CGFloat, isTelevision: Bool = EtagereWidthClass.platformIsTelevision
    ) -> EtagereResolvedMetrics {
        switch self {
        case .automatic:
            let widthClass = EtagereWidthClass.forContainerWidth(containerWidth, isTelevision: isTelevision)
            return .starting(widthClass, containerWidth: containerWidth)
        case .widthClass(let widthClass):
            return .starting(widthClass, containerWidth: containerWidth)
        case .fixed(let metrics):
            return metrics
        case .fitting(_, let base):
            return base.resolved(containerWidth: containerWidth, isTelevision: isTelevision)
        }
    }
}
