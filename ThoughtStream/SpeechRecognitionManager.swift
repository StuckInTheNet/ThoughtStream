import Foundation
import Speech
import AVFoundation

/// Manages continuous speech recognition by chaining recognition requests.
/// Each Apple recognition request has a ~1 minute limit, so we seamlessly
/// restart when one ends to achieve unlimited duration.
@MainActor
final class SpeechRecognitionManager: ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var error: String?
    @Published var elapsedSeconds: Int = 0

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var timer: Timer?

    /// The full saved transcript across all chained requests
    private var savedTranscript = ""

    /// Text from the current (in-progress) recognition request
    private var currentSegmentText = ""

    /// Whether we should automatically restart recognition after a segment ends
    private var shouldContinue = false

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            error = "Speech recognition permission denied"
            return false
        }

        let audioStatus: Bool
        if #available(iOS 17.0, *) {
            audioStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            audioStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard audioStatus else {
            error = "Microphone permission denied"
            return false
        }

        return true
    }

    // MARK: - Start / Stop

    func start() async {
        guard !isRecording else { return }

        let permitted = await requestPermissions()
        guard permitted else { return }

        savedTranscript = ""
        currentSegmentText = ""
        liveTranscript = ""
        elapsedSeconds = 0
        error = nil
        shouldContinue = true
        isRecording = true

        // Start elapsed time timer
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }

        configureAudioSession()
        startRecognitionSegment()
    }

    func stop() {
        shouldContinue = false
        isRecording = false
        timer?.invalidate()
        timer = nil

        // Finalize current segment
        commitCurrentSegment()

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        // Save to file
        saveTranscriptToFile()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Audio session error: \(error.localizedDescription)"
        }
    }

    // MARK: - Recognition Chaining

    /// Starts a single recognition segment. When it ends (due to Apple's ~1 min limit
    /// or silence), it commits the text and starts a new segment automatically.
    private func startRecognitionSegment() {
        guard shouldContinue else { return }

        currentSegmentText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // If on-device recognition is available, prefer it (faster, no network needed)
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    self.currentSegmentText = result.bestTranscription.formattedString
                    self.liveTranscript = self.buildFullTranscript()

                    // If this result is final, the segment ended — chain a new one
                    if result.isFinal {
                        self.commitCurrentSegment()
                        self.restartRecognitionSegment()
                    }
                }

                if let error = error {
                    let nsError = error as NSError

                    // Error 216 = no speech detected, 1110 = request timeout
                    // These are normal — just restart
                    let recoverableCodes = [216, 1110]
                    if recoverableCodes.contains(nsError.code) {
                        self.commitCurrentSegment()
                        self.restartRecognitionSegment()
                    } else if self.shouldContinue {
                        self.error = error.localizedDescription
                        self.stop()
                    }
                }
            }
        }

        // Install audio tap (only if not already tapped)
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Remove existing tap if any, then install fresh
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
            } catch {
                self.error = "Audio engine failed: \(error.localizedDescription)"
            }
        }
    }

    /// Restart recognition for a new segment (chaining)
    private func restartRecognitionSegment() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        guard shouldContinue else { return }

        // Small delay to let the previous task fully clean up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.startRecognitionSegment()
        }
    }

    /// Commit the current segment's text into the saved transcript
    private func commitCurrentSegment() {
        let trimmed = currentSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if savedTranscript.isEmpty {
            savedTranscript = trimmed
        } else {
            savedTranscript += " " + trimmed
        }
        currentSegmentText = ""
    }

    /// Build the full display transcript (saved + in-progress)
    private func buildFullTranscript() -> String {
        let current = currentSegmentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if savedTranscript.isEmpty {
            return current
        } else if current.isEmpty {
            return savedTranscript
        } else {
            return savedTranscript + " " + current
        }
    }

    // MARK: - Persistence

    func saveTranscriptToFile() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let durationFormatted = formatDuration(elapsedSeconds)

        let content = """
        # Thought Stream — \(timestamp)
        Duration: \(durationFormatted)

        \(text)
        """

        // Save to Documents directory
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = docs.appendingPathComponent("ThoughtStreams")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let file = dir.appendingPathComponent("stream_\(timestamp).md")
            try? content.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
