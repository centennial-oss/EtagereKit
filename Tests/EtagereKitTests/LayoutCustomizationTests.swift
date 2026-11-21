import CoreGraphics
@testable import EtagereKit
import SwiftUI
import Testing

@Suite("T27, T28 layout a host can set: title style and gap, insets, growth reserve, fitting shelves (D10)")
struct LayoutCustomizationTests {
    private static let regular = EtagereResolvedMetrics.starting(.regular, containerWidth: 1280)
    private static let television = EtagereResolvedMetrics.starting(.television, containerWidth: 1920)

    private static func layout(
        _ metrics: EtagereResolvedMetrics, height: CGFloat = 800, safeArea: EdgeInsets = EdgeInsets(),
        titleHeight: CGFloat? = 20, alignment: ShelfCardCrossAlignment = .center
    ) -> EtagereLayout {
        EtagereLayout(
            size: CGSize(width: 1280, height: height), safeArea: safeArea, metrics: metrics,
            aspectRatio: 16.0 / 9.0, titleHeight: titleHeight, cardCrossAlignment: alignment
        )
    }

    @Test("T27 .callout is a step below .headline, with a caption status and its own estimate")
    func calloutTitle() {
        #expect(EtagereTitleStyle.callout.font == .callout)
        #expect(EtagereTitleStyle.callout.statusFont == .caption)
        #if os(macOS)
        #expect(EtagereTitleStyle.callout.estimatedHeight == 15)
        #else
        #expect(EtagereTitleStyle.callout.estimatedHeight == 20)
        #endif
        #expect(EtagereTitleStyle.callout.estimatedHeight < EtagereTitleStyle.headline.estimatedHeight)
        #expect(EtagereLayout.estimatedTitleHeight(for: .callout) == EtagereTitleStyle.callout.estimatedHeight)
        #expect(EtagereTitleStyle(rawValue: "callout") == .callout)
    }

    @Test("T27 the title gap and the horizontal inset start per width class", arguments: [
        (EtagereWidthClass.compact, CGFloat(6), CGFloat(16)), (.medium, 6, 24), (.regular, 6, 32), (.television, 12, 48)
    ])
    func defaultSpacingAndInsets(widthClass: EtagereWidthClass, titleSpacing: CGFloat, inset: CGFloat) {
        let metrics = EtagereResolvedMetrics.starting(widthClass, containerWidth: 1000)
        #expect(metrics.titleSpacing == titleSpacing)
        #expect(metrics.horizontalInset == inset)
        #expect(metrics.activeGrowthReserve == 1)
        let layout = Self.layout(metrics)
        #expect(layout.titleSpacing == titleSpacing && layout.leadingInset == inset && layout.trailingInset == inset)
        #expect(layout.highlightPadding.width == inset / 2)
    }

    @Test("T27 a host's title gap and inset reach the layout; a larger safe area still wins")
    func customSpacingAndInsets() {
        var metrics = Self.television
        metrics.titleSpacing = 4
        metrics.horizontalInset = 0
        let layout = Self.layout(metrics, titleHeight: 30)
        #expect(layout.titleSpacing == 4)
        #expect(layout.shelfHeight == 30 + 4 + layout.ringHeight)
        #expect(layout.leadingInset == 0 && layout.trailingInset == 0 && layout.highlightPadding.width == 0)
        let notched = Self.layout(metrics, safeArea: EdgeInsets(top: 0, leading: 59, bottom: 0, trailing: 0))
        #expect(notched.leadingInset == 59 && notched.trailingInset == 0)
        let exact = EtagereResolvedMetrics(
            widthClass: .medium, cardWidth: 200, activeScale: 1.2, cardSpacing: 20, shelfSpacing: 24,
            titleStyle: .callout, seamWidth: 3, titleSpacing: 2, horizontalInset: 10, activeGrowthReserve: 0.5
        )
        #expect(exact.titleSpacing == 2 && exact.horizontalInset == 10 && exact.activeGrowthReserve == 0.5)
    }

