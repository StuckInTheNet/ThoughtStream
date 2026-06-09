import SwiftUI

@main
struct ThoughtStreamApp: App {
    @StateObject private var speechManager = SpeechRecognitionManager.shared
    @AppStorage("siri_pending_start") private var pendingStart = false
    @AppStorage("siri_pending_stop") private var pendingStop = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechManager)
        }
        .onChange(of: pendingStart) { _, shouldStart in
            if shouldStart {
                pendingStart = false
                Task {
                    // Wait for Siri to fully release the audio session
                    try? await Task.sleep(for: .seconds(1))
                    await speechManager.start()
                }
            }
        }
        .onChange(of: pendingStop) { _, shouldStop in
            if shouldStop {
                pendingStop = false
                speechManager.stop()
            }
        }
    }
}
