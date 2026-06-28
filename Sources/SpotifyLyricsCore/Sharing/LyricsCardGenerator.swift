import SwiftUI
import AppKit

/// Generates shareable lyrics card images using offscreen rendering.
@MainActor
public final class LyricsCardGenerator {

    public enum CardSize {
        case square     // 1080x1080
        case landscape  // 1920x1080

        public var dimensions: CGSize {
            switch self {
            case .square:    return CGSize(width: 1080, height: 1080)
            case .landscape: return CGSize(width: 1920, height: 1080)
            }
        }
    }

    public init() {}

    /// Generate a lyrics card as an NSImage.
    public func generateCard(
        line: LyricLine,
        enrichment: LineEnrichment?,
        title: String,
        artist: String,
        artworkImage: NSImage? = nil,
        accentColor: Color = .white,
        cardSize: CardSize = .square
    ) -> NSImage {
        let size = cardSize.dimensions
        let view = LyricsCardView(
            lineText: line.text,
            romanization: enrichment?.romanization,
            translation: enrichment?.translation,
            title: title,
            artist: artist,
            artworkImage: artworkImage,
            accentColor: accentColor,
            size: size
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0 // Retina
        renderer.proposedSize = .init(width: size.width, height: size.height)

        if let cgImage = renderer.cgImage {
            return NSImage(cgImage: cgImage, size: NSSize(width: size.width, height: size.height))
        }

        // Fallback: return a blank image
        return NSImage(size: NSSize(width: size.width, height: size.height))
    }

    /// Copy the generated card to the system clipboard.
    public func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    /// Save the generated card as a PNG file.
    public func saveAsPNG(_ image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CardGeneratorError.renderFailed
        }
        try pngData.write(to: url)
    }

    public enum CardGeneratorError: Error {
        case renderFailed
    }
}
