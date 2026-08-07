import Foundation
import AVFoundation
import Combine

/// Apple on-device dictation for Keep — same architecture as Murmura Assistant (Apple Speech + mic recorder).
@MainActor
final class CitadelVoiceScribe: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var partialText = ""
    @Published var errorMessage: String?

    private let appleSpeech = CitadelAppleSpeechEngine()
    private let recorder = CitadelMicrophoneRecorder()
    private var speechSink: CitadelAppleSpeechSink?
    private var cancellables = Set<AnyCancellable>()

    private var candidateLocales: [Locale] {
        CitadelLocale.current == .french
            ? [Locale(identifier: "fr-FR"), Locale(identifier: "fr-CH"), Locale(identifier: "en-US")]
            : [Locale(identifier: "en-US"), Locale(identifier: "en-GB"), Locale(identifier: "fr-FR")]
    }

    init() {
        appleSpeech.syncAuthorizationFromSystem()
        appleSpeech.$transcription
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self, self.isListening else { return }
                self.partialText = text
            }
            .store(in: &cancellables)
    }

    /// Flip the mic to red before permission / AVAudio setup (Murmura-feel).
    func armListeningUI() {
        errorMessage = nil
        partialText = ""
        isListening = true
        // Accessory apps lose their window when TCC / audio session steals activation.
        CitadelMainWindowPresenter.promoteForDictation()
    }

    func requestAuthorization() async -> Bool {
        errorMessage = nil
        appleSpeech.syncAuthorizationFromSystem()

        // Fast path — already granted; never touch window focus (that was closing the main window).
        if appleSpeech.isAuthorized,
           AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            appleSpeech.checkAvailability(locales: candidateLocales)
            if appleSpeech.isSupported { return true }
        }

        CitadelMainWindowPresenter.promoteForDictation()
        let speech = await appleSpeech.requestPermissions()
        let mic = await recorder.ensureMicrophonePermission()
        CitadelMainWindowPresenter.promoteForDictation()

        guard speech else {
            errorMessage = CitadelAppleSpeechError.notAuthorized.errorDescription
            return false
        }
        guard mic else {
            errorMessage = L10n.voicePermissionDenied
            return false
        }
        guard appleSpeech.isSupported else {
            errorMessage = CitadelAppleSpeechError.onDeviceNotSupported.errorDescription
            return false
        }
        return true
    }

    func startListening() async throws {
        if !isListening {
            isListening = true
        }
        errorMessage = nil
        partialText = ""
        CitadelMainWindowPresenter.promoteForDictation()

        do {
            appleSpeech.reset()
            appleSpeech.checkAvailability(locales: candidateLocales)
            try appleSpeech.startStreaming()

            let sink = CitadelAppleSpeechSink(engine: appleSpeech)
            speechSink = sink
            recorder.onAudioBuffer = { buffer in
                sink.append(buffer)
            }

            try await recorder.start()
            CitadelMainWindowPresenter.promoteForDictation()
        } catch {
            appleSpeech.stopStreaming()
            recorder.onAudioBuffer = nil
            speechSink = nil
            isListening = false
            throw error
        }
    }

    func stopListening() {
        guard isListening || recorder.isRecording else { return }
        recorder.stop()
        appleSpeech.stopStreaming()
        recorder.onAudioBuffer = nil
        speechSink = nil
        isListening = false
        partialText = appleSpeech.currentTranscriptSnapshot()
    }

    /// Stops listening and returns the on-device Apple transcript (no backend STT).
    func stopAndGetTranscript() -> String {
        stopListening()
        let text = appleSpeech.currentTranscriptSnapshot()
        partialText = text
        if text.isEmpty {
            errorMessage = errorMessage ?? L10n.voiceTranscriptionEmpty
        }
        return text
    }
}

/// Bridges mic forward queue → Apple Speech main-queue append (Murmura `AppleSpeechLiveSink`).
final class CitadelAppleSpeechSink: @unchecked Sendable {
    private weak var engine: CitadelAppleSpeechEngine?

    init(engine: CitadelAppleSpeechEngine) {
        self.engine = engine
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        engine?.appendAudioSynchronously(buffer)
    }
}
