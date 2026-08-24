# OpenFlow Voice

Push-to-talk dictation for macOS. Hold a key, talk, release — cleaned-up text lands in
whatever text field has focus. A Wispr Flow-shaped app, built native and fully on-device.

**Status:** working skeleton. Builds, launches, arms the hotkey, transcribes, injects.
Branding and the LLM cleanup tier are the next passes.

---

## Coexisting with another dictation app

This app is built to run alongside other dictation tools without colliding with them, which
is not automatic on macOS and is worth understanding before changing anything:

- **Bundle ID `com.Hitjack007.OpenFlow-Voice`** — TCC keys Accessibility and Microphone
  grants to the bundle ID, so granting or revoking a permission here has no effect on any
  other app, and vice versa.
- **Executable `OpenFlowVoice`** — distinct enough that `pkill -x OpenFlowVoice` cannot
  match a differently-named binary.
- **Hotkey is configurable** (Right ⌥ / fn / Right ⌘) precisely because another tool may
  already own the key you'd reach for first. The event tap inspects only its own keycode
  and passes everything else through untouched.

If you run more than one dictation app, give each a different push-to-talk key. Two apps on
the same key both record, and whichever injects text will fight the other.

---

## Quick start

Open `OpenFlowVoice.xcodeproj` in Xcode, pick your Team under the target's
Signing & Capabilities tab (first run only), then **⌘R**.

Then grant two permissions — neither is optional, and neither can be requested silently:

| Permission | Where | Needed for |
|---|---|---|
| **Accessibility** | System Settings ▸ Privacy & Security ▸ Accessibility | The `CGEventTap` that sees the hotkey, and the AX text insert |
| **Microphone** | Prompted on first dictation | Audio capture |

Restart OpenFlow Voice after granting Accessibility. Then hold **Right ⌥** and talk.

### Why grants survive rebuilds here

TCC stores a *code-signing requirement* per entry, not just a path. Xcode's Automatic
signing reuses one stable certificate across rebuilds — unlike an ad-hoc signature, which
changes on every build and makes the rebuilt binary stop satisfying the stored requirement.
When that happens the symptom is nasty: the Accessibility toggle still **shows as on** while
the app is reported untrusted, and flipping it changes nothing because the stale row is the
problem.

If a grant ever does get wedged, reset that one row and re-add — never toggle:

```bash
tccutil reset Accessibility com.Hitjack007.OpenFlow-Voice
tccutil reset Microphone   com.Hitjack007.OpenFlow-Voice
```

Always pass the bundle ID. A bare `tccutil reset Accessibility` wipes **every** app on the
machine. Then quit System Settings entirely (⌘Q) before reopening — that pane caches its
list and will otherwise show the row you just deleted.

For a copy worth keeping in `/Applications` rather than running straight out of
DerivedData, use Xcode's **Product ▸ Archive**.

---

## Architecture

```
 hold key ─► HotkeyMonitor ──► DictationController ◄── Settings
                                │
                     ┌──────────┼──────────┐
                     ▼          ▼          ▼
              AudioCapture  HUDPanel   TranscriptionEngine
                     │                      │
                (AudioChunk) ──ordered──► AppleSpeechEngine
                                            │
                                       (transcript)
                                            ▼
                                      TextFormatter
                                            ▼
                                      TextInjector ─► focused app
```

### Decisions worth knowing

**The HUD must never take focus.** `HUDPanel` is a `.nonactivatingPanel` with
`canBecomeKey == false`. This is the load-bearing detail of the whole app: if the overlay
took key status, the user's text field would lose focus and there'd be nothing left to
inject into. Everything else is replaceable; this isn't.

**The hotkey needs a `CGEventTap`, not `NSEvent`.** `fn` and left/right modifier
discrimination don't surface through `NSEvent.addGlobalMonitorForEvents` or the Carbon
hotkey API. A session event tap is the only way to see them — which is why Accessibility
permission is a hard requirement rather than a nicety.

