import SwiftUI
import AppKit
import SpotifyLyricsCore

@MainActor
final class DominantColorExtractor: ObservableObject {
    @Published var dominantColor: Color = .white
    @Published var accentColor: Color = .gray
    @Published var backgroundColor: Color = .black
    @Published var albumText: [String] = []

    private let visionAnalyzer = VisionAnalyzer()
    private var cachedURL: URL?

    func extractColor(from url: URL?) {
        guard let url, url != cachedURL else { return }
        cachedURL = url

        // Use Vision-based analysis for rich palette
        visionAnalyzer.analyze(imageURL: url)

        // Observe Vision results
        Task { @MainActor in
            // Give Vision a moment to process
            try? await Task.sleep(nanoseconds: 500_000_000)

            if let palette = self.visionAnalyzer.palette {
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.dominantColor = Color(nsColor: palette.dominant)
                    self.accentColor = Color(nsColor: palette.accent)
                    self.backgroundColor = Color(nsColor: palette.background)
                }
            } else {
                // Fallback to simple average color
                guard let color = DominantColorExtractor.computeAverageColor(from: url) else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    self.dominantColor = Color(nsColor: color)
                }
            }

            self.albumText = self.visionAnalyzer.detectedText
        }
    }

    private nonisolated static func computeAverageColor(from url: URL) -> NSColor? {
        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let width = 1
        let height = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixel: [UInt8] = [0, 0, 0, 0]

        guard let context = CGContext(
            data: &pixel,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0

        let nsColor = NSColor(red: r, green: g, blue: b, alpha: 1.0)
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let adjustedBrightness = max(brightness, 0.6)
        let adjustedSaturation = min(saturation * 1.2, 1.0)

        return NSColor(hue: hue, saturation: adjustedSaturation, brightness: adjustedBrightness, alpha: 1.0)
    }
}
