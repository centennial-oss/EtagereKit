import CoreGraphics
@_spi(EtagereDebug) @testable import EtagereKit
import SwiftUI
import Testing

/// Width ratios for virtual indices -60...60 that repeat a pattern by ring index, as a ring of `pattern.count`
/// cards would.
private func patternWidths(_ pattern: [CGFloat]) -> RingWidths {
    RingWidths(firstVirtualIndex: -60, ratios: (-60...60).map { pattern[RingMath.floorMod($0, pattern.count)] })
}

/// Ratios of exactly 1 through the general path, which must match the uniform slot functions.
private let explicitOnes = RingWidths(firstVirtualIndex: -60, ratios: Array(repeating: 1, count: 121))

@Suite("T25, T26 cards sized by their artwork (behavior §1.12, D9)")
struct CardWidthTests {
    @Test("T25 with equal widths the general slot functions are the uniform ones", arguments: ViewportCase.all)
    func generalPathMatchesUniform(viewport: ViewportCase) {
        let ring = viewport.geometry
        for activity in [0.0, 0.5, 1] {
            let geometry = ring.withActivity(activity)
            for phase in slots(from: -2, through: 3, by: 0.05) {
                for index in -3...6 {
                    let expected = geometry.center(at: Double(index) - phase)
                    let actual = geometry.center(of: index, phase: phase, widths: explicitOnes)
                    #expect(abs(actual - expected) < 1e-6, "v=\(index) phase=\(phase)")
                    let length = geometry.length(of: index, phase: phase, widths: explicitOnes)
                    #expect(abs(length - geometry.length(at: Double(index) - phase)) < 1e-6)
                }
            }
        }
    }

