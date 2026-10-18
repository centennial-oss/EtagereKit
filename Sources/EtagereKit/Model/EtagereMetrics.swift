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

/// The text style of a shelf title, per width class.
public nonisolated enum EtagereTitleStyle: String, Sendable, Hashable, CaseIterable, Codable {
    case headline, title3Bold, title2Bold, televisionTitle3

    public var font: Font {
        switch self {
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
        case .headline: .caption
        case .title3Bold, .title2Bold: .subheadline
        case .televisionTitle3: .caption
        }
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
    /// The seam bar's thickness (behavior §1.6); Increase Contrast draws it at 4 pt in the accent color.
    public var seamWidth: CGFloat

    public init(
        widthClass: EtagereWidthClass,
        cardWidth: CGFloat,
        activeScale: CGFloat,
        cardSpacing: CGFloat,
        shelfSpacing: CGFloat,
        titleStyle: EtagereTitleStyle,
        seamWidth: CGFloat
    ) {
        self.widthClass = widthClass
        self.cardWidth = cardWidth
        self.activeScale = activeScale
        self.cardSpacing = cardSpacing
        self.shelfSpacing = shelfSpacing
        self.titleStyle = titleStyle
        self.seamWidth = seamWidth
    }

    /// `W`: the Active ShelfCard's width.
    public var activeCardWidth: CGFloat { cardWidth * activeScale }

    /// The idle card height for a face aspect ratio (width / height).
    public func cardHeight(aspectRatio: CGFloat) -> CGFloat {
        aspectRatio > 0 ? cardWidth / aspectRatio : cardWidth
    }

    /// The height every ring reserves: the enlarged card's height, so activating a shelf never reflows the page
    /// (behavior §1.7).
    public func reservedRingHeight(aspectRatio: CGFloat) -> CGFloat {
        cardHeight(aspectRatio: aspectRatio) * activeScale
    }

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
                cardSpacing: 40, shelfSpacing: 36, titleStyle: .televisionTitle3, seamWidth: 4
            )
        }
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

/// How the Etagere sizes its cards (behavior §6). The view resolves it with its container's width.
public nonisolated enum EtagereMetrics: Sendable, Hashable {
    /// The starting metrics for the container's width class (the default).
    case automatic
    /// One width class's starting metrics at any container width.
    case widthClass(EtagereWidthClass)
    /// Exact sizes, whatever the container.
    case fixed(EtagereResolvedMetrics)

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
        }
    }
}
