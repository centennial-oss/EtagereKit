import CoreGraphics
@testable import EtagereKit
import SwiftUI
import Testing

@Suite("View layout, render phases and accessibility text (behavior §1.5, §1.7, §4, §6)")
struct EtagereLayoutTests {
    private func layout(width: CGFloat, safeArea: EdgeInsets = EdgeInsets(), titleHeight: CGFloat? = 20)
        -> EtagereLayout {
        let metrics = EtagereMetrics.automatic.resolved(containerWidth: width, isTelevision: false)
        return EtagereLayout(
            size: CGSize(width: width, height: 800), safeArea: safeArea, metrics: metrics, aspectRatio: 16.0 / 9.0,
            titleHeight: titleHeight
        )
    }

    @Test("A shelf is its title, a gap and the ring's reserved (enlarged) height")
    func shelfHeight() {
        let layout = layout(width: 1280)
        let cardHeight = layout.metrics.cardWidth * 9 / 16
        #expect(abs(layout.cardSize.height - cardHeight) < 1e-9)
        #expect(abs(layout.ringHeight - cardHeight * layout.metrics.activeScale) < 1e-9)
        #expect(layout.shelfHeight == 20 + layout.titleSpacing + layout.ringHeight)
        let shelves = layout.shelvesGeometry(EtagereConfiguration())
        #expect(shelves.idleLength == layout.shelfHeight && shelves.activeLength == layout.shelfHeight)
        #expect(shelves.spacing == layout.metrics.shelfSpacing)
        let ring = layout.ringGeometry(EtagereConfiguration(horizontalAlignment: .trailing))
        #expect(ring.anchor == .trailing)
        #expect(ring.leadingInset == layout.leadingInset)
    }

    @Test("Insets keep the anchor inside the safe area, with a base inset per width class",
          arguments: [(CGFloat(400), CGFloat(16)), (700, 24), (1280, 32)])
    func insets(width: CGFloat, base: CGFloat) {
        #expect(layout(width: width).leadingInset == base)
        let notched = layout(width: width, safeArea: EdgeInsets(top: 50, leading: 59, bottom: 0, trailing: 10))
        #expect(notched.leadingInset == 59)
        #expect(notched.trailingInset == base)
        #expect(notched.topInset == 50)
        #expect(notched.bottomInset >= notched.highlightPadding.height)
    }

    @Test("Before the title is measured, an estimate per title style stands in")
    func estimatedTitle() {
        let unmeasured = layout(width: 1280, titleHeight: nil)
        #expect(unmeasured.titleHeight == EtagereLayout.estimatedTitleHeight(for: unmeasured.metrics.titleStyle))
        #expect(EtagereLayout.estimatedTitleHeight(for: .televisionTitle3) == 58)
    }

    @Test("The render window covers the rotations in flight and a fractional phase")
    func coveredRotations() {
        #expect(RingPhase.coveredRotations(0...3, phase: 3) == 0...3)
        #expect(RingPhase.coveredRotations(0...0, phase: 0.25) == 0...1)
        #expect(RingPhase.coveredRotations(0...0, phase: -0.5) == -1...0)
        #expect(RingPhase.coveredRotations(2...2, phase: 4.6) == 2...5)
        #expect(RingPhase.coveredRotations(1...4, phase: .nan) == 1...4)
        #expect(RingPhase.union(0...3, -1...2) == -1...3)
        #expect(RingPhase.activity(atSlot: 0) == 1)
        #expect(RingPhase.activity(atSlot: -0.25) == 0.75)
        #expect(RingPhase.activity(atSlot: 1.5) == 0)
    }

    @Test("Cross alignment and the mode 2 scroll anchor")
    func alignments() {
        #expect(ShelfCardCrossAlignment.bottom.stackAlignment == .bottomLeading)
        #expect(ShelfCardCrossAlignment.bottom.scaleAnchor == .bottom)
        #expect(ShelfCardCrossAlignment.center.stackAlignment == .leading)
        #expect(ShelfCardCrossAlignment.top.scaleAnchor == .top)
        #expect(EtagereVerticalAlignment.center.scrollAnchor == .center)
        #expect(EtagereVerticalAlignment.bottom.scrollAnchor == .bottom)
    }

    @Test("A shelf's VoiceOver value: the card, its position, or the placeholder's message")
    func accessibilityValue() {
        #expect(ShelfAccessibilityText.value(cardTitle: "KUSA 9.1, NBC", index: 2, count: 8, emptyMessage: nil)
            == "KUSA 9.1, NBC, 3 of 8")
        #expect(ShelfAccessibilityText.value(cardTitle: nil, index: nil, count: 0, emptyMessage: "Add a DVR")
            == "Add a DVR")
        #expect(ShelfAccessibilityText.value(cardTitle: nil, index: nil, count: 0, emptyMessage: "")
            == ShelfAccessibilityText.emptyShelf)
        #expect(ShelfAccessibilityText.value(cardTitle: "KUSA", index: 0, count: 2, emptyMessage: nil, isUpdating: true)
            == "KUSA, 1 of 2, Updating")
        #expect(ShelfAccessibilityText.value(cardTitle: nil, index: nil, count: 0, emptyMessage: nil, isUpdating: true)
            == "\(ShelfAccessibilityText.emptyShelf), Updating")
    }

    @Test("Reduce Motion replaces a card whose emphasis changes, so its sizes crossfade instead of zooming (§4)")
    func emphasisCrossfadeIdentity() {
        #expect(RingSlotPlacement.crossfadeIdentity(isEmphasized: true, reduceMotion: false) == nil)
        #expect(RingSlotPlacement.crossfadeIdentity(isEmphasized: false, reduceMotion: false) == nil)
        #expect(RingSlotPlacement.crossfadeIdentity(isEmphasized: true, reduceMotion: true) == true)
        #expect(RingSlotPlacement.crossfadeIdentity(isEmphasized: false, reduceMotion: true) == false)
    }

    @Test("Start of list when the seam crosses the anchor going forward; End of list going back (Q5)")
    @MainActor
    func seamAnnouncement() {
        #expect(ShelfAccessibilityText.seamAnnouncement(fromLap: 0, toLap: 1) == ShelfAccessibilityText.startOfList)
        #expect(ShelfAccessibilityText.seamAnnouncement(fromLap: 0, toLap: -1) == ShelfAccessibilityText.endOfList)
        #expect(ShelfAccessibilityText.seamAnnouncement(fromLap: 2, toLap: 2) == nil)
        let shelf = ShelfState(Fixture.shelf("live", cardCount: 3))
        #expect(shelf.accessibilityValueText == "live-A, 1 of 3")
        shelf.rotate(by: -1)
        #expect(shelf.accessibilityValueText == "live-C, 3 of 3")
        #expect(RingMath.floorDiv(shelf.rotation, 3) == -1, "the lap changed: the seam crossed the anchor")
        let updating = ShelfState(Shelf(id: "live", title: "Live", cards: [PlainCard("A")], isUpdating: true))
        #expect(updating.accessibilityValueText == "A, 1 of 1, Updating")
    }
}
