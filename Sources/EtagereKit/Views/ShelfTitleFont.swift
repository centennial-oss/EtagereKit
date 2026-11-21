import SwiftUI

/// The font of a shelf title, or of the status text beside it: the title style's own font, or with a host's
/// `titleFontSize` (D10) the system font at that size and the style's weight, scaled with Dynamic Type relative to
/// the style's text style.
struct ShelfTitleFont: ViewModifier {
    let style: EtagereTitleStyle
    let pointSize: CGFloat?
    let isStatus: Bool
    @ScaledMetric private var scaledSize: CGFloat

    init(style: EtagereTitleStyle, pointSize: CGFloat?, isStatus: Bool = false) {
        self.style = style
        self.pointSize = pointSize
        self.isStatus = isStatus
        let base = (pointSize ?? 0) * (isStatus ? EtagereTitleStyle.statusSizeRatio : 1)
        _scaledSize = ScaledMetric(wrappedValue: base, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content.font(font)
    }

    private var font: Font {
        guard pointSize != nil else { return isStatus ? style.statusFont : style.font }
        return .system(size: scaledSize, weight: isStatus ? .regular : style.weight)
    }
}

extension View {
    /// The shelf title font for these metrics (D10).
    func shelfTitleFont(_ metrics: EtagereResolvedMetrics, isStatus: Bool = false) -> some View {
        modifier(ShelfTitleFont(style: metrics.titleStyle, pointSize: metrics.validTitleFontSize, isStatus: isStatus))
    }
}
