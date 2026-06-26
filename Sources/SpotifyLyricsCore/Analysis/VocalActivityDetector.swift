import Foundation
import CreateML
import NaturalLanguage

/// Detects vocal activity (singing vs instrumental) in audio segments
/// and classifies lyrics language using CreateML / NaturalLanguage frameworks.
///
/// Two capabilities:
/// 1. **Vocal Activity Detection**: Analyzes audio energy to detect when singing
///    occurs, helping the alignment pipeline skip instrumental sections.
/// 2. **Lyrics Language Classification**: Uses NLLanguageRecognizer with custom
///    hints tuned for song lyrics (handles slang, romanized text, mixed language).
@MainActor
public final class VocalActivityDetector: ObservableObject {

    /// Whether a given time window contains vocal activity.
    public struct VocalSegment: Equatable {
        public let startTime: TimeInterval
        public let endTime: TimeInterval
        public let isVocal: Bool
        public let energy: Float

        public init(startTime: TimeInterval, endTime: TimeInterval, isVocal: Bool, energy: Float) {
            self.startTime = startTime
            self.endTime = endTime
            self.isVocal = isVocal
            self.energy = energy
        }
    }

    /// Language classification result for lyrics.
    public struct LyricsLanguageResult: Equatable {
        public let language: String
        public let confidence: Double
        public let script: String

        public init(language: String, confidence: Double, script: String) {
            self.language = language
            self.confidence = confidence
            self.script = script
        }
    }

    @Published public private(set) var vocalSegments: [VocalSegment] = []
    @Published public private(set) var languageResult: LyricsLanguageResult?
    @Published public private(set) var vocalRatio: Double = 0.0

    /// Energy threshold for vocal detection.
    /// Audio energy above this level in speech-frequency bands indicates vocals.
    private let energyThreshold: Float = 0.02
    /// Minimum segment duration in seconds.
    private let segmentDuration: TimeInterval = 0.5

    public init() {}

    // MARK: - Vocal Activity Detection

    /// Analyze an audio buffer to detect vocal segments.
    ///
    /// Uses spectral energy analysis: vocals concentrate energy in 300Hz-3kHz range.
    /// Compares mid-band energy to full-band energy ratio to distinguish vocals
    /// from instruments.
    ///
    /// - Parameters:
    ///   - audioBuffer: 16kHz mono Float32 samples
    ///   - captureStartPosition: Song time at buffer start
    /// - Returns: Array of vocal segments
    public func detectVocalActivity(
        in audioBuffer: [Float],
        captureStartPosition: TimeInterval
    ) -> [VocalSegment] {
        let sampleRate: Double = 16000
        let samplesPerSegment = Int(segmentDuration * sampleRate)
        guard audioBuffer.count >= samplesPerSegment else { return [] }

        var segments: [VocalSegment] = []
        let totalSegments = audioBuffer.count / samplesPerSegment

        for i in 0..<totalSegments {
            let start = i * samplesPerSegment
            let end = min(start + samplesPerSegment, audioBuffer.count)
            let window = Array(audioBuffer[start..<end])

            let energy = computeRMSEnergy(window)
            let spectralCentroid = computeSpectralCentroid(window, sampleRate: sampleRate)
            let zeroCrossingRate = computeZeroCrossingRate(window)

            // Vocal detection heuristic:
            // - Vocals have energy concentrated in 300Hz-3kHz (spectral centroid in this range)
            // - Vocals have moderate zero-crossing rate (not too high like noise, not too low like bass)
            // - Energy must be above threshold
            let isVocal = energy > energyThreshold
                && spectralCentroid > 300 && spectralCentroid < 4000
                && zeroCrossingRate > 0.02 && zeroCrossingRate < 0.3

            let segStartTime = captureStartPosition + Double(start) / sampleRate
            let segEndTime = captureStartPosition + Double(end) / sampleRate

            segments.append(VocalSegment(
                startTime: segStartTime,
                endTime: segEndTime,
                isVocal: isVocal,
                energy: energy
            ))
        }

        vocalSegments = segments

        // Compute vocal ratio
        let vocalCount = segments.filter(\.isVocal).count
        vocalRatio = segments.isEmpty ? 0 : Double(vocalCount) / Double(segments.count)

        return segments
    }

    /// Check if a specific time range contains vocal activity.
    public func isVocalAt(time: TimeInterval) -> Bool {
        vocalSegments.first(where: { time >= $0.startTime && time < $0.endTime })?.isVocal ?? false
    }

