import SwiftUI
import Combine

/// Listens for Siri intent notifications and controls the speech manager.
/// Attach this as a modifier to the root view.
struct SiriObserverModifier: ViewModifier {
    @EnvironmentObject var speechManager: SpeechRecognitionManager

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .startRecordingFromSiri)) { _ in
                if !speechManager.isRecording {
                    Task { await speechManager.start() }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stopRecordingFromSiri)) { _ in
                if speechManager.isRecording {
                    speechManager.stop()
                }
            }
    }
}

extension View {
    func observeSiriIntents() -> some View {
        modifier(SiriObserverModifier())
    }
}