    @Test("T27 the growth reserve: the full enlarged height by default, the idle height at 0, clamped")
    func growthReserve() {
        var metrics = Self.regular
        let height = metrics.cardHeight(aspectRatio: 16.0 / 9.0)
        #expect(abs(metrics.reservedRingHeight(aspectRatio: 16.0 / 9.0) - height * 1.3) < 1e-9)
        #expect(metrics.activeOverflow(aspectRatio: 16.0 / 9.0) == 0)
        metrics.activeGrowthReserve = 0
        #expect(metrics.reservedRingHeight(aspectRatio: 16.0 / 9.0) == height)
        #expect(abs(metrics.activeOverflow(aspectRatio: 16.0 / 9.0) - height * 0.3) < 1e-9)
        metrics.activeGrowthReserve = 0.5
        #expect(abs(metrics.reservedRingHeight(aspectRatio: 16.0 / 9.0) - height * 1.15) < 1e-9)
        for (value, clamped) in [(CGFloat(-1), CGFloat(0)), (2, 1), (.nan, 1)] {
            metrics.activeGrowthReserve = value
            #expect(metrics.clampedGrowthReserve == clamped)
        }
    }

    @Test("T27 a card growing past its ring: the cross alignment sets the direction, insets keep it on screen",
          arguments: ShelfCardCrossAlignment.allCases)
    func overflowDirection(alignment: ShelfCardCrossAlignment) {
        var metrics = Self.regular
        metrics.activeGrowthReserve = 0
        let layout = Self.layout(metrics, alignment: alignment)
        let overflow = metrics.cardHeight(aspectRatio: 16.0 / 9.0) * 0.3
        let padding = metrics.highlightVerticalPadding
        #expect(layout.ringHeight == layout.cardSize.height)
        #expect(abs(layout.overflowAbove + layout.overflowBelow - overflow) < 1e-9)
        #expect(layout.ringOverflow == max(layout.overflowAbove, layout.overflowBelow))
        switch alignment {
        case .top:
            #expect(layout.overflowAbove == 0)
            #expect(abs(layout.bottomInset - (overflow + 4)) < 1e-9, "the bottom shelf's card stays on screen")
        case .center:
            #expect(abs(layout.overflowAbove - overflow / 2) < 1e-9)
            #expect(layout.topInset == padding + 4, "the title's space above the ring takes the growth")
        case .bottom:
            #expect(layout.overflowBelow == 0 && layout.bottomInset == padding + 4)
            #expect(abs(layout.topInset - (overflow - 20 - 6 + 4)) < 1e-9, "past the title and its gap")
        }
        #expect(Self.layout(Self.regular, alignment: alignment).topInset == padding + 4, "reserve 1: no change")
    }

    @Test("T28 fitting: three tvOS shelves fill 1080 pt, as the closed form gives")
    func fitsThreeTelevisionShelves() {
        let fitted = Self.television.fitting(shelves: 3, in: 1080, aspectRatio: 16.0 / 9.0, titleHeight: 40)
        // 1080 - 2 x (14 + 4) insets - 2 x 36 gaps = 972; 324 per shelf - 40 - 12 = 272 = 1.25 h.
        #expect(abs(fitted.cardWidth - 272 / 1.25 * 16 / 9) < 1e-6)
        var unchanged = fitted
        unchanged.cardWidth = Self.television.cardWidth
        #expect(unchanged == Self.television, "only the card width changes")
        let layout = Self.layout(fitted, height: 1080, titleHeight: 40)
        #expect(abs(layout.height(ofShelves: 3) - 1080) < 1e-6)
        #expect(layout.shelvesGeometry(EtagereConfiguration()).restWindow(count: 10) == 0...2, "three at rest")
    }