**Audio ordering is explicit.** `AudioCapture` yields into an `AsyncStream` drained by a
single task. Spawning a `Task` per buffer would be simpler and would silently corrupt the
transcript, because unstructured tasks have no ordering guarantee.

**Buffers are copied, never borrowed.** `AVAudioEngine` recycles the buffer it hands to a
tap the instant the callback returns. `AudioChunk`'s `@unchecked Sendable` is only sound
because `AudioCapture` always allocates fresh storage before handing off.

**Two swappable seams.** `TranscriptionEngine` and `TextFormatter` are protocols so the
two components most likely to change can change without touching anything else.

### Layout

```
OpenFlowVoice/
├── OpenFlowVoiceApp.swift          @main, AppDelegate, MenuBarExtra
├── Core/
│   ├── DictationController.swift   state machine, wires everything
│   ├── HotkeyMonitor.swift         CGEventTap on .flagsChanged
│   ├── AudioCapture.swift          AVAudioEngine tap + format conversion + RMS
│   └── TextInjector.swift          AX insert, pasteboard+⌘V fallback
├── Dictionary/                     DictionaryStore, DictionaryCorrector, DictionaryEntry
├── Transcription/
│   ├── TranscriptionEngine.swift   protocol + AudioChunk
│   └── AppleSpeechEngine.swift     SpeechAnalyzer / SpeechTranscriber
├── Formatting/
│   └── TextFormatter.swift         protocol + RuleBasedFormatter
├── UI/                             HUDPanel, HUDView, MainWindow, SettingsWindow, ...
└── Support/                        Settings, Permissions, Log, RunLog
```

---

## Speech engine

Default is Apple's **`SpeechAnalyzer` / `SpeechTranscriber`**, new in macOS 26: no
dependency, no bundled model, no cloud path, real streaming with `.volatileResults` so
text appears while you're still talking. The OS downloads and manages model assets, so the
first run for a locale may pause on `AssetInstallationRequest`.

The alternative is **Parakeet v3** via FluidAudio (CoreML on the Neural Engine) —
measurably better English WER, ~110× realtime, ~66 MB resident. Implementing
`TranscriptionEngine` is the entire cost of switching; `DictationController` doesn't
change.

| | Apple SpeechTranscriber | Parakeet v3 (FluidAudio) | Whisper large-v3 (WhisperKit) |
|---|---|---|---|
| Dependency | none | SwiftPM | SwiftPM |
| Model download | OS-managed | ~600 MB | ~1.5 GB |
| English accuracy | good | best | good |
| Languages | many | 25 | 99 |
| Latency | low | ~80 ms | 200–500 ms |

---

## Not built yet

1. **LLM cleanup tier.** `RuleBasedFormatter` strips fillers, fixes spacing, capitalizes
   sentences and adds terminal punctuation — genuinely useful, entirely deterministic. The
   real win is a second `TextFormatter` backed by Apple's on-device Foundation Models
   (macOS 26) for tone, list formatting, and honoring spoken corrections, with Claude as an
   optional higher-quality tier.
2. **Command Mode.** Select text, hold a second hotkey, say "make this more formal."
   Needs AX read of `kAXSelectedTextAttribute` plus an LLM round-trip.
3. **Onboarding.** A first-run window that walks through both permissions instead of
   relying on the menu's "Grant…" items.
4. **Notarization.** Ends the Gatekeeper prompt on other machines and makes the app
   distributable outside this one.

---

## Verified

Confirmed via `/usr/bin/log show --predicate 'subsystem ==
"com.Hitjack007.OpenFlow-Voice"'`:

- Builds clean under Swift 6 strict concurrency.
- Signs with Xcode Automatic signing; grants survive rebuild.
- Launches with a Dock icon and menu bar item present.
- Event tap arms on grant without a restart (the poller catches it).
- Full state machine: `starting → listening → finishing → idle`, no errors.
- `SpeechAnalyzer` starts; models already installed, no download stall.
- Audio capture runs and converts native 48 kHz → 16 kHz for the engine.
- Silence produces an empty transcript and injects nothing.

> `log` is shadowed in this shell — use `/usr/bin/log` explicitly or it returns nothing.
