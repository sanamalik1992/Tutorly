# Tutorly — iOS

Native SwiftUI AI tutor with live whiteboard. Students speak, the tutor explains or quizzes them, and sketches out solutions on a PencilKit-powered whiteboard as it talks.

## Features

- 🎙 **Native voice recognition** via `SFSpeechRecognizer` — fast and accurate
- 🔊 **Natural text-to-speech** via Apple's premium/enhanced voices
- ✏️ **PencilKit whiteboard** — pressure-sensitive drawing, full Apple Pencil support, palm rejection
- 🎨 **Animated AI drawing overlay** — the tutor's diagrams draw themselves on as it speaks
- 🧠 **Teach mode + Quiz mode** — switch on the fly
- 🙌 **Hands-free toggle** — mic auto-restarts after each tutor reply for a real conversation
- 🔒 **API key stored in iOS Keychain** — never leaves your device except to call Anthropic
- ✨ **Animated brand-gradient border** that only appears when the tutor is thinking

## Requirements

- **Xcode 15+** (tested on Xcode 15 / iOS 17)
- **iOS 17.0+** target (iPhone or iPad)
- **Apple Developer account** (free tier is fine — you'll sign with your personal team)
- An **Anthropic API key** — <https://console.anthropic.com>

## Open & run

1. Open `Tutorly.xcodeproj` in Xcode
2. Select the **Tutorly** target → **Signing & Capabilities** → pick your Team (your Apple ID)
3. (Optional) change the Bundle Identifier from `com.tutorly.app` to something unique like `com.yourname.tutorly` so Xcode lets you sign
4. Plug in your iPhone (or use an iPad simulator that supports mic)
5. ▶️ Run

**On first launch:**
- You'll be prompted for microphone and speech recognition permissions — accept both
- Tap the **gear icon** in the top-right → paste your Anthropic API key → Save
- Tap a subject chip (e.g. "Algebra") or hit the mic and start talking

> **Note on simulators:** the iOS simulator's microphone works but speech recognition and audio routing are less reliable there. For the real experience, run on a physical device.

## How it works

```
                  ┌──────────────────────┐
                  │   SwiftUI interface  │
                  │   (ContentView)      │
                  └──────────┬───────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
 ┌──────▼──────┐     ┌───────▼───────┐    ┌──────▼──────┐
 │  SFSpeech   │     │  TutorSession │    │ AVSpeech    │
 │  Recognizer │────▶│  (state hub)  │───▶│ Synthesizer │
 └─────────────┘     └───────┬───────┘    └─────────────┘
                             │
                     ┌───────▼────────┐
                     │ AnthropicClient│
                     │  (x-api-key)   │
                     └───────┬────────┘
                             │
                     ┌───────▼────────┐
                     │  Anthropic API │
                     │  Claude Sonnet │
                     └───────┬────────┘
                             │
                  ┌──────────▼───────────┐
                  │  Whiteboard          │
                  │  • PencilKit (user)  │
                  │  • Canvas overlay    │
                  │    (AI draw cmds)    │
                  └──────────────────────┘
```

The AI model is instructed to emit a `<draw>...</draw>` JSON block alongside its spoken reply. The app decodes it into typed `DrawCommand` cases (text, line, arrow, circle, rect, path) and animates them onto a `Canvas` layered above the user's `PKCanvasView` — so the student can freely annotate the tutor's work.

## Project structure

```
Tutorly/
├── TutorlyApp.swift           # App entry
├── ContentView.swift          # Main screen
├── Theme.swift                # Brand palette & fonts
├── TutorSession.swift         # @Observable state + orchestration
├── Models/
│   └── Models.swift           # ChatMessage, DrawCommand enum, etc.
├── Services/
│   ├── SpeechRecognizer.swift # SFSpeechRecognizer + AVAudioEngine
│   ├── SpeechSynthesizer.swift# AVSpeechSynthesizer
│   ├── AnthropicClient.swift  # URLSession → api.anthropic.com
│   └── Keychain.swift         # Secure key storage
├── Views/
│   └── Whiteboard.swift       # PencilKit + animated AI overlay
├── Assets.xcassets/           # App icon + accent color
├── Info.plist                 # Permission strings
└── Preview Content/
```

## Customising

- **Tutor personality** — edit `systemPrompt` in `AnthropicClient.swift`
- **Model** — change `model = "claude-sonnet-4-5"` to something else
- **Brand colors** — all in `Theme.swift`
- **Drawing palette** — `Theme.drawColors`
- **Max context turns** — `maxHistory` in `TutorSession.swift` (default 20)

## Things to try

- "Teach me how to solve quadratic equations"
- "Quiz me on the French Revolution"
- "Draw a diagram of the water cycle"
- "Show me long division with 452 divided by 8"
- "I don't understand derivatives — explain"

## License

MIT. Built with SwiftUI, PencilKit, the Speech framework, and Claude.
