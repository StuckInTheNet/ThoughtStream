import SwiftUI

struct ContentView: View {
    @EnvironmentObject var speechManager: SpeechRecognitionManager
    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 16)
                    .padding(.horizontal, 24)

                // Transcript area
                transcriptArea
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                Spacer()

                // Error message
                if let error = speechManager.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                // Record button
                recordButton
                    .padding(.bottom, 60)
            }
        }
        .onShake {
            if speechManager.isRecording {
                speechManager.stop()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("ThoughtStream")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                if speechManager.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .modifier(PulseModifier())

                        Text(speechManager.formatDuration(speechManager.elapsedSeconds))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.gray)
                    }

                    Text("Shake or tap stop to end")
                        .font(.caption2)
                        .foregroundColor(.gray.opacity(0.6))
                } else {
                    Text("Tap to start streaming")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
        }
    }

    // MARK: - Transcript

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(speechManager.liveTranscript.isEmpty
                     ? (speechManager.isRecording ? "Listening..." : "Your thoughts will appear here")
                     : speechManager.liveTranscript)
                    .font(.body)
                    .foregroundColor(speechManager.liveTranscript.isEmpty ? .gray : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 20)
                    .id("bottom")
            }
            .onChange(of: speechManager.liveTranscript) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            if speechManager.isRecording {
                speechManager.stop()
            } else {
                Task { await speechManager.start() }
            }
        } label: {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                    .frame(width: 80, height: 80)

                if speechManager.isRecording {
                    // Stop: rounded square
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 32, height: 32)
                } else {
                    // Record: filled circle
                    Circle()
                        .fill(Color.red)
                        .frame(width: 64, height: 64)
                }
            }
        }
        .accessibilityLabel(speechManager.isRecording ? "Stop recording" : "Start recording")
    }

}

// MARK: - Pulse Animation

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

#Preview {
    ContentView()
        .environmentObject(SpeechRecognitionManager())
}