    @Test("T26 with equal widths every rotation has the uniform rest window", arguments: RingCase.all)
    func generalRestWindowMatchesUniform(ring: RingCase) {
        for rotation in [-7, 0, 5] {
            #expect(ring.geometry.restWindow(count: ring.itemCount, rotation: rotation, widths: explicitOnes)
                == ring.geometry.restWindow(count: ring.itemCount))
            let inactive = ring.geometry.withActivity(0)
            #expect(inactive.restWindow(count: ring.itemCount, rotation: rotation, widths: explicitOnes)
                == inactive.restWindow(count: ring.itemCount))
        }
    }

    @Test("T25 mixed widths keep exactly the spacing between neighbours on every frame (R12, R18)",
          arguments: RingAnchor.allCases)
    func constantGap(anchor: RingAnchor) {
        let geometry = Fixture.referenceGeometry(anchor: anchor)
        let widths = patternWidths([1, 0.375, 1.4, 0.6, 1])
        for phase in slots(from: -3, through: 6, by: 0.05) {
            for index in -4...8 {
                let trailing = geometry.center(of: index, phase: phase, widths: widths)
                    + geometry.length(of: index, phase: phase, widths: widths) / 2
                let leading = geometry.center(of: index + 1, phase: phase, widths: widths)
                    - geometry.length(of: index + 1, phase: phase, widths: widths) / 2
                #expect(abs(leading - trailing - geometry.spacing) < 1e-6, "v=\(index) phase=\(phase)")
            }
        }
    }

    @Test("T25 at rest the anchored card, at its own enlarged width, sits at the Anchor Spot (R6)",
          arguments: RingAnchor.allCases)
    func anchoredCardAtRest(anchor: RingAnchor) {
        let geometry = Fixture.referenceGeometry(anchor: anchor)
        let widths = patternWidths([1, 0.375, 1.4])
        for rotation in -4...4 {
            let phase = Double(rotation)
            let length = geometry.length(of: rotation, phase: phase, widths: widths)
            #expect(abs(length - 390 * widths.ratio(at: rotation)) < 1e-9, "grown to W x its ratio")
            let center = geometry.center(of: rotation, phase: phase, widths: widths)
            switch anchor {
            case .leading: #expect(abs(center - length / 2 - 80) < 1e-9)
            case .center: #expect(abs(center - 960) < 1e-9)
            case .trailing: #expect(abs(center + length / 2 - (1920 - 80)) < 1e-9)
            }
            #expect(abs(geometry.center(of: rotation + 1, phase: phase - 1e-9, widths: widths)
                - geometry.center(of: rotation + 1, phase: phase, widths: widths)) < 1e-5, "continuous")
        }
    }

    @Test("T26 the rest window counts the cards that are at least partly visible at their own widths (R19)")
    func restWindowFollowsWidths() {
        let geometry = Fixture.referenceGeometry()
        let uniform = geometry.restWindow(count: 40)
        #expect(uniform == 0...5)
        let narrow = geometry.restWindow(count: 40, rotation: 0, widths: patternWidths([0.4]))
        let wide = geometry.restWindow(count: 40, rotation: 0, widths: patternWidths([2]))
        #expect(narrow.upperBound > uniform.upperBound && wide.upperBound < uniform.upperBound)
        let mixed = patternWidths([1, 0.375, 1.4, 0.6])
        for rotation in -3...3 {
            let rest = geometry.restWindow(count: 40, rotation: rotation, widths: mixed)
            let last = rotation + rest.upperBound
            let nearEdge = { (index: Int) in
                geometry.center(of: index, phase: Double(rotation), widths: mixed)
                    - geometry.length(of: index, phase: Double(rotation), widths: mixed) / 2
            }
            #expect(nearEdge(last) < 1920 && nearEdge(last + 1) >= 1920, "rotation \(rotation): \(rest)")
            #expect(rest.lowerBound == 0, "a leading ring shows nothing before the anchor")
        }
        #expect(geometry.restWindow(count: 3, rotation: 0, widths: patternWidths([0.4])) == 0...2, "never repeats")
    }

    @Test("T26 fades: opaque inside both rest windows, fading out of one or into the other (R13, R17)")
    func opacityAcrossRotations() {
        var geometry = Fixture.referenceGeometry()
        let rests = RestWindows(firstRotation: 0, windows: [0...5, 0...3])
        #expect(geometry.opacity(of: 2, phase: 0.4, rests: rests) == 1, "in both windows")
        #expect(abs(geometry.opacity(of: 0, phase: 0.25, rests: rests) - 0.75) < 1e-9, "the anchored card leaves")
        #expect(abs(geometry.opacity(of: 5, phase: 0.5, rests: rests) - 0.5) < 1e-9, "past the narrower window")
        #expect(geometry.opacity(of: 5, phase: 0, rests: rests) == 1)
        #expect(geometry.opacity(of: 6, phase: 0.5, rests: rests) == 0)
        #expect(abs(geometry.opacity(of: 4, phase: 0.75, rests: RestWindows(single: 0...3)) - 0.75) < 1e-9,
                "a card entering the window")
        geometry.fadeLength = 0.5
        #expect(geometry.opacity(of: 0, phase: 0.5, rests: rests) == 0, "a shorter fade ends sooner (Q1)")
        for phase in slots(from: 0, through: 2, by: 0.05) {
            for index in -1...7 {
                let uniform = geometry.opacity(at: Double(index) - phase, rest: 0...4)
                #expect(abs(geometry.opacity(of: index, phase: phase, rests: RestWindows(single: 0...4)) - uniform)
                    < 1e-9, "one window for every rotation is the uniform rule: v=\(index) phase=\(phase)")
            }
        }
    }

    @Test("T25 a card's width ratio: its clamped shape at the shelf's height; nil keeps the shelf's shape")
    func widthRatios() {
        let size = CGSize(width: 320, height: 180)
        #expect(RingWidths.widthRatio(cardAspectRatio: nil, cardSize: size) == 1)
        #expect(RingWidths.widthRatio(cardAspectRatio: 16.0 / 9.0, cardSize: size) == 1, "the shelf's own shape")
        #expect(abs(RingWidths.widthRatio(cardAspectRatio: 2.0 / 3.0, cardSize: size) - 120.0 / 320) < 1e-9)
        #expect(abs(RingWidths.widthRatio(cardAspectRatio: 9, cardSize: size) - 450.0 / 320) < 1e-9, "max 2.5")
        #expect(abs(RingWidths.widthRatio(cardAspectRatio: 0.1, cardSize: size) - 90.0 / 320) < 1e-9, "min 0.5")
        for invalid: CGFloat in [0, -1, .nan, .infinity] {
            #expect(RingWidths.widthRatio(cardAspectRatio: invalid, cardSize: size) == 1)
        }
        #expect(RingWidths(firstVirtualIndex: 3, ratios: [0.5]).ratio(at: 4) == 1, "outside the window")
        #expect(RestWindows(firstRotation: 2, windows: [0...1, 0...2]).window(at: 9) == 0...2)
        #expect(RestWindows(firstRotation: 2, windows: [-1...1, 0...2]).union == -1...2)
    }

    @Test("T26 D4 a strip's cost follows the viewport, not the ring's length; uniform rings store nothing")
    func stripCost() {
        let geometry = Fixture.referenceGeometry()
        let size = CGSize(width: 300, height: 168.75)
        func strip(count: Int, shaped: Bool) -> RingStrip {
            RingStrip(geometry: geometry, cardSize: size, itemCount: count, covering: 0...2) {
                shaped && $0.isMultiple(of: 2) ? 2.0 / 3.0 : nil
            }
        }
        #expect(strip(count: 10_000, shaped: false).widths.isUniform)
        #expect(strip(count: 10_000, shaped: false).activeRests == RestWindows(single: 0...5))
        let short = strip(count: 12, shaped: true)
        let long = strip(count: 10_000, shaped: true)
        #expect(!long.widths.isUniform && strip(count: 40, shaped: true).widths.ratios.count
            == long.widths.ratios.count, "past what fits in the viewport, the window stops growing")
        #expect(short.widths.ratios.count <= long.widths.ratios.count, "a short ring needs no more than it has")
        #expect(long.activeRests.windows.count == 5, "the rotations in flight and one on each side")
        let empty = RingStrip(geometry: geometry, cardSize: size, itemCount: 0, covering: 0...0) { _ in nil }
        #expect(empty.renderRest == 0...0)
        #expect(long.step(at: 0) == (300 * long.widths.ratio(at: 0) + 300 * long.widths.ratio(at: 1)) / 2 + 32)
        #expect(strip(count: 12, shaped: false).step(at: 0) == geometry.step)
    }

    @Test("T25 the seam bar sits in the middle of the gap after the last card, whatever its width (R20)")
    func seamAfterAShapedCard() {
        let geometry = Fixture.referenceGeometry()
        let strip = RingStrip(
            geometry: geometry, widths: patternWidths([1, 0.5, 0.5]),
            activeRests: RestWindows(single: 0...2), inactiveRests: RestWindows(single: 0...2)
        )
        let lastEdge = geometry.center(of: 2, phase: 0, widths: strip.widths)
            + geometry.length(of: 2, phase: 0, widths: strip.widths) / 2
        #expect(abs(strip.seamCenter(after: 2, slot: 2, activity: 1) - (lastEdge + 16)) < 1e-9)
        #expect(abs(strip.offset(of: 1, slot: 1, activity: 1) - (80 + 390 + 32)) < 1e-9)
    }
}

