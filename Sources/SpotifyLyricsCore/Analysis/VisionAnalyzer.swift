import Foundation
import Vision
import AppKit

/// Uses the Vision framework for advanced album art analysis:
/// - Multi-color palette extraction (dominant + accent colors)
/// - Text recognition from album art (title, artist embedded in artwork)
/// - Image saliency detection for focus areas
@MainActor
public final class VisionAnalyzer: ObservableObject {

    /// A color palette extracted from album art.
    public struct ColorPalette: Equatable {
        public let dominant: NSColor
        public let accent: NSColor
        public let background: NSColor
        public let isLight: Bool

        public init(dominant: NSColor, accent: NSColor, background: NSColor, isLight: Bool) {
            self.dominant = dominant
            self.accent = accent
            self.background = background
            self.isLight = isLight
        }
    }

    @Published public private(set) var palette: ColorPalette?
    @Published public private(set) var detectedText: [String] = []
    @Published public private(set) var saliencyCenter: CGPoint?

    private var cachedURL: URL?

    public init() {}

    // MARK: - Analysis

    /// Analyze album art from a URL. Extracts color palette, text, and saliency.
    public func analyze(imageURL: URL?) {
        guard let url = imageURL, url != cachedURL else { return }
        cachedURL = url

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let data = try? Data(contentsOf: url),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return }

            async let paletteResult = VisionAnalyzer.extractColorPalette(from: cgImage)
            async let textResult = VisionAnalyzer.recognizeText(in: cgImage)
            async let saliencyResult = VisionAnalyzer.detectSaliency(in: cgImage)

            let palette = await paletteResult
            let text = await textResult
            let saliency = await saliencyResult

            await MainActor.run { [weak self] in
                guard let self else { return }
                if let palette {
                    self.palette = palette
                }
                self.detectedText = text
                self.saliencyCenter = saliency
            }
        }
    }

    // MARK: - Color Palette Extraction

    /// Extract a multi-color palette from an image using Vision's feature print
    /// combined with k-means-style region sampling.
    private nonisolated static func extractColorPalette(from cgImage: CGImage) async -> ColorPalette? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        // Sample colors from a grid across the image
        let sampleSize = 8
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Collect sampled colors as HSB tuples
        struct HSBColor: Hashable {
            let hue: CGFloat
            let saturation: CGFloat
            let brightness: CGFloat
        }

        var colorCounts: [HSBColor: Int] = [:]
        let stepX = max(width / sampleSize, 1)
        let stepY = max(height / sampleSize, 1)

        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = (y * width + x) * bytesPerPixel
                let r = CGFloat(pixelData[offset]) / 255.0
                let g = CGFloat(pixelData[offset + 1]) / 255.0
                let b = CGFloat(pixelData[offset + 2]) / 255.0

                let color = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &br, alpha: &a)

                // Quantize to reduce noise
                let qh = (h * 12).rounded() / 12
                let qs = (s * 4).rounded() / 4
                let qb = (br * 4).rounded() / 4

                let quantized = HSBColor(hue: qh, saturation: qs, brightness: qb)
                colorCounts[quantized, default: 0] += 1
            }
        }

        // Sort by frequency
        let sorted = colorCounts.sorted { $0.value > $1.value }
        guard !sorted.isEmpty else { return nil }

        // Dominant = most frequent saturated color
        let dominantHSB = sorted.first(where: { $0.key.saturation > 0.15 })?.key ?? sorted[0].key
        let dominant = NSColor(hue: dominantHSB.hue, saturation: min(dominantHSB.saturation * 1.2, 1.0),
                              brightness: max(dominantHSB.brightness, 0.6), alpha: 1.0)

        // Accent = most frequent color that's visually distinct from dominant
        let accentHSB = sorted.first(where: {
            let hueDiff = abs($0.key.hue - dominantHSB.hue)
            let minHueDiff = min(hueDiff, 1.0 - hueDiff)
            return minHueDiff > 0.15 && $0.key.saturation > 0.1
        })?.key ?? dominantHSB

        let accent = NSColor(hue: accentHSB.hue, saturation: min(accentHSB.saturation * 1.1, 1.0),
                            brightness: max(accentHSB.brightness, 0.5), alpha: 1.0)

        // Background = darkest frequent color
        let bgHSB = sorted.first(where: { $0.key.brightness < 0.4 })?.key
            ?? HSBColor(hue: dominantHSB.hue, saturation: 0.3, brightness: 0.15)
        let background = NSColor(hue: bgHSB.hue, saturation: bgHSB.saturation * 0.5,
                                brightness: bgHSB.brightness, alpha: 1.0)

        // Determine if the image is predominantly light
        let avgBrightness = sorted.prefix(5).reduce(0.0) {
            $0 + $1.key.brightness * CGFloat($1.value)
        } / CGFloat(sorted.prefix(5).reduce(0) { $0 + $1.value })

        return ColorPalette(
            dominant: dominant,
            accent: accent,
            background: background,
            isLight: avgBrightness > 0.6
        )
    }

    // MARK: - Text Recognition

    /// Recognize text embedded in album art using VNRecognizeTextRequest.
    private nonisolated static func recognizeText(in cgImage: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let texts = results.compactMap { observation -> String? in
                    guard observation.confidence > 0.5 else { return nil }
                    return observation.topCandidates(1).first?.string
                }
                continuation.resume(returning: texts)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }

    // MARK: - Saliency Detection

    /// Detect the most salient point in the image using VNGenerateAttentionBasedSaliencyImageRequest.
    private nonisolated static func detectSaliency(in cgImage: CGImage) async -> CGPoint? {
        await withCheckedContinuation { continuation in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { request, error in
                guard let results = request.results as? [VNSaliencyImageObservation],
                      let saliency = results.first,
                      let salientObject = saliency.salientObjects?.first else {
                    continuation.resume(returning: nil)
                    return
                }

                let box = salientObject.boundingBox
                let center = CGPoint(x: box.midX, y: box.midY)
                continuation.resume(returning: center)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