    @Test("T28 fitting accounts for the safe area and a card growing past its ring",
          arguments: ShelfCardCrossAlignment.allCases)
    func fitsWithInsets(alignment: ShelfCardCrossAlignment) {
        var metrics = Self.television
        metrics.activeGrowthReserve = 0
        let safeArea = EdgeInsets(top: 60, leading: 0, bottom: 0, trailing: 0)
        let fitted = metrics.fitting(
            shelves: 3, in: 1080, aspectRatio: 16.0 / 9.0, titleHeight: 40, safeArea: safeArea,
            cardCrossAlignment: alignment
        )
        let layout = Self.layout(fitted, height: 1080, safeArea: safeArea, titleHeight: 40, alignment: alignment)
        #expect(layout.topInset == 60)
        #expect(abs(layout.height(ofShelves: 3) - 1080) < 1e-6)
    }

    @Test("T28 fitting edge cases: no shelves, no height, titles that alone overflow")
    func fittingEdgeCases() {
        let metrics = Self.regular
        #expect(metrics.fitting(shelves: 0, in: 900, aspectRatio: 16.0 / 9.0) == metrics)
        #expect(metrics.fitting(shelves: 2, in: .nan, aspectRatio: 16.0 / 9.0) == metrics)
        #expect(metrics.fitting(shelves: 9, in: 40, aspectRatio: 16.0 / 9.0).cardWidth == 1)
        let estimated = metrics.fitting(shelves: 2, in: 900, aspectRatio: 0.71)
        let boxArt = EtagereLayout(
            size: CGSize(width: 1280, height: 900), safeArea: EdgeInsets(), metrics: estimated, aspectRatio: 0.71,
            titleHeight: nil
        )
        #expect(abs(boxArt.height(ofShelves: 2) - 900) < 1e-6, "box art, with the title style's estimate")
        #expect(Self.layout(metrics).height(ofShelves: 0) == Self.layout(metrics).topInset * 2)
    }

    @Test("T28 EtagereMetrics.fitting resolves inside the Etagere; without a height it is its base")
    func fittingMetrics() {
        let size = CGSize(width: 1920, height: 1080)
        let fitting = EtagereMetrics.fitting(shelves: 3, base: .widthClass(.television))
        let resolved = fitting.resolved(containerSize: size, aspectRatio: 16.0 / 9.0, titleHeight: 40)
        #expect(resolved == Self.television.fitting(shelves: 3, in: 1080, aspectRatio: 16.0 / 9.0, titleHeight: 40))
        #expect(fitting.resolved(containerWidth: 1920) == Self.television)
        #expect(EtagereMetrics.automatic.resolved(containerSize: size, aspectRatio: 1, isTelevision: false)
            == EtagereMetrics.automatic.resolved(containerWidth: 1920, isTelevision: false))
        var configuration = EtagereConfiguration()
        configuration.metrics = .fitting(shelves: 2, base: .automatic)
        #expect(configuration.metrics != .automatic)
    }
}

@Suite("T30 the shelf title's point size (D10)")
@MainActor
struct TitleFontSizeTests {
    @Test("T30 a host's point size sets the title estimate; nil and invalid sizes keep the style's")
    func estimates() {
        var metrics = EtagereResolvedMetrics.starting(.regular, containerWidth: 1280)
        #expect(metrics.titleFontSize == nil && metrics.validTitleFontSize == nil)
        #expect(metrics.estimatedTitleHeight == EtagereTitleStyle.title2Bold.estimatedHeight)
        metrics.titleFontSize = 32
        #expect(metrics.validTitleFontSize == 32 && metrics.estimatedTitleHeight == 40)
        let layout = EtagereLayout(
            size: CGSize(width: 1280, height: 800), safeArea: EdgeInsets(), metrics: metrics, aspectRatio: 16.0 / 9.0,
            titleHeight: nil
        )
        #expect(layout.titleHeight == 40)
        for invalid in [CGFloat(0), -4, .nan, .infinity] {
            metrics.titleFontSize = invalid
            #expect(metrics.validTitleFontSize == nil)
            #expect(metrics.estimatedTitleHeight == EtagereTitleStyle.title2Bold.estimatedHeight)
        }
        let exact = EtagereResolvedMetrics(
            widthClass: .medium, cardWidth: 200, activeScale: 1.2, cardSpacing: 20, shelfSpacing: 24,
            titleStyle: .callout, seamWidth: 3, titleFontSize: 11
        )
        #expect(exact.titleFontSize == 11 && exact.estimatedTitleHeight == 14)
    }

