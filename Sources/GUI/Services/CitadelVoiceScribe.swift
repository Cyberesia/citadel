import Foundation
import Speech
import AVFoundation

/// Citadel Voice Scribe — on-device dictation with CoworkCore STT fallback.
///
/// While listening, audio is simultaneously streamed to the on-device recognizer (when
/// authorized/available) and written to a temp file. If on-device recognition yields
/// nothing, `stopAndTranscribe` sends the recording to CoworkCore's `api/stt`.
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
    private(set) var speechAuthorized = false

    init() {
        let localeID = CitadelLocale.current == .french ? "fr-FR" : "en-US"
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
    }

    /// True if we can listen at all: on-device speech OR plain microphone recording (backend fallback).
    func requestAuthorization() async -> Bool {
        let speech: Bool = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        speechAuthorized = speech
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        return speech || mic
    }

    func startListening() throws {
        stopListening()
        partialText = ""
        errorMessage = nil

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Record to disk so the backend can transcribe if on-device recognition fails.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("citadel-scribe-\(UUID().uuidString).caf")
        let file = try? AVAudioFile(forWriting: url, settings: format.settings)
        audioFileURL = url
        audioFile = file

        let useOnDevice = speechAuthorized && recognizer?.isAvailable == true
        var speechRequest: SFSpeechAudioBufferRecognitionRequest?
        if useOnDevice {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            self.request = req
            speechRequest = req
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            speechRequest?.append(buffer)
            try? file?.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        if useOnDevice, let speechRequest {
            task = recognizer?.recognitionTask(with: speechRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.partialText = result.bestTranscription.formattedString
                        if result.isFinal {
                            self.stopListening()
                        }
                    }
                    if error != nil, self.partialText.isEmpty {
                        // Keep recording — the backend fallback can still transcribe on stop.
                        self.task = nil
                        self.request = nil
                    }
                }
            }
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        audioFile = nil
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
        guard let client, let url = audioFileURL,
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

    private func cleanupRecording() {
        if let url = audioFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        audioFileURL = nil
    }

    func transcribeViaBackend(client: CoworkCoreClient, audioData: Data) async throws -> String {
        try await client.transcribeAudio(base64: audioData.base64EncodedString())
    }
}
