import SwiftUI

@main
struct ThoughtStreamApp: App {
    @StateObject private var speechManager = SpeechRecognitionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(speechManager)
                .observeSiriIntents()
        }
    }
}
