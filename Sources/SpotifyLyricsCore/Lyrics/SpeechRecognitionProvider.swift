import Foundation
import Speech
import AVFoundation

/// Generates lyrics from captured audio using Apple's Speech framework (SFSpeechRecognizer).
/// Used as a last-resort fallback when LRCLIB and Musixmatch have no results.
///
/// Requires:
/// - Speech Recognition permission (prompted on first use)
/// - Audio buffer from AudioCaptureService (16kHz mono Float32)
@MainActor
public final class SpeechRecognitionProvider: ObservableObject {

    public enum RecognitionState: Equatable {
        case idle
        case recognizing
        case completed
        case failed(String)
    }

    @Published public private(set) var state: RecognitionState = .idle

    private let recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?

    public init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    // MARK: - Permission

    public static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    public static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Recognition

    /// Recognize lyrics from a 16kHz mono Float32 audio buffer.
    ///
    /// - Parameters:
    ///   - audioBuffer: Raw Float32 samples at 16kHz mono
    ///   - captureStartPosition: The song playback position when capture started
    /// - Returns: Array of LyricLines with word-level timings, or nil on failure
    public func recognizeLyrics(
        from audioBuffer: [Float],
        captureStartPosition: TimeInterval
    ) async -> [LyricLine]? {
        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognizer unavailable")
            return nil
        }

        if !Self.isAuthorized {
            let granted = await Self.requestPermission()
            guard granted else {
                state = .failed("Speech recognition not authorized")
                return nil
            }
        }

        state = .recognizing

        // Write audio buffer to a temporary WAV file for SFSpeechRecognizer
        guard let tempURL = writeWAV(samples: audioBuffer, sampleRate: 16000) else {
            state = .failed("Failed to create audio file")
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        // Request word-level timestamps
        if #available(macOS 13, *) {
            request.addsPunctuation = true
        }

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognitionResult?, Never>) in
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if (error as NSError).code != 1 { // Ignore cancellation
                        continuation.resume(returning: nil)
                    }
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result)
                }
            }
        }

        recognitionTask = nil

        guard let result else {
            state = .failed("Recognition failed")
            return nil
        }

        let lines = buildLyricLines(from: result, captureStartPosition: captureStartPosition)
        state = lines.isEmpty ? .failed("No speech detected") : .completed
        return lines.isEmpty ? nil : lines
    }

    /// Cancel any in-progress recognition.
    public func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        state = .idle
    }

    // MARK: - Line Building

    /// Converts SFSpeechRecognitionResult into LyricLine array.
    /// Groups words into lines based on pauses between words (>0.8s gap = new line).
    private func buildLyricLines(
        from result: SFSpeechRecognitionResult,
        captureStartPosition: TimeInterval
    ) -> [LyricLine] {
        let bestTranscription = result.bestTranscription
        let segments = bestTranscription.segments

        guard !segments.isEmpty else { return [] }

        var lines: [LyricLine] = []
        var currentWords: [LyricWord] = []
        var lineStartTime: TimeInterval = 0
        var lastEndTime: TimeInterval = 0
        let pauseThreshold: TimeInterval = 0.8

        for (i, segment) in segments.enumerated() {
            let wordStart = captureStartPosition + segment.timestamp
            let wordEnd = captureStartPosition + segment.timestamp + segment.duration

            // Detect line breaks based on pauses
            if i > 0 && (segment.timestamp - lastEndTime) > pauseThreshold {
                // Flush current line
                if !currentWords.isEmpty {
                    let text = currentWords.map(\.text).joined(separator: " ")
                    lines.append(LyricLine(
                        timestamp: lineStartTime,
                        text: text,
                        words: currentWords,
                        endTime: currentWords.last?.end
                    ))
                    currentWords.removeAll()
                }
                lineStartTime = wordStart
            }

            if currentWords.isEmpty {
                lineStartTime = wordStart
            }

            currentWords.append(LyricWord(
                text: segment.substring,
                start: wordStart,
                end: wordEnd
            ))
            lastEndTime = segment.timestamp + segment.duration
        }

        // Flush remaining words
        if !currentWords.isEmpty {
            let text = currentWords.map(\.text).joined(separator: " ")
            lines.append(LyricLine(
                timestamp: lineStartTime,
                text: text,
                words: currentWords,
                endTime: currentWords.last?.end
            ))
        }

        return lines
    }

    // MARK: - WAV Writing

    /// Write Float32 samples to a temporary 16kHz mono WAV file.
    private func writeWAV(samples: [Float], sampleRate: Int) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("speech_recognition_\(UUID().uuidString).wav")

        let numSamples = samples.count
        let dataSize = numSamples * 2  // 16-bit PCM
        let fileSize = 36 + dataSize

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })     // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })     // mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) }) // byte rate
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })     // block align
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })    // bits per sample

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })

        // Convert Float32 [-1, 1] to Int16
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * Float(Int16.max))
            data.append(contentsOf: withUnsafeBytes(of: int16.littleEndian) { Array($0) })
        }

        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
