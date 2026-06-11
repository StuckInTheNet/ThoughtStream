<p align="center">
  <img src="assets/logo.svg" alt="ThoughtStream" width="280"/>
</p>
<p align="center">
  <em>Hands-free, continuous speech-to-text for iOS.</em><br/>
  <sub>Start with Siri, talk as long as you want, get a clean transcript saved automatically.</sub>
</p>
<p align="center">
  <a href="#requirements"><img src="https://img.shields.io/badge/platform-iOS%2017%2B-blue?style=flat-square" alt="iOS 17+"/></a>
  <a href="#setup"><img src="https://img.shields.io/badge/swift-5.9-orange?style=flat-square" alt="Swift 5.9"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/StuckInTheNet/ThoughtStream?style=flat-square" alt="MIT License"/></a>
</p>

## Why This Exists
Apple's built-in dictation times out after ~30 seconds of silence. Voice Memos records but doesn't transcribe. ThoughtStream bridges the gap — it listens continuously with no time limit, transcribes in real time, and saves everything as a clean Markdown file when you're done.
**Say "Hey Siri, thought stream" and start talking. That's it.**

## Features
- **Siri Launch** — "Hey Siri, thought stream" opens the app and starts recording immediately
- **Unlimited Duration** — Seamlessly chains recognition requests so you can talk for seconds, minutes, or hours
- **Live Transcript** — See your words appear in real time as you speak
- **On-Device Processing** — Uses Apple's on-device speech recognition when available (no data leaves your phone)
- **Topic Detection** — Automatically detects what you were talking about and titles the note
- **Save to Notes** — Transcripts saved directly to Apple Notes via Shortcuts integration
- **Background Audio** — Keeps listening even when the screen locks
- **Shake to Stop** — Shake your phone to end a stream, or tap the stop button
- **Minimal UI** — Dark interface with a single large button, designed for glanceable use while moving

## How It Works

### Starting a Stream
**Option 1: Siri (hands-free)**
> "Hey Siri, thought stream"

The app opens and immediately begins listening. No taps needed.

**Option 2: Manual**
Open the app and tap the red record button.

### During a Stream
Just talk. The transcript scrolls in real time on screen. A pulsing red dot and elapsed timer show that recording is active.
You'll see silence gaps handled gracefully — the app doesn't stop when you pause to think. It keeps listening.

### Stopping a Stream
Two options:
- **Shake your phone** — hands-free, works while running
- **Tap the stop button** (the red square) on screen

Your transcript is automatically saved to **Apple Notes** with a detected topic title. A backup is also saved to `Documents/ThoughtStreams/` in the Files app.

Each note looks like:
```
Architecture, Services & Latency
2026-06-09_14-30-00 · 12:34

I was thinking about the architecture for the new feature and I think
we should probably go with a pub-sub model instead of direct calls
because the latency requirements aren't that strict and it would
decouple the services nicely...
```

### One-Time Setup
ThoughtStream saves to Notes via a simple Shortcut. On first launch, the app guides you through a 30-second setup:
1. Open the Shortcuts app
2. Add **Get Clipboard** action
3. Add **Create Note** action
4. Name it **Save ThoughtStream**

After that, every recording is saved to Notes automatically.

## Technical Details

### Recognition Chaining
Apple's `SFSpeechRecognitionTask` has a soft limit of ~60 seconds per request. ThoughtStream works around this by **chaining requests** — when one recognition segment ends (indicated by `isFinal` results or recoverable error codes like 216/1110), the manager commits that segment's text and immediately starts a new request. The ~0.3 second gap between segments is imperceptible during normal speech.

### Architecture
```
ThoughtStreamApp.swift          App entry point
ContentView.swift               Minimal dark UI — transcript + record button + setup flow
SpeechRecognitionManager.swift  Core engine — audio capture, chaining, topic detection, Notes saving
AppIntents.swift                Siri phrases and Shortcuts integration
ShakeDetector.swift             Shake-to-stop via UIWindow motion events
```

### Key Implementation Choices
- **On-device recognition preferred** — Faster response, works without network, private. Falls back to server-based recognition when on-device isn't available.
- **`AVAudioSession.Category.record`** — Enables background audio so the app keeps listening with the screen locked.
- **Audio interruption recovery** — Handles Siri/phone call interruptions gracefully, resuming recording when the mic is available again.
- **NLP topic detection** — Uses `NLTagger` with named entity recognition and lexical classification to extract the dominant topic from the transcript.
- **Notes via Shortcuts** — Copies transcript to clipboard and invokes a user-created Shortcut to save to Apple Notes, with `x-callback-url` to return to the app.

## Requirements
- iOS 17.0+
- Xcode 16.0+
- iPhone with microphone (Speech recognition requires a physical device — the Simulator doesn't support mic input)

## Setup

### 1. Clone the repo
```bash
git clone https://github.com/StuckInTheNet/ThoughtStream.git
cd ThoughtStream
```

### 2. Generate the Xcode project
The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj` from `project.yml`.
```bash
brew install xcodegen
xcodegen generate
```
Or open the included `.xcodeproj` directly if you prefer.

### 3. Open in Xcode
```bash
open ThoughtStream.xcodeproj
```

### 4. Configure signing
1. Select the **ThoughtStream** target
2. Go to **Signing & Capabilities**
3. Select your **Team** (Apple Developer account)
4. Xcode will auto-manage provisioning

### 5. Build and run
Select your physical iPhone as the destination and hit **Cmd + R**.
> The Siri phrases register automatically when the app is first installed. After installation, "Hey Siri, thought stream" will work system-wide.

## Siri Phrases
These phrases are registered automatically:

| Phrase | Action |
|--------|--------|
| "Hey Siri, ThoughtStream" | Opens app and starts recording |
| "Hey Siri, start ThoughtStream" | Opens app and starts recording |
| "Hey Siri, stream with ThoughtStream" | Opens app and starts recording |
| "Hey Siri, open ThoughtStream" | Opens app and starts recording |
| "Hey Siri, stop ThoughtStream" | Stops recording and saves |
| "Hey Siri, end ThoughtStream" | Stops recording and saves |

You can also find and customize these in the **Shortcuts** app.

## File Storage
Transcripts are saved to **Apple Notes** (via Shortcuts) and backed up to:
```
[App Documents]/ThoughtStreams/[topic]_[timestamp].md
```
Backup files are accessible via the **Files** app on iOS under ThoughtStream's documents.

## License
MIT — see [LICENSE](LICENSE) for details.
