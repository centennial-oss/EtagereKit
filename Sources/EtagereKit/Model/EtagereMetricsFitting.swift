import SwiftUI

nonisolated extension EtagereResolvedMetrics {
    /// These metrics with the largest card width at which `count` whole shelves fill `height` (behavior §6.1,
    /// D10): the top and bottom insets, `count` shelves (title, title spacing and reserved ring height each) and
    /// the shelf spacing between them. Everything but the card width stays. It uses the same layout the Etagere
    /// draws with, so it keeps fitting when EtagereKit's insets or spacing change. `EtagereMetrics.fitting` does
    /// this inside the Etagere with the title height it measures.
    ///
    /// - Parameters:
    ///   - count: Shelves to show at once; below 1 returns these metrics unchanged.
    ///   - height: The Etagere's height.
    ///   - aspectRatio: The card face's aspect ratio (`ShelfCardContent.faceAspectRatio`).
    ///   - titleHeight: One line of `titleStyle`; nil for `EtagereResolvedMetrics.estimatedTitleHeight`.
    ///   - safeArea: The Etagere's safe area; its top and bottom can enlarge the insets.
    ///   - cardCrossAlignment: Where a growing Active ShelfCard reaches past its ring when
    ///     `activeGrowthReserve` is below 1, which can enlarge the insets.
    /// - Returns: At least a 1 pt card width, even when the titles and insets alone overflow `height`.
    public func fitting(
        shelves count: Int,
        in height: CGFloat,
        aspectRatio: CGFloat,
        titleHeight: CGFloat? = nil,
        safeArea: EdgeInsets = EdgeInsets(),
        cardCrossAlignment: ShelfCardCrossAlignment = .center
    ) -> EtagereResolvedMetrics {
        guard count > 0, height.isFinite, height > 0 else { return self }
        func requiredHeight(cardWidth: CGFloat) -> CGFloat {
            var candidate = self
            candidate.cardWidth = cardWidth
            return EtagereLayout(
                size: CGSize(width: 0, height: height), safeArea: safeArea, metrics: candidate,
                aspectRatio: aspectRatio, titleHeight: titleHeight, cardCrossAlignment: cardCrossAlignment
            ).height(ofShelves: count)
        }
        // The required height grows with the card width, so bisect between a width that fits and one that does
        // not. Growing past the height stops the doubling; 64 halvings reach the limit of the precision.
        var fits: CGFloat = 0
        var overflows = max(height * max(aspectRatio, 1), 1)
        var doublings = 0
        while requiredHeight(cardWidth: overflows) <= height, doublings < 64 {
            fits = overflows
            overflows *= 2
            doublings += 1
        }
        for _ in 0..<64 {
            let middle = (fits + overflows) / 2
            if requiredHeight(cardWidth: middle) <= height { fits = middle } else { overflows = middle }
        }
        var fitted = self
        fitted.cardWidth = max(fits, 1)
        return fitted
    }
}
