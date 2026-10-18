import CoreGraphics
@_spi(EtagereDebug) import EtagereKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A card whose face is a flat color: red for the Active ShelfCard, blue for other anchored cards and gray for the
/// rest, so a rendered frame can be checked pixel by pixel.
nonisolated struct SwatchCard: ShelfCardContent {
    let id: String

    var accessibilityTitle: String { id }

    @MainActor
    func makeFace(context: ShelfCardContext) -> some View {
        Rectangle().fill(context.isActive ? Color.red : context.isAnchored ? Color.blue : Color.gray)
    }
}

/// An RGB color with components in 0...1.
nonisolated struct PixelColor: Sendable {
    var red: Double
    var green: Double
    var blue: Double

    func isClose(to target: PixelColor) -> Bool {
        abs(red - target.red) < 0.2 && abs(green - target.green) < 0.2 && abs(blue - target.blue) < 0.2
    }

    /// Text, a seam bar or a dimmed card on the white background; not the light highlight tint.
    var isDark: Bool { max(red, green, blue) < 0.8 }

    /// The Active Shelf highlight on white: the accent (system blue) at a low opacity.
    var isHighlightTint: Bool { blue > 0.95 && red > 0.6 && red < 0.95 && blue - red > 0.04 }
}

/// A rendered frame's pixels, decoded once. Row 0 is the top of the frame.
nonisolated struct PixelImage {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(_ image: CGImage) {
        width = image.width
        height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        bytes = pixels
    }

    func color(column: Int, row: Int) -> PixelColor {
        let offset = (row * width + column) * 4
        return PixelColor(
            red: Double(bytes[offset]) / 255, green: Double(bytes[offset + 1]) / 255,
            blue: Double(bytes[offset + 2]) / 255
        )
    }

    /// The columns of one row whose color matches.
    func columns(row: Int, in range: Range<Int>? = nil, where matches: (PixelColor) -> Bool) -> [Int] {
        guard row >= 0, row < height else { return [] }
        return (range ?? 0..<width).clamped(to: 0..<width).filter { matches(color(column: $0, row: row)) }
    }

    /// The rows of one column whose color matches.
    func rows(column: Int, in range: Range<Int>? = nil, where matches: (PixelColor) -> Bool) -> [Int] {
        guard column >= 0, column < width else { return [] }
        return (range ?? 0..<height).clamped(to: 0..<height).filter { matches(color(column: column, row: $0)) }
    }
}

nonisolated extension [Int] {
    /// The middle of the span from the first to the last element.
    var spanCenter: Double? {
        guard let first, let last else { return nil }
        return Double(first + last) / 2
    }

    /// True when the elements are consecutive integers, one run without gaps.
    var isOneRun: Bool {
        guard let first, let last else { return false }
        return last - first + 1 == count
    }
}

/// Renders views with `ImageRenderer` (behavior §7.3). Set `ETAGERE_SNAPSHOT_DIR` to also write each frame as a
/// PNG for a person to look at; the tests never depend on it.
@MainActor
enum SnapshotHarness {
    static func render(_ view: some View, size: CGSize, name: String) -> CGImage? {
        let framed = view
            .frame(width: size.width, height: size.height)
            .background(Color.white)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        let image = renderer.cgImage
        if let image, let directory = ProcessInfo.processInfo.environment["ETAGERE_SNAPSHOT_DIR"] {
            write(image, to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        return image
    }

    static func etagere<Card>(_ model: EtagereModel<Card>, override: EtagerePhaseOverride? = nil) -> some View {
        Etagere(model: model) { _ in } onExit: {}
            .phaseOverride(override)
    }

    /// `Color.red` as rendered (the system red).
    static let systemRed = PixelColor(red: 1, green: 0.23, blue: 0.19)
    /// `Color.gray`, dimmed as an idle card on the Active Shelf.
    static let idleGray = PixelColor(red: 0.5, green: 0.5, blue: 0.5)

    /// The columns of one pixel row whose color is close to `target`.
    static func columns(in image: CGImage, row: Int, matching target: PixelColor) -> [Int] {
        PixelImage(image)?.columns(row: row) { $0.isClose(to: target) } ?? []
    }

    private static func write(_ image: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
