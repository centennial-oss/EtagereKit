import EtagereKit
import SwiftUI
import Testing

@Suite("Input: the key map (behavior §3) and the repeat detector (§1.8)")
struct EtagereInputTests {
    // MARK: T18

    @Test("T18 left-to-right: arrows move, Return, keypad Enter, Space and K activate, Esc exits", arguments: [
        (EtagereKey.leftArrow, EtagereIntent.move(.previousCard)), (.rightArrow, .move(.nextCard)),
        (.upArrow, .move(.previousShelf)), (.downArrow, .move(.nextShelf)), (.returnKey, .activate),
        (.keypadEnter, .activate), (.space, .activate), (.letterK, .activate), (.escape, .exit)
    ])
    func leftToRight(key: EtagereKey, expected: EtagereIntent) {
        #expect(EtagereKeyMap.intent(for: key, isRightToLeft: false) == expected)
    }

    @Test("T18 right-to-left mirrors only left and right", arguments: EtagereKey.allCases)
    func rightToLeft(key: EtagereKey) {
        let ltr = EtagereKeyMap.intent(for: key, isRightToLeft: false)
        let rtl = EtagereKeyMap.intent(for: key, isRightToLeft: true)
        switch key {
        case .leftArrow: #expect(rtl == .move(.nextCard))
        case .rightArrow: #expect(rtl == .move(.previousCard))
        default: #expect(rtl == ltr)
        }
    }

    @Test("T18 SwiftUI's key characters map to the Etagere's keys")
    func swiftUIKeyCharacters() {
        let pairs: [(KeyEquivalent, EtagereKey)] = [
            (.leftArrow, .leftArrow), (.rightArrow, .rightArrow), (.upArrow, .upArrow), (.downArrow, .downArrow),
            (.return, .returnKey), (.space, .space), (.escape, .escape), (KeyEquivalent("k"), .letterK)
        ]
        for (equivalent, key) in pairs {
            #expect(EtagereKey(character: equivalent.character) == key)
        }
        #expect(EtagereKey(character: "K") == .letterK)
        #expect(EtagereKey(character: "\u{3}") == .keypadEnter)
        #expect(EtagereKey(character: "j") == nil)
        #expect(EtagereKey(character: KeyEquivalent.tab.character) == nil)
        #expect(EtagereKeyMap.intent(forCharacter: KeyEquivalent.rightArrow.character, isRightToLeft: true)
            == .move(.previousCard))
        #expect(EtagereKeyMap.intent(forCharacter: "x", isRightToLeft: false) == nil)
    }

    @Test("T18 move helpers")
    func moveHelpers() {
        #expect(EtagereMove.allCases.filter(\.isHorizontal) == [.previousCard, .nextCard])
        #expect(EtagereMove.allCases.map(\.delta) == [-1, 1, -1, 1])
    }

    // MARK: RepeatDetector

    @Test("Moves in the same direction under 180 ms apart are repeats")
    func repeatThreshold() {
        var detector = RepeatDetector()
        #expect(detector.register(.nextCard, at: 0) == RepeatSample(isRepeat: false, interval: nil))
        let boundary = detector.register(.nextCard, at: 0.18)
        #expect(!boundary.isRepeat, "180 ms apart is not a repeat")
        #expect(boundary.interval == 0.18)
        let quick = detector.register(.nextCard, at: 0.3)
        #expect(quick.isRepeat)
        #expect(abs((quick.interval ?? 0) - 0.12) < 1e-9)
        #expect(detector.register(.nextCard, at: 0.479).isRepeat, "179 ms apart is a repeat")
    }

    @Test("A direction change, a clock going backwards or a reset starts over")
    func repeatResets() {
        var detector = RepeatDetector()
        _ = detector.register(.nextCard, at: 1)
        #expect(detector.register(.previousCard, at: 1.05) == RepeatSample(isRepeat: false, interval: nil))
        #expect(detector.register(.previousCard, at: 1.0) == RepeatSample(isRepeat: false, interval: nil))
        #expect(detector.register(.previousCard, at: 1.1).isRepeat)
        detector.reset()
        #expect(!detector.register(.previousCard, at: 1.15).isRepeat)
        _ = detector.register(.nextShelf, at: 2)
        #expect(detector.register(.nextShelf, at: 2.05).isRepeat)
    }

    @Test("A custom threshold")
    func customThreshold() {
        var detector = RepeatDetector(threshold: 0.3)
        _ = detector.register(.nextShelf, at: 0)
        #expect(detector.register(.nextShelf, at: 0.25).isRepeat)
        #expect(RepeatDetector().threshold == RepeatDetector.defaultThreshold)
    }

    @Test("Measured intervals are clamped to 60-200 ms for the repeat animation", arguments: [
        (0.01, 0.06), (0.06, 0.06), (0.1, 0.1), (0.2, 0.2), (0.75, 0.2), (-1.0, 0.06), (Double.nan, 0.12)
    ])
    func animationInterval(measured: Double, expected: Double) {
        #expect(RepeatDetector.animationInterval(forMeasured: measured) == expected)
    }
}