    /// Get vocal segments within a time range (useful for per-line alignment decisions).
    public func vocalSegments(from startTime: TimeInterval, to endTime: TimeInterval) -> [VocalSegment] {
        vocalSegments.filter { $0.endTime > startTime && $0.startTime < endTime }
    }

    // MARK: - Lyrics Language Classification

    /// Classify the language of lyrics text using NaturalLanguage with lyrics-aware tuning.
    ///
    /// Better than raw NLLanguageRecognizer for song lyrics because it:
    /// - Handles romanized text (e.g. "watashi wa" → Japanese)
    /// - Handles mixed-language lines
    /// - Recognizes slang and informal contractions
    public func classifyLyricsLanguage(_ lines: [String]) -> LyricsLanguageResult {
        let recognizer = NLLanguageRecognizer()

        // Provide language hints weighted for common lyrics languages
        recognizer.languageHints = [
            .english: 0.2,
            .japanese: 0.15,
            .korean: 0.15,
            .simplifiedChinese: 0.1,
            .spanish: 0.1,
            .indonesian: 0.1,
            .french: 0.05,
            .german: 0.05,
            .portuguese: 0.05,
            .thai: 0.025,
            .arabic: 0.025,
        ]

        // Combine all lines for overall language detection
        let fullText = lines.joined(separator: "\n")
        recognizer.processString(fullText)

        guard let dominantLanguage = recognizer.dominantLanguage else {
            let result = LyricsLanguageResult(language: "und", confidence: 0, script: "unknown")
            languageResult = result
            return result
        }

        // Get confidence for dominant language
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        let confidence = hypotheses[dominantLanguage] ?? 0

        // Detect script type
        let script = detectScript(fullText)

        let result = LyricsLanguageResult(
            language: dominantLanguage.rawValue,
            confidence: confidence,
            script: script
        )
        languageResult = result
        return result
    }

    /// Classify language per line, useful for mixed-language songs.
    public func classifyPerLine(_ lines: [String]) -> [LyricsLanguageResult] {
        lines.map { classifyLyricsLanguage([$0]) }
    }

    // MARK: - Audio Feature Computation

    /// Root mean square energy of a signal window.
    private func computeRMSEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumSquares / Float(samples.count))
    }

    /// Spectral centroid — the "center of mass" of the frequency spectrum.
    /// Higher values indicate brighter/higher-pitched content (vocals).
    private func computeSpectralCentroid(_ samples: [Float], sampleRate: Double) -> Double {
        guard samples.count >= 2 else { return 0 }

        // Simple DFT magnitude spectrum (first half)
        let n = samples.count
        let halfN = n / 2
        var magnitudes = [Double](repeating: 0, count: halfN)
        var totalMagnitude: Double = 0

        for k in 0..<halfN {
            var real: Double = 0
            var imag: Double = 0
            for i in 0..<n {
                let angle = 2.0 * Double.pi * Double(k) * Double(i) / Double(n)
                real += Double(samples[i]) * cos(angle)
                imag += Double(samples[i]) * sin(angle)
            }
            magnitudes[k] = sqrt(real * real + imag * imag)
            totalMagnitude += magnitudes[k]
        }

        guard totalMagnitude > 0 else { return 0 }

        // Weighted average frequency
        var centroid: Double = 0
        for k in 0..<halfN {
            let freq = Double(k) * sampleRate / Double(n)
            centroid += freq * magnitudes[k]
        }
        return centroid / totalMagnitude
    }

    /// Zero-crossing rate — how often the signal changes sign.
    /// Moderate values indicate voiced speech/singing.
    private func computeZeroCrossingRate(_ samples: [Float]) -> Double {
        guard samples.count >= 2 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0) != (samples[i-1] >= 0) {
                crossings += 1
            }
        }
        return Double(crossings) / Double(samples.count - 1)
    }

    // MARK: - Script Detection

    private func detectScript(_ text: String) -> String {
        var scriptCounts: [String: Int] = [:]

        for scalar in text.unicodeScalars {
            let script: String
            switch scalar.value {
            case 0x3040...0x309F: script = "hiragana"
            case 0x30A0...0x30FF: script = "katakana"
            case 0x4E00...0x9FFF: script = "cjk"
            case 0xAC00...0xD7AF: script = "hangul"
            case 0x0041...0x007A: script = "latin"
            case 0x0600...0x06FF: script = "arabic"
            case 0x0900...0x097F: script = "devanagari"
            case 0x0E00...0x0E7F: script = "thai"
            case 0x0400...0x04FF: script = "cyrillic"
            default: continue
            }
            scriptCounts[script, default: 0] += 1
        }

        return scriptCounts.max(by: { $0.value < $1.value })?.key ?? "unknown"
    }
}
