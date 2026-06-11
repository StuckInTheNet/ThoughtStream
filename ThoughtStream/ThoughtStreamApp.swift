import SwiftUI

@main
struct ThoughtStreamApp: App {
    @StateObject private var speechManager = SpeechRecognitionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechManager)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && !speechManager.isRecording {
                        Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            await speechManager.resume()
                        }
                    }
                }
        }
    }
}
