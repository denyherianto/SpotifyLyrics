import Foundation
@preconcurrency import SoundAnalysis
@preconcurrency import AVFoundation

/// Classifies audio using Apple's SoundAnalysis framework to detect music characteristics.
/// Exposes music mood/genre results for dynamic overlay theming.
///
/// Uses the built-in SNClassifySoundRequest to identify sounds like music, singing, etc.
/// On macOS 15+, can also detect musical genre for richer theming.
@MainActor
public final class SoundClassifier: ObservableObject {

    /// High-level mood derived from sound classification results.
    public enum MusicMood: String, CaseIterable {
        case energetic    // Fast, upbeat, loud
        case calm         // Slow, quiet, ambient
        case vocal        // Singing-dominant
        case instrumental // No vocals detected
        case unknown

        public var themeHue: Double {
            switch self {
            case .energetic:    return 0.05   // Warm orange-red
            case .calm:         return 0.6    // Cool blue
            case .vocal:        return 0.8    // Purple
            case .instrumental: return 0.45   // Teal
            case .unknown:      return 0.0    // Neutral
            }
        }

        public var animationSpeed: Double {
            switch self {
            case .energetic:    return 1.5
            case .calm:         return 0.6
            case .vocal:        return 1.0
            case .instrumental: return 0.8
            case .unknown:      return 1.0
            }
        }
    }

    @Published public private(set) var currentMood: MusicMood = .unknown
    @Published public private(set) var confidence: Double = 0.0
    @Published public private(set) var isSinging: Bool = false
    @Published public private(set) var detectedSounds: [String: Double] = [:]

    private var analyzer: SNAudioStreamAnalyzer?
    private var analysisQueue = DispatchQueue(label: "com.spotifylyrics.soundanalysis", qos: .userInitiated)
    private var observer: ClassificationObserver?
    private var format: AVAudioFormat?

    public init() {}

    // MARK: - Analysis Control

    /// Start analyzing audio from a continuous stream of Float32 samples.
    /// Call `appendSamples(_:)` to feed audio data.
    public func startAnalysis() {
        let audioFormat = AVAudioFormat(
            standardFormatWithSampleRate: 16000,
            channels: 1
        )!
        self.format = audioFormat

        let analyzer = SNAudioStreamAnalyzer(format: audioFormat)
        self.analyzer = analyzer

        let observer = ClassificationObserver { [weak self] results in
            Task { @MainActor [weak self] in
                self?.processResults(results)
            }
        }
        self.observer = observer

        do {
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 3.0, preferredTimescale: 1000)
            request.overlapFactor = 0.5
            try analyzer.add(request, withObserver: observer)
        } catch {
            // Classifier not available on this system
        }
    }

    /// Feed audio samples into the analyzer.
    /// Samples should be 16kHz mono Float32 (same format as AudioCaptureService).
    public func appendSamples(_ samples: [Float]) {
        guard let analyzer, let format else { return }

        let frameCount = AVAudioFrameCount(samples.count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channelData[0].update(from: src.baseAddress!, count: samples.count)
            }
        }

        let time = AVAudioTime(sampleTime: 0, atRate: format.sampleRate)
        analysisQueue.async {
            analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
    }

    /// Stop analysis and reset state.
    public func stopAnalysis() {
        if let analyzer {
            analyzer.removeAllRequests()
        }
        analyzer = nil
        observer = nil
        format = nil
        currentMood = .unknown
        confidence = 0.0
        isSinging = false
        detectedSounds.removeAll()
    }

    // MARK: - Result Processing

    private func processResults(_ results: [String: Double]) {
        detectedSounds = results

        // Determine if singing is happening
        let singingScore = results["singing"] ?? 0
        let musicScore = results["music"] ?? 0
        let speechScore = results["speech"] ?? 0

        isSinging = singingScore > 0.3 || (speechScore > 0.3 && musicScore > 0.3)

        // Determine mood from sound classifications
        let newMood: MusicMood
        let newConfidence: Double

        if singingScore > 0.5 {
            newMood = .vocal
            newConfidence = singingScore
        } else if musicScore > 0.5 && singingScore < 0.1 && speechScore < 0.1 {
            newMood = .instrumental
            newConfidence = musicScore
        } else if musicScore > 0.3 {
            // Use energy-related classifications to differentiate energetic vs calm
            let drumScore = results["drum"] ?? 0
            let guitarScore = results["guitar"] ?? 0
            let pianoScore = results["piano"] ?? 0

            if drumScore > 0.2 || guitarScore > 0.3 {
                newMood = .energetic
                newConfidence = max(drumScore, guitarScore)
            } else if pianoScore > 0.2 {
                newMood = .calm
                newConfidence = pianoScore
            } else {
                newMood = .unknown
                newConfidence = musicScore
            }
        } else {
            newMood = .unknown
            newConfidence = 0.0
        }

        if newConfidence > 0.2 {
            currentMood = newMood
            confidence = newConfidence
        }
    }
}

// MARK: - Classification Observer

private final class ClassificationObserver: NSObject, SNResultsObserving {
    let onResults: ([String: Double]) -> Void

    init(onResults: @escaping ([String: Double]) -> Void) {
        self.onResults = onResults
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }

        var results: [String: Double] = [:]
        for item in classification.classifications {
            results[item.identifier] = item.confidence
        }
        onResults(results)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        // Classification failed — not critical
    }

    func requestDidComplete(_ request: SNRequest) {
        // Analysis complete
    }
}
