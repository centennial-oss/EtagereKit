@testable import EtagereKit
import Testing

/// Stands in for the repeat timer: each wait returns only when the test fires it.
@MainActor
final class ManualRepeatClock {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var requested: [Int] = []

    func wait(_ index: Int) async {
        requested.append(index)
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Ends the oldest wait, once the repeat task has started waiting, and lets the task run.
    func fire() async {
        await settle()
        if !waiting.isEmpty { waiting.removeFirst().resume() }
        await settle()
    }

    /// Ends every wait, so no task is left suspended.
    func drain() async {
        await settle()
        while !waiting.isEmpty { await fire() }
    }

    /// Lets tasks on the main actor run until they wait again.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

/// What a gamepad sent the Etagere it is attached to.
@MainActor
final class PressLog {
    var presses: [String] = []
    var consumes = true

    func attach(to gamepad: EtagereGamepad) {
        gamepad.attach(owner: ObjectIdentifier(self)) { [self] key, isRepeat in
            presses.append(isRepeat ? "\(key.rawValue) again" : key.rawValue)
            return consumes
        }
    }
}

@MainActor
@Suite("Game controllers through the host-fed EtagereGamepad (behavior §3.3)")
struct GamepadTests {
    @Test("Nothing is taken while no Etagere is attached")
    func unattached() {
        let gamepad = EtagereGamepad()
        #expect(!gamepad.isAttached)
        #expect(!gamepad.directionChanged(.dpad, xValue: 1, yValue: 0))
        #expect(!gamepad.directionChanged(.dpad, xValue: 0, yValue: 0))
        #expect(!gamepad.buttonChanged(.buttonA, isPressed: true))
        #expect(!gamepad.buttonChanged(.buttonB, isPressed: true))
        #expect(!gamepad.buttonChanged(.buttonB, isPressed: false))
    }

    @Test("Directions past half way press arrows; the d-pad wins over the stick; A and B are Return and Esc")
    func directionsAndButtons() async {
        let clock = ManualRepeatClock()
        let gamepad = EtagereGamepad(waitBeforeRepeat: clock.wait)
        let log = PressLog()
        log.attach(to: gamepad)
        #expect(gamepad.isAttached)
        #expect(!gamepad.directionChanged(.leftStick, xValue: 0.4, yValue: 0.1), "inside the dead zone")
        #expect(gamepad.directionChanged(.leftStick, xValue: -0.7, yValue: 0.2))
        #expect(gamepad.directionChanged(.leftStick, xValue: -0.9, yValue: 0), "still left: no new press")
        #expect(gamepad.directionChanged(.dpad, xValue: 0, yValue: 1))
        #expect(gamepad.directionChanged(.dpad, xValue: 0, yValue: 0), "the stick is still held left")
        #expect(gamepad.directionChanged(.leftStick, xValue: 0, yValue: 0), "a release goes with its press")
        #expect(gamepad.buttonChanged(.buttonA, isPressed: true))
        #expect(gamepad.buttonChanged(.buttonA, isPressed: false))
        #expect(gamepad.buttonChanged(.buttonB, isPressed: true))
        #expect(log.presses == ["leftArrow", "upArrow", "leftArrow", "returnKey", "escape"])
        await clock.drain()
    }

    @Test("A held direction repeats after 400 ms, then every 110 ms, until it is released")
    func heldDirectionRepeats() async {
        let clock = ManualRepeatClock()
        let gamepad = EtagereGamepad(waitBeforeRepeat: clock.wait)
        let log = PressLog()
        log.attach(to: gamepad)
        gamepad.directionChanged(.dpad, xValue: 1, yValue: 0)
        await clock.fire()
        await clock.fire()
        #expect(log.presses == ["rightArrow", "rightArrow again", "rightArrow again"])
        #expect(clock.requested == [0, 1, 2])
        #expect([0, 1, 2].map(ControllerStick.delay(beforeRepeat:)) == [0.4, 0.11, 0.11])
        gamepad.directionChanged(.dpad, xValue: 0, yValue: 0)
        await clock.drain()
        #expect(log.presses.count == 3, "no repeat after the release")
    }

    @Test("Input the Etagere does not use is not taken, and does not repeat")
    func unusedInput() async {
        let clock = ManualRepeatClock()
        let gamepad = EtagereGamepad(waitBeforeRepeat: clock.wait)
        let log = PressLog()
        log.consumes = false
        log.attach(to: gamepad)
        #expect(!gamepad.directionChanged(.dpad, xValue: -1, yValue: 0))
        #expect(!gamepad.buttonChanged(.buttonB, isPressed: true), "the host may use B as its own back button")
        #expect(!gamepad.buttonChanged(.buttonB, isPressed: false))
        #expect(clock.requested.isEmpty)
        await clock.drain()
    }

    @Test("Only the attached Etagere takes input; a newly focused one takes over and sees only new presses")
    func attachAndDetach() async {
        let clock = ManualRepeatClock()
        let gamepad = EtagereGamepad(waitBeforeRepeat: clock.wait)
        let first = PressLog()
        let second = PressLog()
        first.attach(to: gamepad)
        gamepad.directionChanged(.dpad, xValue: 1, yValue: 0)
        second.attach(to: gamepad)
        await clock.drain()
        #expect(gamepad.directionChanged(.dpad, xValue: 1, yValue: 0.1), "still the first Etagere's direction")
        #expect(second.presses.isEmpty, "a direction held for another Etagere stays with it")
        #expect(gamepad.directionChanged(.dpad, xValue: 0, yValue: 0))
        gamepad.detach(owner: ObjectIdentifier(first))
        #expect(gamepad.isAttached, "detaching an Etagere that is not attached changes nothing")
        #expect(gamepad.directionChanged(.dpad, xValue: 0, yValue: -1))
        #expect(second.presses == ["downArrow"])
        gamepad.detach(owner: ObjectIdentifier(second))
        #expect(!gamepad.isAttached)
        await clock.drain()
        #expect(second.presses == ["downArrow"], "detaching stops the repeats")
        #expect(first.presses == ["rightArrow"])
    }

    @Test("releaseAll lets go of everything, so the next touch is a new press")
    func releaseAll() async {
        let clock = ManualRepeatClock()
        let gamepad = EtagereGamepad(waitBeforeRepeat: clock.wait)
        let log = PressLog()
        log.attach(to: gamepad)
        gamepad.directionChanged(.leftStick, xValue: 0, yValue: -1)
        gamepad.releaseAll()
        await clock.drain()
        gamepad.directionChanged(.leftStick, xValue: 0, yValue: -1)
        #expect(log.presses == ["downArrow", "downArrow"])
        gamepad.releaseAll()
        await clock.drain()
    }

    @Test("Through the controller, the gamepad turns the ring, plays and leaves")
    func drivesTheController() async {
        let model = Fixture.model(cardCounts: [4, 4])
        let host = HostLog()
        let controller = EtagereController(model: model)
        controller.update(model: model, handlers: host.handlers(), reduceMotion: true)
        let clock = ManualRepeatClock()
        let gamepad = EtagereGamepad(waitBeforeRepeat: clock.wait)
        gamepad.attach(owner: ObjectIdentifier(controller)) { [weak controller] key, isRepeat in
            controller?.perform(key: key, isRightToLeft: false, reportedRepeat: isRepeat) ?? false
        }
        gamepad.directionChanged(.dpad, xValue: 1, yValue: 0)
        await clock.fire()
        gamepad.directionChanged(.dpad, xValue: 0, yValue: 0)
        #expect(model.activeCard?.id == "s0-C")
        gamepad.directionChanged(.leftStick, xValue: 0, yValue: -1)
        #expect(model.activeShelf?.id == "s1")
        #expect(gamepad.buttonChanged(.buttonA, isPressed: true))
        #expect(host.activated == ["s1-A"])
        #expect(gamepad.buttonChanged(.buttonB, isPressed: true))
        #expect(host.exits == 1)
        gamepad.releaseAll()
        await clock.drain()
    }
}
