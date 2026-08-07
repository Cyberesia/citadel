@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech

/// On-device Apple Speech streaming — adapted from Murmura `AppleSpeechManager`.
final class CitadelAppleSpeechEngine: NSObject, ObservableObject, @unchecked Sendable {
    private let speechLock = NSLock()

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechAudioConverter: AVAudioConverter?
    private var speechAudioConverterInputFormat: AVAudioFormat?
    private var lastNonEmptyTranscription = ""
    /// Finalized utterance segments — Apple resets `bestTranscription` per segment (last-word bug).
    private var committedTranscript = ""

    @Published private(set) var transcription = ""
    @Published private(set) var isSupported = false
    @Published private(set) var isAuthorized = false
    @Published private(set) var activeLocaleIdentifier: String?
    @Published var lastErrorMessage: String?

    private func publishOnMain(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

    func syncAuthorizationFromSystem() {
        let authorized = SFSpeechRecognizer.authorizationStatus() == .authorized
        if Thread.isMainThread {
            isAuthorized = authorized
        } else {
            publishOnMain { self.isAuthorized = authorized }
        }
    }

    func requestPermissions() async -> Bool {
        syncAuthorizationFromSystem()
        if isAuthorized { return true }
        return await withCheckedContinuation { continuation in
            publishOnMain {
                SFSpeechRecognizer.requestAuthorization { status in
                    let authorized = status == .authorized
                    self.publishOnMain {
                        self.isAuthorized = authorized
                        continuation.resume(returning: authorized)
                    }
                }
            }
        }
    }

    func checkAvailability(locales: [Locale]) {
        let apply: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.speechLock.lock()
            defer { self.speechLock.unlock() }

            self.speechRecognizer = nil
            self.isSupported = false
            self.activeLocaleIdentifier = nil

            for locale in locales {
                guard let recognizer = SFSpeechRecognizer(locale: locale) else { continue }
                recognizer.queue = OperationQueue.main

                let onDevice = recognizer.supportsOnDeviceRecognition
                let available = recognizer.isAvailable
                guard onDevice && available else { continue }

                self.speechRecognizer = recognizer
                self.isSupported = true
                self.activeLocaleIdentifier = locale.identifier
                return
            }
        }
        if Thread.isMainThread {
            apply()
        } else {
            publishOnMain { apply() }
        }
    }

    func startStreaming() throws {
        precondition(Thread.isMainThread, "startStreaming must be called on the main thread")
        speechLock.lock()
        defer { speechLock.unlock() }

        guard isAuthorized else { throw CitadelAppleSpeechError.notAuthorized }
        guard isSupported else { throw CitadelAppleSpeechError.onDeviceNotSupported }

        recognitionTask?.cancel()
        recognitionTask = nil
        speechAudioConverter = nil
        speechAudioConverterInputFormat = nil
        lastNonEmptyTranscription = ""
        committedTranscript = ""
        transcription = ""
        lastErrorMessage = nil

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            throw CitadelAppleSpeechError.requestCreationFailed
        }

