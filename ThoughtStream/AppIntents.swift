import AppIntents
import SwiftUI

// MARK: - Start Thought Stream

/// Siri trigger: "Hey Siri, thought stream" or "Hey Siri, start thought stream"
struct StartThoughtStreamIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Thought Stream"
    static var description = IntentDescription("Begin continuous speech-to-text capture")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = SpeechRecognitionManager.shared
        if !manager.isRecording {
            await manager.start()
        }
        return .result()
    }
}

// MARK: - Stop Thought Stream

/// Siri trigger: "Hey Siri, stop thought stream"
struct StopThoughtStreamIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Thought Stream"
    static var description = IntentDescription("Stop the current thought stream recording")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let manager = SpeechRecognitionManager.shared
        if manager.isRecording {
            manager.stop()
        }
        return .result()
    }
}

// MARK: - Shortcuts Provider

/// Makes the intents discoverable in the Shortcuts app and Siri suggestions
struct ThoughtStreamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartThoughtStreamIntent(),
            phrases: [
                "Start \(.applicationName)",
                "\(.applicationName)",
                "Stream with \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Thought Stream",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: StopThoughtStreamIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "End \(.applicationName)",
                "Finish \(.applicationName)"
            ],
            shortTitle: "Stop Stream",
            systemImageName: "stop.circle"
        )
    }
}

