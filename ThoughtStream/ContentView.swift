import SwiftUI
import UIKit

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

                // Setup banner (one-time)
                if !speechManager.isShortcutInstalled {
                    setupBanner
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                }

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
        .overlay(alignment: .top) {
            if let topic = speechManager.lastSavedTopic {
                SavedBanner(topic: topic)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { speechManager.lastSavedTopic = nil }
                        }
                    }
                    .padding(.top, 60)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: speechManager.lastSavedTopic != nil)
        .sheet(isPresented: $speechManager.showShortcutSetup) {
            ShortcutSetupView()
                .environmentObject(speechManager)
        }
    }

    // MARK: - Setup Banner

    private var setupBanner: some View {
        Button {
            speechManager.showShortcutSetup = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.title3)
                    .foregroundColor(.yellow)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Enable Notes Saving")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("One-time setup — takes 30 seconds")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
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

// MARK: - Shortcut Setup View

struct ShortcutSetupView: View {
    @EnvironmentObject var speechManager: SpeechRecognitionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // Hero
                        VStack(spacing: 8) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.system(size: 48))
                                .foregroundColor(.yellow)
                            Text("Save to Notes")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Create a simple Shortcut so ThoughtStream can save directly to Apple Notes.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                        // Steps
                        VStack(alignment: .leading, spacing: 20) {
                            stepRow(number: 1,
                                    title: "Tap \"Open Shortcuts\" below",
                                    detail: "This opens the Shortcuts app to create a new shortcut.")

                            stepRow(number: 2,
                                    title: "Add \"Get Clipboard\"",
                                    detail: "Search for \"Clipboard\" and add the Get Clipboard action.")

                            stepRow(number: 3,
                                    title: "Add \"Create Note\"",
                                    detail: "Search for \"Create Note\" and add it below. It will automatically use the clipboard text.")

                            stepRow(number: 4,
                                    title: "Rename to \"Save ThoughtStream\"",
                                    detail: "Tap the name at the top and type exactly: Save ThoughtStream")
                        }
                        .padding(.horizontal, 4)

                        // Open Shortcuts button
                        Button {
                            speechManager.openShortcutsApp()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.up.forward.app")
                                Text("Open Shortcuts")
                            }
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 12))
                        }

                        // Done button
                        Button {
                            speechManager.markShortcutInstalled()
                            dismiss()
                        } label: {
                            Text("I've created the shortcut")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
    }

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 24, height: 24)
                .background(Color.yellow, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
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

// MARK: - Saved Banner

struct SavedBanner: View {
    let topic: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Saved: \(topic)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

#Preview {
    ContentView()
        .environmentObject(SpeechRecognitionManager.shared)
}