        recognitionRequest.requiresOnDeviceRecognition = true
        recognitionRequest.shouldReportPartialResults = true
        speechRecognizer?.queue = OperationQueue.main

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                self.publishOnMain {
                    if result.isFinal {
                        // Each final segment replaces Apple's buffer — accumulate ourselves.
                        if self.committedTranscript.isEmpty {
                            self.committedTranscript = text
                        } else if !self.committedTranscript.hasSuffix(text) {
                            self.committedTranscript += " " + text
                        }
                        self.transcription = self.committedTranscript
                        self.lastNonEmptyTranscription = self.committedTranscript
                    } else {
                        let combined = self.committedTranscript.isEmpty
                            ? text
                            : self.committedTranscript + " " + text
                        self.transcription = combined
                        self.lastNonEmptyTranscription = combined
                    }
                }
            }

            if let error {
                self.publishOnMain {
                    self.lastErrorMessage = error.localizedDescription
                }
            }
        }

        guard recognitionTask != nil else {
            throw CitadelAppleSpeechError.taskCreationFailed
        }
    }

    func appendAudioSynchronously(_ buffer: AVAudioPCMBuffer) {
        guard let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.speechLock.lock()
            defer { self.speechLock.unlock() }

            guard let request = self.recognitionRequest else { return }

            do {
                let speechBuffer = try self.convertForSpeechIfNeeded(copy, targetFormat: request.nativeAudioFormat)
                request.append(speechBuffer)
            } catch {
                self.lastErrorMessage = error.localizedDescription
            }
        }
    }

    func stopStreaming() {
        precondition(Thread.isMainThread, "stopStreaming must be called on the main thread")
        speechLock.lock()
        defer { speechLock.unlock() }

        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        speechAudioConverter = nil
        speechAudioConverterInputFormat = nil
    }

    func currentTranscriptSnapshot() -> String {
        let current = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty { return current }
        return lastNonEmptyTranscription
    }

    func reset() {
        precondition(Thread.isMainThread, "reset must be called on the main thread")
        speechLock.lock()
        defer { speechLock.unlock() }

        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        speechAudioConverter = nil
        speechAudioConverterInputFormat = nil
        transcription = ""
        lastNonEmptyTranscription = ""
        committedTranscript = ""
        lastErrorMessage = nil
    }

    private func convertForSpeechIfNeeded(
        _ buffer: AVAudioPCMBuffer,
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if buffer.format.isEquivalentForSpeech(to: targetFormat) {
            return buffer
        }

        if speechAudioConverter == nil || speechAudioConverterInputFormat != buffer.format {
            speechAudioConverter = AVAudioConverter(from: buffer.format, to: targetFormat)
            speechAudioConverterInputFormat = buffer.format
        }

        guard let converter = speechAudioConverter else {
            throw CitadelAppleSpeechError.audioConversionFailed
        }

        let capacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        )
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(capacity, 1)) else {
            throw CitadelAppleSpeechError.audioConversionFailed
        }

        let inputProvider = SingleBufferInputProvider(buffer: buffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            inputProvider.next(outStatus: outStatus)
        }

        if let conversionError { throw conversionError }
        guard status == .haveData || status == .inputRanDry, converted.frameLength > 0 else {
            throw CitadelAppleSpeechError.audioConversionFailed
        }
        return converted
    }
}

enum CitadelAppleSpeechError: LocalizedError {
    case notAuthorized
    case onDeviceNotSupported
    case requestCreationFailed
    case taskCreationFailed
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return CitadelLocale.current == .french
                ? "Autorisation reconnaissance vocale non accordée. Activez-la dans Réglages système → Confidentialité et sécurité → Reconnaissance vocale."
                : "Speech Recognition permission not granted. Enable it in System Settings → Privacy & Security → Speech Recognition."
        case .onDeviceNotSupported:
            return L10n.voiceOnDeviceUnsupported
        case .requestCreationFailed:
            return CitadelLocale.current == .french
                ? "Impossible de créer la requête de reconnaissance."
                : "Could not create recognition request."
        case .taskCreationFailed:
            return CitadelLocale.current == .french
                ? "Impossible de démarrer la reconnaissance Apple."
                : "Could not start Apple Speech recognition."
        case .audioConversionFailed:
            return CitadelLocale.current == .french
                ? "Impossible de convertir l'audio micro pour la dictée."
                : "Could not convert microphone audio for dictation."
        }
    }
}

private final class SingleBufferInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else {
            outStatus.pointee = .noDataNow
            return nil
        }
        consumed = true
        outStatus.pointee = .haveData
        return buffer
    }
}

private extension AVAudioFormat {
    func isEquivalentForSpeech(to other: AVAudioFormat) -> Bool {
        sampleRate == other.sampleRate
            && channelCount == other.channelCount
            && commonFormat == other.commonFormat
            && isInterleaved == other.isInterleaved
    }
}