    @Test("T30 the estimate matches the styles' own estimates at their default sizes")
    func estimateRule() {
        #if os(macOS)
        let sizes: [(EtagereTitleStyle, CGFloat)] = [(.callout, 12), (.title3Bold, 15), (.title2Bold, 17)]
        #elseif os(tvOS)
        let sizes: [(EtagereTitleStyle, CGFloat)] = [
            (.callout, 31), (.headline, 38), (.title3Bold, 48), (.title2Bold, 57)
        ]
        #else
        let sizes: [(EtagereTitleStyle, CGFloat)] = [
            (.callout, 16), (.headline, 17), (.title3Bold, 20), (.title2Bold, 22)
        ]
        #endif
        for (style, size) in sizes {
            #expect(EtagereTitleStyle.estimatedHeight(pointSize: size) == style.estimatedHeight, "\(style)")
        }
    }

    @Test("T30 fitting with a larger title leaves less height for cards")
    func fittingWithLargerTitle() {
        var metrics = EtagereResolvedMetrics.starting(.television, containerWidth: 1920)
        let standard = metrics.fitting(shelves: 3, in: 1080, aspectRatio: 16.0 / 9.0)
        metrics.titleFontSize = 80
        let large = metrics.fitting(shelves: 3, in: 1080, aspectRatio: 16.0 / 9.0)
        #expect(large.cardWidth < standard.cardWidth)
        #expect(large.titleFontSize == 80)
    }

    @Test("T30 the title renders at the host's size: taller than the style's, shorter when smaller")
    func renderedHeight() {
        var metrics = EtagereResolvedMetrics.starting(.compact, containerWidth: 400)
        let styled = Self.renderedHeight(metrics)
        metrics.titleFontSize = 40
        let large = Self.renderedHeight(metrics)
        metrics.titleFontSize = 8
        let small = Self.renderedHeight(metrics)
        #expect(large > styled && styled > small)
        #expect(abs(large - 40 * 1.2) < 6, "about one 40 pt line")
        metrics.titleFontSize = 40
        #expect(Self.renderedHeight(metrics, isStatus: true) < large, "the status stays smaller than the title")
    }

    private static func renderedHeight(_ metrics: EtagereResolvedMetrics, isStatus: Bool = false) -> CGFloat {
        let title = Text(verbatim: "Ag").shelfTitleFont(metrics, isStatus: isStatus).fixedSize()
        let renderer = ImageRenderer(content: title)
        renderer.scale = 1
        return CGFloat(renderer.cgImage?.height ?? 0)
    }
}

@Suite("T29 context menus: dividers and Cancel (D11)")
@MainActor
struct ActionDividerTests {
    @Test("T29 dividers never lead, trail or repeat; VoiceOver gets no dividers and no Cancel")
    func dividers() {
        @EtagereActionBuilder
        func build(showsExtras: Bool) -> [EtagereAction] {
            EtagereAction.divider
            EtagereAction("Play") {}
            EtagereAction.divider
            if showsExtras {
                EtagereAction("Favorite", systemImage: "heart") {}
                EtagereAction.divider
            }
            EtagereAction.divider
            EtagereAction("Show as List") {}
            EtagereAction("Cancel", role: .cancel) {}
            EtagereAction.divider
        }
        let titles = { (actions: [EtagereAction]) in actions.map { $0.isDivider ? "-" : $0.title } }
        #expect(titles(EtagereAction.menuItems(build(showsExtras: true)))
            == ["Play", "-", "Favorite", "-", "Show as List", "Cancel"])
        #expect(titles(EtagereAction.menuItems(build(showsExtras: false))) == ["Play", "-", "Show as List", "Cancel"])
        #expect(titles(EtagereAction.accessibilityItems(build(showsExtras: true)))
            == ["Play", "Favorite", "Show as List"])
        #expect(EtagereAction.menuItems([.divider, .divider]).isEmpty)
        let play = EtagereAction("Play") {}
        #expect(EtagereAction.divider.isDivider && !play.isDivider)
    }
}