/// A flat-color card with its own shape: red when active, gray otherwise.
private nonisolated struct ShapedSwatchCard: ShelfCardContent {
    let id: String
    let cardAspectRatio: CGFloat?

    var accessibilityTitle: String { id }

    @MainActor
    func makeFace(context: ShelfCardContext) -> some View {
        Rectangle().fill(context.isActive ? Color.red : Color.gray)
    }
}

@MainActor
@Suite("T22, T25 snapshot: cards drawn at their own widths")
struct CardWidthSnapshotTests {
    @Test("T22, T25 a poster card draws narrower than its 16:9 neighbours, with the same gap between them")
    func posterCardWidths() throws {
        let size = CGSize(width: 1280, height: 340)
        let shapes: [CGFloat?] = [nil, 2.0 / 3.0, nil, 2.0 / 3.0]
        let cards = shapes.enumerated().map { ShapedSwatchCard(id: "c\($0.offset)", cardAspectRatio: $0.element) }
        let model = EtagereModel(shelves: [Shelf(id: "shaped", title: "Shaped", cards: cards)])
        let image = try #require(SnapshotHarness.render(
            SnapshotHarness.etagere(model, override: EtagerePhaseOverride()), size: size, name: "card-widths"
        ))
        let pixels = try #require(PixelImage(image))
        let layout = EtagereLayout(
            size: size, safeArea: EdgeInsets(), metrics: model.configuration.metrics.resolved(containerWidth: 1280),
            aspectRatio: ShapedSwatchCard.faceAspectRatio, titleHeight: nil
        )
        let strip = RingStrip(
            geometry: layout.ringGeometry(model.configuration), cardSize: layout.cardSize, itemCount: cards.count,
            covering: 0...0
        ) { cards[$0].cardAspectRatio }
        let anchoredCenter = Int(strip.offset(of: 0, slot: 0, activity: 1) + layout.cardSize.width / 2)
        let red = pixels.rows(column: anchoredCenter) { $0.isClose(to: SnapshotHarness.systemRed) }
        let row = Int(try #require(red.spanCenter))
        let dark = pixels.columns(row: row) { $0.isDark }
        let runs = dark.reduce(into: [[Int]]()) { runs, column in
            if let last = runs.last?.last, column == last + 1 { runs[runs.count - 1].append(column) } else {
                runs.append([column])
            }
        }.filter { $0.count > 10 }
        #expect(runs.count >= 3, "three gray cards after the red one: \(runs.map { ($0.first ?? 0, $0.count) })")
        for (offset, run) in runs.prefix(3).enumerated() {
            let index = offset + 1
            let leading = strip.offset(of: index, slot: Double(index), activity: 1)
            let width = strip.idleWidth(of: index)
            #expect(abs(Double(run.first ?? 0) - leading) <= 2, "card \(index) starts at \(leading)")
            #expect(abs(Double(run.count) - width) <= 3, "card \(index) is \(width) wide, drew \(run.count)")
        }
        #expect(abs(strip.idleWidth(of: 1) - layout.cardSize.height * 2 / 3) < 1e-9)
    }
}
