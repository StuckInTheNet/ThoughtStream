import SwiftUI

@main
struct ThoughtStreamApp: App {
    @StateObject private var speechManager = SpeechRecognitionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechManager)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                handlePendingSiriActions()
            }
        }
    }

    /// Check for Siri-set flags when the app becomes active.
    /// By this point Siri has fully released the audio session
    /// and the app is in the foreground.
    private func handlePendingSiriActions() {
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: "siri_pending_start") {
            defaults.removeObject(forKey: "siri_pending_start")
            if !speechManager.isRecording {
                // Small delay to ensure audio session is fully available
                Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    await speechManager.start()
                }
            }
        }

        if defaults.bool(forKey: "siri_pending_stop") {
            defaults.removeObject(forKey: "siri_pending_stop")
            if speechManager.isRecording {
                speechManager.stop()
            }
        }
    }
}
