/// The animations still moving one ring, which decide its render window (behavior §1.5, D3, D4).
///
/// Every animated rotation is a flight from one rotation to the next, ended by its settle token once SwiftUI has
/// removed its animation. While flights run, the window covers every rotation the ring has had since the oldest
/// flight still running took off: SwiftUI runs overlapping timing-curve animations additively and retargets
/// springs, so the ring's presentation stays between those rotations and no card in flight is dropped. As the
/// oldest flights land, that start moves up behind them, so a held key keeps the window a few cards wide however
/// long the ring is. The latest flight landing lands them all, as before, so a lost completion cannot pin the
/// window. A jump forgets every flight, and their late completions change nothing (T13).
nonisolated struct RingFlights: Sendable, Equatable {
    /// The farthest the window reaches from the target rotation: the longest single flight (a 30-slot fling) plus
    /// ten steps. A backstop for a completion that never arrives; a held key stays far inside it.
    static let maximumLag = RingDragMath.maximumReleaseSlots + 10

    private struct Flight: Sendable, Equatable {
        let token: Int
        let origin: Int
        let target: Int
        var hasLanded = false
    }

    /// The flights since the oldest one still running, in the order they took off. Each starts where the previous
    /// one ended, so together they trace every rotation the ring has had since.
    private var flights: [Flight] = []
    private var lastToken = 0

    /// True when nothing is in flight.
    var isIdle: Bool { flights.isEmpty }

    /// Records an animated rotation from `origin` to `target` and returns its settle token (always positive).
    mutating func takeOff(from origin: Int, to target: Int) -> Int {
        lastToken += 1
        flights.append(Flight(token: lastToken, origin: origin, target: target))
        return lastToken
    }

    /// Lands the flight that returned `token`. The latest flight lands them all; an older one lands only itself,
    /// and the window's far end moves up past every landed flight at the front. Returns false for a token that is
    /// not in flight: a no-op, a flight already landed, or one a jump forgot.
    @discardableResult
    mutating func land(_ token: Int) -> Bool {
        guard let index = flights.firstIndex(where: { $0.token == token }) else { return false }
        if index == flights.count - 1 {
            flights.removeAll()
        } else {
            flights[index].hasLanded = true
            flights.removeFirst(flights.firstIndex { !$0.hasLanded } ?? flights.count)
        }
        return true
    }

    /// Forgets every flight: a jump or a reload settles the ring at once.
    mutating func removeAll() {
        flights.removeAll()
    }

    /// Where the oldest flight still running took off; `rotation` when nothing is in flight.
    func settledRotation(at rotation: Int) -> Int {
        flights.first?.origin ?? rotation
    }

    /// The rotations the render window covers with the ring's target at `rotation`: every rotation since the oldest
    /// flight still running took off, at most `maximumLag` away from the target.
    func coveredRotations(at rotation: Int) -> ClosedRange<Int> {
        var low = rotation
        var high = rotation
        if let first = flights.first {
            low = min(low, first.origin)
            high = max(high, first.origin)
        }
        for flight in flights {
            low = min(low, flight.target)
            high = max(high, flight.target)
        }
        return max(low, rotation - Self.maximumLag)...min(high, rotation + Self.maximumLag)
    }
}
