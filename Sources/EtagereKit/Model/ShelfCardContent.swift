import SwiftUI

/// What a card face may need to know about where it is. A cheap value, so faces stay `Equatable` and render once.
public nonisolated struct ShelfCardContext: Sendable, Equatable {
    /// The Active ShelfCard: anchored on the Active Shelf, the one "go" triggers (R8). True for exactly one card in
    /// the Etagere (R9).
    public var isActive: Bool
    /// Anchored on its shelf, whether that shelf is active or not.
    public var isAnchored: Bool
    public var isShelfActive: Bool
    public var ringIndex: Int
    public var ringCount: Int
    /// The idle face size; the ring scales the Active ShelfCard up from it.
    public var faceSize: CGSize

    public init(
        isActive: Bool, isAnchored: Bool, isShelfActive: Bool, ringIndex: Int, ringCount: Int, faceSize: CGSize
    ) {
        self.isActive = isActive
        self.isAnchored = isAnchored
        self.isShelfActive = isShelfActive
        self.ringIndex = ringIndex
        self.ringCount = ringCount
        self.faceSize = faceSize
    }
}

/// Anything that can sit on a Shelf (etagere.md §4.1). The conforming type draws its own face, the same pattern as
/// `ButtonStyle.makeBody`, so an Etagere needs one generic parameter, its shelves can never mix card kinds, and no
/// `AnyView` is involved.
///
/// In a MainActor-default target, both the conforming type and the conformance must be `nonisolated`, or the
/// conformances become main-actor-isolated and cannot satisfy `Sendable` (etagere.md §4.4). Declare the conformance
/// on the type itself or in a `nonisolated extension`; a plain extension is main-actor-isolated by default, so
/// `extension Card: ShelfCardContent` fails to compile there, crossing into main-actor-isolated code:
///
/// ```swift
/// nonisolated struct VideoCard: Identifiable, Hashable, Sendable { ... }   // VideoCard.swift
///
/// nonisolated extension VideoCard: ShelfCardContent {                     // VideoCardFace.swift
///     var accessibilityTitle: String { ... }
///     @MainActor func makeFace(context: ShelfCardContext) -> some View { ... }
/// }
/// ```
///
/// Card IDs must be unique within a shelf.
public nonisolated protocol ShelfCardContent: Identifiable, Equatable, Sendable where ID: Sendable {
    associatedtype Face: View

    /// The face's width / height: 16:9 for video by default, about 0.71 for box art.
    static var faceAspectRatio: CGFloat { get }

    /// A full phrase for VoiceOver, for example "KUSA 9.1, NBC, live now, favorite".
    var accessibilityTitle: String { get }

    @MainActor @ViewBuilder
    func makeFace(context: ShelfCardContext) -> Face
}

nonisolated extension ShelfCardContent {
    public static var faceAspectRatio: CGFloat { 16.0 / 9.0 }
}
