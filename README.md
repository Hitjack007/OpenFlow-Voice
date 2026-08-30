# OpenFlow Voice

Push-to-talk dictation for macOS. Hold a hotkey, speak, release — cleaned-up text lands at the cursor in whatever app has focus. Runs entirely on-device with no cloud dependency required.

---

## Features

- **Push-to-talk** — hold the hotkey to record, release to transcribe and inject
- **Multiple engines** — Apple SpeechTranscriber (streaming, on-device) or Parakeet via FluidAudio (higher accuracy, Apple Silicon)
- **AI formatting** — on-device cleanup via Apple Intelligence (Foundation Models) or cloud enhancement via API
- **Custom dictionary** — teach the app your names, jargon, and abbreviations
- **Sensitivity detection** — pauses formatting automatically in password fields
- **App exclusions** — skip dictation entirely in apps you choose
- **HUD overlay** — minimal recording indicator that appears and disappears without stealing focus
- **Engine comparison** — record once, see Apple Speech vs. Parakeet output side by side
- **Wispr Flow compatibility** — drop-in replacement for users migrating from Wispr
- **Onboarding** — guided first-run flow for permissions, engine choice, and hotkey setup

---

## Requirements

- macOS **26** or later
- Apple Silicon Mac (required for Parakeet engine; Apple Speech works on Intel)
- Microphone access
- Accessibility access (required for the event tap and text injection)

---

## Building from Source

```bash
git clone https://github.com/mark-greene/openflow-voice.git
cd openflow-voice
open OpenFlowVoice/OpenFlowVoice.xcodeproj
```

In Xcode, set your development team under **Signing & Capabilities** for both `OpenFlowVoice` and `OpenFlowVoiceHelper`, then press **Cmd + R**.

Grant two permissions on first run — neither is optional:

| Permission | Where | Needed for |
|---|---|---|
| **Accessibility** | System Settings ▸ Privacy & Security ▸ Accessibility | CGEventTap for the hotkey, and AX text injection |
| **Microphone** | Prompted on first dictation | Audio capture |

Restart OpenFlow Voice after granting Accessibility. Then hold **Right ⌥** and talk.

### Why grants survive rebuilds

TCC stores a code-signing requirement per entry, not just a path. Xcode's Automatic signing reuses one stable certificate across rebuilds — so grants stay valid. If a grant ever gets wedged, reset and re-add (never just toggle):

```bash
tccutil reset Accessibility com.Hitjack007.OpenFlow-Voice
tccutil reset Microphone   com.Hitjack007.OpenFlow-Voice
```

Always pass the bundle ID. A bare `tccutil reset Accessibility` wipes every app on the machine.

---

## Coexisting with other dictation apps

OpenFlow Voice is built to run alongside other dictation tools without collision:

- **Bundle ID `com.Hitjack007.OpenFlow-Voice`** — TCC grants are per-bundle-ID, so this app's permissions are fully isolated from any other tool.
- **Hotkey is configurable** (Right ⌥ / fn / Right ⌘) because another tool may already own the key you'd reach for first. The event tap inspects only its own keycode and passes everything else through untouched.

If you run more than one dictation app, give each a different push-to-talk key. Two apps on the same key will both record; whichever injects text will fight the other.

---

## Architecture

```
 hold key ─► HotkeyMonitor ──► DictationController ◄── Settings
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
              AudioCapture  HUDPanel   TranscriptionEngine
                     │                      │
                (AudioChunk) ──ordered──► AppleSpeechEngine / ParakeetEngine
                                            │
                                       (transcript)
                                            ▼
                                  SensitivityScanner
                                            ▼
                                      TextFormatter
                                            ▼
                                  DictionaryCorrector
                                            ▼
                                      TextInjector ─► focused app
```

See [CODEBASE_NOTES.md](./CODEBASE_NOTES.md) for a full file map, data flow diagrams, and contribution recipes.

---

## Speech Engines

| | Apple SpeechTranscriber | Parakeet v3 (FluidAudio) |
|---|---|---|
| Dependency | none | SwiftPM (FluidAudio) |
| Model download | OS-managed | ~600 MB on first run |
| English accuracy | good | best |
| Languages | many | 25 |
| Latency | streaming | ~80 ms |
| Requires Apple Silicon | no | yes |

Default is **Apple SpeechTranscriber** (new in macOS 26): no extra dependency, streaming output via `.volatileResults`, OS manages model assets. Switch to **Parakeet** in settings for higher English accuracy at the cost of a one-time model download.

---

## Credits

Push-to-talk architecture and audio pipeline by Mark Greene.

Parakeet transcription engine provided by [FluidAudio](https://github.com/.../).

---

## License

MIT License

Copyright © 2026 Mark Greene
