# OpenFlow Voice

Push-to-talk dictation for macOS. Hold a key, speak, release — polished text lands at the cursor in whatever app has focus. Runs entirely on-device with no cloud dependency required.

---

## Features

- **Push-to-talk** — hold any key to record, release to transcribe and inject text
- **Multiple engines** — Apple Speech (streaming, instant) or Parakeet (higher accuracy, Apple Silicon)
- **AI cleanup** — on-device formatting via Apple Intelligence, or cloud enhancement via Claude, OpenAI, Groq, or Gemini
- **Custom dictionary** — teach it your names, jargon, and abbreviations
- **App exclusions** — disable dictation in specific apps so their native shortcuts still work
- **HUD overlay** — minimal recording indicator that never steals focus
- **Engine comparison** — record once, see both engines side by side
- **Sensitivity detection** — pauses AI formatting automatically in password fields

---

## Requirements

- macOS **26** or later
- Apple Silicon (required for Parakeet; Apple Speech works on Intel too)
- Microphone and Accessibility permissions

---

## Installation

1. Download the latest **OpenFlowVoice.dmg** from the [Releases](https://github.com/Hitjack007/OpenFlow-Voice/releases/latest) page
2. Open the DMG and drag **OpenFlow Voice** to your Applications folder
3. Before opening, run this once in Terminal to clear the macOS security warning:
   ```bash
   xattr -dr com.apple.quarantine /Applications/OpenFlowVoice.app
   ```
4. Open the app and follow the setup guide

---

## Building from Source

### Prerequisites
- macOS 15 or later
- Xcode 26 or later

### Steps

```bash
git clone https://github.com/Hitjack007/OpenFlow-Voice.git
cd OpenFlow-Voice
open OpenFlowVoice.xcodeproj
```

In Xcode, set your own development team under **Signing & Capabilities** for both `OpenFlowVoice` and `OpenFlowVoiceHelper`, then press **Cmd + R**.

---

## Credits

Parakeet transcription powered by [FluidAudio](https://github.com/fluidaudio/FluidAudio).

---

## License

MIT License

Copyright © 2026 Mark Greene
