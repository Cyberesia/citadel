@preconcurrency import AVFoundation
import Foundation

/// Microphone capture for dictation — adapted from Murmura `MicrophoneRecorder`.
final class CitadelMicrophoneRecorder: ObservableObject, @unchecked Sendable {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private let forwardQueue = DispatchQueue(label: "com.citadel.dictation.audio.forward")
    private var recordingActive = false

    @Published private(set) var isRecording = false

    var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func ensureMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                switch status {
                case .authorized:
                    continuation.resume(returning: true)
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        DispatchQueue.main.async {
                            continuation.resume(returning: granted)
                        }
                    }
                default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                do {
                    try self.startOnMainQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func startOnMainQueue() throws {
        precondition(Thread.isMainThread, "AVAudioEngine must be started from the main queue")
        guard !recordingActive else { return }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        audioEngine = engine
        inputNode = input

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw CitadelMicrophoneRecorderError.formatError
        }

        recordingActive = true
        let bufferSize: AVAudioFrameCount = 4096
        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] inputBuffer, _ in
            guard let self, self.recordingActive else { return }
            guard let pcmCopy = inputBuffer.copy() as? AVAudioPCMBuffer else { return }
            self.forwardQueue.async { [weak self] in
                self?.onAudioBuffer?(pcmCopy)
            }
        }

        try engine.start()
        isRecording = true
    }

    func stop() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
            }
            return
        }
        guard recordingActive else { return }

        recordingActive = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isRecording = false
    }
}

enum CitadelMicrophoneRecorderError: LocalizedError {
    case formatError

    var errorDescription: String? {
        CitadelLocale.current == .french
            ? "Impossible de démarrer le microphone."
            : "Could not start the microphone."
    }
}
