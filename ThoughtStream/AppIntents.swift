import AppIntents

// MARK: - Shortcuts Provider

/// Makes the app discoverable in Shortcuts and Siri suggestions.
/// "Hey Siri, open ThoughtStream" works natively via iOS — no custom
/// intent needed. The app auto-starts recording on launch.
struct ThoughtStreamShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartThoughtStreamIntent(),
            phrases: [
                "Start \(.applicationName)",
                "\(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Thought Stream",
            systemImageName: "waveform"
        )
    }
}

// MARK: - Start Intent (opens app — recording auto-starts)

struct StartThoughtStreamIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Thought Stream"
    static var description = IntentDescription("Open ThoughtStream and begin recording")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
