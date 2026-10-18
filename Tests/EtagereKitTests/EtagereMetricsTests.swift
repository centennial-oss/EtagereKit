import CoreGraphics
import EtagereKit
import Testing

/// One row of the metrics table in behavior §6 (the card width is checked separately).
nonisolated struct ClassRow: Sendable, CustomTestStringConvertible {
    let widthClass: EtagereWidthClass
    let scale: CGFloat
    let spacing: CGFloat
    let shelfSpacing: CGFloat
    let title: EtagereTitleStyle
    let seam: CGFloat

    var testDescription: String { widthClass.rawValue }

    static let table = [
        ClassRow(widthClass: .compact, scale: 1.15, spacing: 14, shelfSpacing: 18, title: .headline, seam: 3),
        ClassRow(widthClass: .medium, scale: 1.25, spacing: 20, shelfSpacing: 24, title: .title3Bold, seam: 3),
        ClassRow(widthClass: .regular, scale: 1.3, spacing: 24, shelfSpacing: 28, title: .title2Bold, seam: 3),
        ClassRow(widthClass: .television, scale: 1.25, spacing: 40, shelfSpacing: 36, title: .televisionTitle3, seam: 4)
    ]
}

@Suite("Metrics from the container width (behavior §6, D7) and configuration defaults (etagere.md §4.3)")
struct EtagereMetricsTests {
    @Test("Width classes come from the container width", arguments: [
        (CGFloat(0), EtagereWidthClass.compact), (320, .compact), (499.9, .compact), (500, .medium),
        (899.9, .medium), (900, .regular), (1600, .regular), (2560, .regular), (CGFloat.nan, .compact)
    ])
    func widthClasses(width: CGFloat, expected: EtagereWidthClass) {
        #expect(EtagereWidthClass.forContainerWidth(width, isTelevision: false) == expected)
        #expect(EtagereWidthClass.forContainerWidth(width, isTelevision: true) == .television)
    }

    @Test("The platform default is television only on tvOS")
    func platformDefault() {
        #if os(tvOS)
        #expect(EtagereWidthClass.platformIsTelevision)
        #else
        #expect(!EtagereWidthClass.platformIsTelevision)
        #endif
        #expect(EtagereWidthClass.forContainerWidth(1280) == (EtagereWidthClass.platformIsTelevision ? .television
            : .regular))
    }

    @Test("Starting card widths follow the table, clamped", arguments: [
        (CGFloat(200), CGFloat(150)), (400, 184), (499, 229.54), (500, 170), (700, 170), (900, 200), (1280, 243.2),
        (1600, 304), (1920, 320), (3000, 320)
    ])
    func cardWidths(width: CGFloat, expected: CGFloat) {
        let metrics = EtagereMetrics.automatic.resolved(containerWidth: width, isTelevision: false)
        #expect(abs(metrics.cardWidth - expected) < 1e-9)
    }

    @Test("Each class has its scale, spacing, title style and seam", arguments: ClassRow.table)
    func classMetrics(row: ClassRow) {
        let metrics = EtagereResolvedMetrics.starting(row.widthClass, containerWidth: 1000)
        #expect(metrics.widthClass == row.widthClass)
        #expect(metrics.activeScale == row.scale)
        #expect(metrics.cardSpacing == row.spacing)
        #expect(metrics.shelfSpacing == row.shelfSpacing)
        #expect(metrics.titleStyle == row.title)
        #expect(metrics.seamWidth == row.seam)
        #expect(metrics.activeCardWidth == metrics.cardWidth * row.scale)
    }

    @Test("tvOS uses 360 pt cards at any width")
    func televisionMetrics() {
        let metrics = EtagereMetrics.automatic.resolved(containerWidth: 1920, isTelevision: true)
        #expect(metrics.cardWidth == 360)
        #expect(metrics.activeCardWidth == 450)
        #expect(EtagereMetrics.automatic.resolved(containerWidth: 1700, isTelevision: true) == metrics)
    }

    @Test("A width class or exact sizes can be pinned")
    func pinnedMetrics() {
        let regularAtCompactWidth = EtagereMetrics.widthClass(.regular)
            .resolved(containerWidth: 400, isTelevision: true)
        #expect(regularAtCompactWidth.widthClass == .regular)
        #expect(regularAtCompactWidth.cardWidth == 200)
        let exact = EtagereResolvedMetrics(
            widthClass: .medium, cardWidth: 280, activeScale: 1.2, cardSpacing: 30, shelfSpacing: 30,
            titleStyle: .title3Bold, seamWidth: 3
        )
        #expect(EtagereMetrics.fixed(exact).resolved(containerWidth: 100) == exact)
        #expect(exact.cardHeight(aspectRatio: 0) == 280, "a degenerate aspect ratio keeps a square face")
        let reserved: CGFloat = 280 * 9 / 16 * 1.2
        #expect(exact.reservedRingHeight(aspectRatio: 16.0 / 9.0) == reserved)
    }

    @Test("Configuration defaults (etagere.md §4.3 and the design decisions)")
    func configurationDefaults() {
        let configuration = EtagereConfiguration()
        #expect(configuration.horizontalAlignment == .leading)
        #expect(configuration.verticalAlignment == .top)
        #expect(configuration.verticalMode == .ring)
        #expect(configuration.metrics == .automatic)
        #expect(configuration.cardCrossAlignment == .center)
        #expect(configuration.idleDim == 0.12)
        #expect(configuration.inactiveShelfDim == 0.15)
        #expect(configuration.showsSeam)
        #expect(configuration.showsShelfSeam)
        #expect(configuration.fadeLengthInSlots == 1)
        #expect(configuration != EtagereConfiguration(verticalMode: .cursor))
        #expect(EtagereVerticalAlignment.allCases.map(\.ringAnchor) == [.leading, .center, .trailing])
    }

    @Test("Public enums round-trip through their raw values for Settings")
    func rawValues() {
        #expect(EtagereHorizontalAlignment(rawValue: "trailing") == .trailing)
        #expect(EtagereVerticalAlignment(rawValue: "bottom") == .bottom)
        #expect(EtagereVerticalMode(rawValue: "cursor") == .cursor)
        #expect(EtagereWidthClass(rawValue: "television") == .television)
        #expect(EtagereTitleStyle.allCases.count == 4)
    }
}
