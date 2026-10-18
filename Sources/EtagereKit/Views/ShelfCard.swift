import SwiftUI

/// The chrome around a card face (etagere.md §4.2): the idle size, a continuous corner shape and a compositing
/// group, so a fading card composites once instead of per layer. The ring scales and dims it from outside, so the
/// face lays out once at idle size and never reflows.
public struct ShelfCard<Card: ShelfCardContent>: View, Equatable {
    public let card: Card
    public let context: ShelfCardContext
    /// The accent ring around the Active ShelfCard while the Etagere has keyboard focus (behavior §4).
    var showsFocusRing = false
    /// The Increase Contrast outline on the Active ShelfCard (behavior §4).
    var showsContrastOutline = false

    public init(card: Card, context: ShelfCardContext) {
        self.card = card
        self.context = context
    }

    init(card: Card, context: ShelfCardContext, showsFocusRing: Bool, showsContrastOutline: Bool) {
        self.card = card
        self.context = context
        self.showsFocusRing = showsFocusRing
        self.showsContrastOutline = showsContrastOutline
    }

    public var body: some View {
        let shape = ShelfCardChrome.shape(forWidth: context.faceSize.width)
        card.makeFace(context: context)
            .frame(width: context.faceSize.width, height: context.faceSize.height)
            .clipShape(shape)
            .overlay {
                if showsContrastOutline {
                    shape.strokeBorder(.primary, lineWidth: 2)
                }
            }
            .overlay {
                if showsFocusRing {
                    shape.inset(by: -5).strokeBorder(.tint, lineWidth: 3)
                }
            }
            .compositingGroup()
            .accessibilityHidden(true)
    }
}

/// The card shape shared by faces and placeholders.
nonisolated enum ShelfCardChrome {
    /// About 5% of the card width, at least 8 pt.
    static func cornerRadius(forWidth width: CGFloat) -> CGFloat {
        max(8, (width * 0.05).rounded())
    }

    static func shape(forWidth width: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius(forWidth: width), style: .continuous)
    }
}

/// The one navigable placeholder card of an empty shelf (Q7): its `emptyMessage` on a quiet tile at idle size.
/// "Go" on it runs the host's empty-shelf action.
struct EmptyShelfCard: View, Equatable {
    let message: String
    let size: CGSize
    var showsFocusRing = false
    var showsContrastOutline = false

    var body: some View {
        let shape = ShelfCardChrome.shape(forWidth: size.width)
        ZStack {
            shape.fill(.quaternary)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .minimumScaleFactor(0.6)
                .padding(size.width * 0.06)
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if showsContrastOutline {
                shape.strokeBorder(.primary, lineWidth: 2)
            }
        }
        .overlay {
            if showsFocusRing {
                shape.inset(by: -5).strokeBorder(.tint, lineWidth: 3)
            }
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }
}
