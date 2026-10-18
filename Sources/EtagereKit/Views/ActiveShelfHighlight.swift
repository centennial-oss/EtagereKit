import SwiftUI

/// The Active Shelf's indicator (R25): a tinted rounded rectangle behind the shelf. In mode 1 it stays fixed at the
/// anchor while shelves slide beneath it; in mode 2 one highlight slides between rows. It is deliberately not
/// Liquid Glass: glass belongs to the floating navigation layer (behavior §2.1). Increase Contrast strengthens the
/// tint and adds an outline (behavior §4).
struct ActiveShelfHighlight: View {
    var cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    static var tintOpacity: Double { 0.14 }
    static var increasedContrastTintOpacity: Double { 0.26 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if contrast == .increased {
            shape
                .fill(.tint.opacity(Self.increasedContrastTintOpacity))
                .overlay { shape.strokeBorder(.tint, lineWidth: 2) }
                .accessibilityHidden(true)
        } else {
            shape
                .fill(.tint.opacity(Self.tintOpacity))
                .accessibilityHidden(true)
        }
    }
}
