import Foundation
import Speech
import AVFoundation

/// Citadel Voice Scribe — on-device dictation with CoworkCore STT fallback.
///
/// Pattern aligned with Murmura `AppleSpeechManager`: main-thread lifecycle, on-device only when
/// `supportsOnDeviceRecognition`, buffer copies + main-queue `append(_:)`.
@MainActor
final class CitadelVoiceScribe: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var partialText = ""
    @Published private(set) var isTranscribing = false
    @Published var errorMessage: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var speechAudioConverter: AVAudioConverter?
    private var speechAudioConverterInputFormat: AVAudioFormat?
    private(set) var speechAuthorized = false
    private(set) var onDeviceSpeechSupported = false

    init() {
        refreshRecognizer()
    }

    private func refreshRecognizer() {
        let locales = CitadelLocale.current == .french
            ? [Locale(identifier: "fr-FR"), Locale(identifier: "fr-CH"), Locale(identifier: "en-US")]
            : [Locale(identifier: "en-US"), Locale(identifier: "en-GB"), Locale(identifier: "fr-FR")]
        recognizer = nil
        onDeviceSpeechSupported = false
        for locale in locales {
            guard let candidate = SFSpeechRecognizer(locale: locale) else { continue }
            candidate.queue = OperationQueue.main
            if candidate.supportsOnDeviceRecognition && candidate.isAvailable {
                recognizer = candidate
                onDeviceSpeechSupported = true
                return
            }
        }
        // Last resort: cloud-capable recognizer for backend-only fallback recording.
        if let fallback = SFSpeechRecognizer(locale: locales[0]) {
            fallback.queue = OperationQueue.main
            recognizer = fallback
        }
    }

    /// True if we can listen at all: on-device speech OR plain microphone recording (backend fallback).
    func requestAuthorization() async -> Bool {
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        speechAuthorized = speech
        refreshRecognizer()
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech || mic
    }

    func startListening() throws {
        precondition(Thread.isMainThread, "startListening must be called on the main thread")
        guard !isListening else { return }
        stopListening()
        partialText = ""
        errorMessage = nil
        speechAudioConverter = nil
        speechAudioConverterInputFormat = nil

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("citadel-scribe-\(UUID().uuidString).caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        audioFileURL = url
        audioFile = file

        let useOnDevice = speechAuthorized && onDeviceSpeechSupported
        var activeSpeechRequest: SFSpeechAudioBufferRecognitionRequest?
        if useOnDevice {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = true
            self.request = req
            activeSpeechRequest = req
            recognizer?.queue = OperationQueue.main
        }

        let fileRef = file
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard let copy = buffer.copy() as? AVAudioPCMBuffer else { return }
            try? fileRef.write(from: copy)

            guard let activeSpeechRequest else { return }
            DispatchQueue.main.async { [weak self] in
                self?.appendToSpeechRequest(activeSpeechRequest, buffer: copy)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        if useOnDevice, let activeSpeechRequest {
            task = recognizer?.recognitionTask(with: activeSpeechRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            self.partialText = text
                        }
                    }
                    if error != nil, self.partialText.isEmpty {
                        self.task?.cancel()
                        self.task = nil
                        self.request?.endAudio()
                        self.request = nil
                    }
                }
            }
        }
    }

    func stopListening() {
        precondition(Thread.isMainThread, "stopListening must be called on the main thread")
        guard isListening || audioEngine.isRunning else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        audioFile = nil
        speechAudioConverter = nil
        speechAudioConverterInputFormat = nil
        isListening = false
    }

    /// Stops listening and returns the best transcription: on-device text when available,
    /// otherwise the recording is sent to CoworkCore `api/stt`.
    func stopAndTranscribe(client: CoworkCoreClient?) async -> String {
        stopListening()
        if !partialText.isEmpty {
            cleanupRecording()
            return partialText
        }
        guard let client else {
            errorMessage = L10n.voiceBackendUnavailable
            cleanupRecording()
            return ""
        }
        guard let url = audioFileURL,
              let data = try? Data(contentsOf: url), !data.isEmpty else {
            cleanupRecording()
            return ""
        }
        isTranscribing = true
        defer {
            isTranscribing = false
            cleanupRecording()
        }
        do {
            let text = try await client.transcribeAudio(base64: data.base64EncodedString())
            if !text.isEmpty { partialText = text }
            return text
        } catch {
            errorMessage = error.localizedDescription
            return ""
        }
    }

    private func appendToSpeechRequest(
        _ request: SFSpeechAudioBufferRecognitionRequest,
        buffer: AVAudioPCMBuffer
    ) {
        guard self.request === request, isListening else { return }
        do {
            let speechBuffer = try convertForSpeechIfNeeded(buffer, targetFormat: request.nativeAudioFormat)
            request.append(speechBuffer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func convertForSpeechIfNeeded(
        _ buffer: AVAudioPCMBuffer,
        targetFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if buffer.format.sampleRate == targetFormat.sampleRate
            && buffer.format.channelCount == targetFormat.channelCount
            && buffer.format.commonFormat == targetFormat.commonFormat {
            return buffer
        }

        if speechAudioConverter == nil || speechAudioConverterInputFormat != buffer.format {
            speechAudioConverter = AVAudioConverter(from: buffer.format, to: targetFormat)
            speechAudioConverterInputFormat = buffer.format
        }

        guard let converter = speechAudioConverter else {
            throw CitadelVoiceScribeError.audioConversionFailed
        }

        let capacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
        )
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(capacity, 1)) else {
            throw CitadelVoiceScribeError.audioConversionFailed
        }

        var conversionError: NSError?
        var consumed = false
        let status = converter.convert(to: converted, error: &conversionError) { _, outStatus in
            guard !consumed else {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError { throw conversionError }
        guard status == .haveData || status == .inputRanDry, converted.frameLength > 0 else {
            throw CitadelVoiceScribeError.audioConversionFailed
        }
        return converted
    }

    private func cleanupRecording() {
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFileURL = nil
    }
}

private enum CitadelVoiceScribeError: LocalizedError {
    case audioConversionFailed

    var errorDescription: String? {
        switch self {
        case .audioConversionFailed:
            return CitadelLocale.current == .french
                ? "Impossible de convertir l'audio micro pour la dictée."
                : "Could not convert microphone audio for dictation."
        }
    }
}
