import Foundation
import Speech
import AVFoundation
import NaturalLanguage
import UIKit

/// Manages continuous speech recognition by chaining recognition requests.
/// Each Apple recognition request has a ~1 minute limit, so we seamlessly
/// restart when one ends to achieve unlimited duration.
@MainActor
final class SpeechRecognitionManager: ObservableObject {

    /// Shared instance so App Intents can directly start/stop recording.
    static let shared = SpeechRecognitionManager()

    // MARK: - Published State

    @Published var isRecording = false
    @Published var liveTranscript = ""
    @Published var error: String?
    @Published var elapsedSeconds: Int = 0
    @Published var lastSavedTopic: String?
    @Published var showShortcutSetup = false

    var isShortcutInstalled: Bool {
        get { UserDefaults.standard.bool(forKey: "shortcutInstalled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "shortcutInstalled")
            objectWillChange.send()
        }
    }

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

    /// Whether audio was interrupted (e.g. by Siri) and we need to resume
    private var wasInterrupted = false

    /// Consecutive restart failures — used for exponential backoff
    private var restartFailures = 0

    /// Incremented each time a new segment starts — used to ignore stale callbacks
    private var segmentID = 0

    // MARK: - Init

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioInterruption(notification)
            }
        }
    }

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

    // MARK: - Start / Stop / Resume

    /// Start a brand-new recording session (clears all previous transcript data)
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
        restartFailures = 0

        startTimer()
        configureAudioSession()
        startRecognitionSegment()
    }

    /// Resume an interrupted session WITHOUT clearing the transcript.
    /// Used when the app returns from background or recovers from an interruption.
    func resume() async {
        guard !isRecording else { return }
        guard !savedTranscript.isEmpty || !currentSegmentText.isEmpty else {
            // Nothing to resume — start fresh
            await start()
            return
        }

        let permitted = await requestPermissions()
        guard permitted else { return }

        error = nil
        shouldContinue = true
        isRecording = true
        restartFailures = 0

        startTimer()
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

        saveTranscriptToFile()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
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

    // MARK: - Audio Interruption (Siri, phone calls, etc.)

    private func handleAudioInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            // Siri or another app took over audio — save progress, tear down cleanly
            guard shouldContinue else { return }
            wasInterrupted = true
            commitCurrentSegment()
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            recognitionTask?.cancel()
            recognitionRequest = nil
            recognitionTask = nil

        case .ended:
            // Interruption ended — resume recording if we were mid-stream
            guard wasInterrupted, shouldContinue else { return }
            wasInterrupted = false
            configureAudioSession()
            startRecognitionSegment()

        @unknown default:
            break
        }
    }

    // MARK: - Recognition Chaining

    /// Starts a single recognition segment. When it ends (due to Apple's ~1 min limit
    /// or silence), it commits the text and starts a new segment automatically.
    private func startRecognitionSegment() {
        guard shouldContinue else { return }

        segmentID += 1
        let thisSegment = segmentID
        currentSegmentText = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        // NOTE: Do NOT set requiresOnDeviceRecognition = true.
        // There is a confirmed Apple bug where on-device recognition
        // discards all text before a speaking pause (~1.5s of silence).
        // With this set to false, iOS still prefers on-device recognition
        // when available, but the text-discard bug does not trigger.

        self.recognitionRequest = request

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                // Ignore callbacks from a previous segment
                guard thisSegment == self.segmentID else { return }

                if let result = result {
                    // Got speech — reset backoff counter
                    self.restartFailures = 0
                    self.currentSegmentText = result.bestTranscription.formattedString
                    self.liveTranscript = self.buildFullTranscript()

                    if result.isFinal {
                        self.commitCurrentSegment()
                        self.restartRecognitionSegment()
                    }
                } else if let error = error {
                    // Only handle error if there was no result (avoid double-fire)
                    self.restartFailures += 1
                    self.commitCurrentSegment()
                    if self.shouldContinue {
                        self.restartRecognitionSegment()
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

        // Exponential backoff: 0.3s, 0.6s, 1.2s, 2.4s... up to 10s
        let baseDelay = 0.3
        let delay = min(baseDelay * pow(2.0, Double(restartFailures)), 10.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard self.shouldContinue else { return }
            // Reconfigure audio session in case iOS deactivated it
            if !self.audioEngine.isRunning {
                self.configureAudioSession()
            }
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

    // MARK: - Topic Detection

    private func detectTopic(from text: String) -> String {
        // Words to ignore — common but not topical
        let stopNouns: Set<String> = [
            "thing", "things", "way", "ways", "time", "times", "people",
            "part", "lot", "kind", "stuff", "point", "something", "anything",
            "everything", "nothing", "place", "fact", "idea", "question",
            "problem", "number", "case", "word", "words", "example"
        ]

        var nounCounts: [String: Int] = [:]

        // First pass: find named entities (people, places, organizations)
        // These are weighted higher since they're almost always topical
        let nameTagger = NLTagger(tagSchemes: [.nameType])
        nameTagger.string = text
        let nameTypes: Set<NLTag> = [.personalName, .placeName, .organizationName]

        nameTagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType
        ) { tag, range in
            if let tag = tag, nameTypes.contains(tag) {
                let word = String(text[range])
                if word.count > 2 {
                    nounCounts[word, default: 0] += 3
                }
            }
            return true
        }

        // Second pass: find regular nouns via lexical class
        let lexTagger = NLTagger(tagSchemes: [.lexicalClass])
        lexTagger.string = text

        lexTagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass
        ) { tag, range in
            if let tag = tag, tag == .noun {
                let word = String(text[range])
                let lower = word.lowercased()

                // Skip short words and stop nouns
                guard lower.count > 2, !stopNouns.contains(lower) else { return true }

                nounCounts[lower, default: 0] += 1
            }
            return true
        }

        let topNouns = nounCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }

        guard !topNouns.isEmpty else { return "Thought Stream" }

        if topNouns.count == 1 {
            return topNouns[0]
        }
        // "Architecture, Services & Latency"
        return topNouns.dropLast().joined(separator: ", ") + " & " + topNouns.last!
    }

    // MARK: - Persistence

    private static let shortcutName = "Save ThoughtStream"

    private func saveTranscriptToFile() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let topic = detectTopic(from: text)
        lastSavedTopic = topic

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let durationFormatted = formatDuration(elapsedSeconds)

        let content = """
        \(topic)
        \(timestamp) · \(durationFormatted)

        \(text)
        """

        // Save to Notes via Shortcuts
        saveToNotes(content)

        // Also save to Documents as backup
        let safeTopic = topic
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
            .prefix(50)

        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = docs.appendingPathComponent("ThoughtStreams")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let filename = "\(safeTopic)_\(timestamp).md"
            let file = dir.appendingPathComponent(filename)
            try? content.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    private func saveToNotes(_ content: String) {
        // Copy transcript to clipboard for the Shortcut to read
        UIPasteboard.general.string = content

        // Invoke the "Save ThoughtStream" shortcut, which creates a note
        // and returns to the app via x-callback-url
        let name = Self.shortcutName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let urlString = "shortcuts://x-callback-url/run-shortcut?name=\(name)&input=clipboard&x-success=thoughtstream://"

        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Shortcut Setup

    func openShortcutsApp() {
        if let url = URL(string: "shortcuts://create-shortcut") {
            UIApplication.shared.open(url)
        }
    }

    func markShortcutInstalled() {
        isShortcutInstalled = true
        showShortcutSetup = false
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
