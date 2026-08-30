# OpenFlow Voice — Codebase Notes

A comprehensive reference for understanding, navigating, and extending the project.

---

## What It Does

OpenFlow Voice is a macOS push-to-talk dictation utility. The user holds a configurable hotkey (default: Left Option), speaks, then releases. The app captures audio, transcribes it via either Apple Speech or the Parakeet engine (FluidAudio), optionally formats the result through AI, applies custom dictionary corrections, and injects the final text at the cursor in whatever app is in focus. A minimal HUD overlay appears while recording is active.

---

## High-Level Architecture

```
OpenFlowVoiceApp (App entry point)
├── DictationController          — orchestrates the full record → transcribe → format → inject pipeline
├── HotkeyMonitor                — detects push-to-talk key down/up via CGEvent tap
├── AudioCapture                 — manages AVAudioEngine mic input, produces PCM buffers
├── TranscriptionEngine (protocol)
│   ├── AppleSpeechEngine        — on-device Apple Speech framework
│   └── ParakeetEngine           — FluidAudio Parakeet (Apple Silicon)
├── TextFormatter                — cleans and structures raw transcript
│   ├── FoundationModelFormatter — on-device formatting via Apple Intelligence
│   ├── CloudEnhancer            — cloud-based AI formatting
│   └── SensitivityScanner       — detects password/sensitive fields; suppresses formatting
├── DictionaryCorrector          — applies user-defined word substitutions post-transcription
├── TextInjector                 — types final text into the frontmost app via Accessibility
├── HUDPanel / HUDView           — floating overlay showing recording state
├── OpenFlowVoiceHelper (XPC)    — privileged helper for Accessibility authorization
└── MainWindow / OnboardingView  — settings UI and first-run guided setup
```

---

## File Map

### Entry Point

| File | Role |
|------|------|
| `OpenFlowVoiceApp.swift` | `@main` struct. Initializes `DictationController`, sets up the menu bar item, and launches onboarding on first run. |

### Core Pipeline

| File | Role |
|------|------|
| `Core/DictationController.swift` | Central coordinator. Owns all major subsystems, drives the record → transcribe → format → inject sequence, and publishes state (`isRecording`, `lastTranscript`). |
| `Core/HotkeyMonitor.swift` | CGEvent tap that intercepts the push-to-talk key (key-down to start, key-up to stop). Requires Accessibility permission. |
| `Core/AudioCapture.swift` | `AVAudioEngine`-based mic capture. Delivers PCM buffers to the active transcription engine. |
| `Core/TextInjector.swift` | Uses `CGEvent` keyboard events (or `AXUIElement` paste) to insert text at the cursor. Falls back to pasteboard injection when direct typing isn't possible. |
| `Core/WisprTrigger.swift` | Compatibility layer for apps expecting Wispr Flow's activation protocol. |
| `Core/EngineComparison.swift` | Records a single utterance and runs both engines in parallel so the user can compare output. |
| `Core/XPCHelperClient.swift` | Swift client for the `OpenFlowVoiceHelper` XPC service. Used to check and request Accessibility authorization. |
| `Core/HelperProtocol.swift` | Shared XPC protocol definition (mirrored in the helper target). |

### Transcription Engines

| File | Role |
|------|------|
| `Transcription/TranscriptionEngine.swift` | Protocol that all engines conform to: `transcribe(audio:) async throws -> String`. |
| `Transcription/AppleSpeechEngine.swift` | Wraps `SFSpeechRecognizer`. Works on-device, supports all Apple-supported locales. |
| `Transcription/ParakeetEngine.swift` | Wraps FluidAudio's Parakeet model. Higher accuracy, Apple Silicon only, requires model download. |
| `Transcription/WisprReader.swift` | Reads transcription output from a running Wispr Flow process (for migration/comparison). |

### Formatting

| File | Role |
|------|------|
| `Formatting/TextFormatter.swift` | Entry point for the formatting pipeline. Applies sensitivity check first, then routes to the configured formatter. |
| `Formatting/FoundationModelFormatter.swift` | Uses Apple's on-device `FoundationModels` framework to punctuate, capitalise, and clean up raw transcripts. |
| `Formatting/CloudEnhancer.swift` | Sends raw transcript to a cloud AI API for richer formatting. API key stored in Keychain. |
| `Formatting/SensitivityScanner.swift` | Inspects the focused `AXUIElement` for password field markers. Returns early if sensitive, bypassing all formatting and logging. |

### Dictionary

| File | Role |
|------|------|
| `Dictionary/DictionaryStore.swift` | Persistent store for user word entries. Backed by `UserDefaults`. |
| `Dictionary/DictionaryEntry.swift` | Model: a spoken trigger phrase → replacement text mapping. |
| `Dictionary/DictionaryCorrector.swift` | Applies all dictionary entries to a transcript string after transcription. |

### Support

| File | Role |
|------|------|
| `Support/Settings.swift` | All `UserDefaults` keys and their defaults. **Single source of truth for user preferences.** |
| `Support/Permissions.swift` | Checks and requests Microphone and Accessibility permissions. |
| `Support/KeychainStore.swift` | Stores and retrieves sensitive values (e.g., cloud API keys) from the system Keychain. |
| `Support/Log.swift` | Lightweight structured logging wrapper around `os.Logger`. |
| `Support/RunLog.swift` | Persists a rolling log of recent dictation runs (timestamp, engine, duration, word count) for the dashboard. |

### UI

| File | Role |
|------|------|
| `UI/HUDView.swift` | SwiftUI view for the recording indicator: pulsing waveform, engine name, elapsed time. |
| `UI/HUDPanel.swift` | `NSPanel` subclass that hosts `HUDView`. Floats above all windows, no title bar, click-through. |
| `UI/MainWindow.swift` | Main settings/dashboard window. Hosts engine selection, formatting options, dictionary panel, run log. |
| `UI/OnboardingView.swift` | Step-by-step first-run flow: permissions → engine → enhancement → hotkey → demo. |
| `UI/DictionaryPanel.swift` | Add/edit/delete custom dictionary entries. |
| `UI/ComparisonWindow.swift` | Side-by-side output of Apple Speech vs. Parakeet for the same recording. |
| `UI/DashboardHTML.swift` | HTML/CSS template for the run-history dashboard rendered in a `WKWebView`. |
| `UI/DesignSystem.swift` | Shared colors, fonts, and spacing constants used across all SwiftUI views. |
| `UI/Equipment.swift` | Microphone device picker and audio level meter. |

### XPC Helper

| File | Role |
|------|------|
| `OpenFlowVoiceHelper/main.swift` | XPC listener entry point. |
| `OpenFlowVoiceHelper/HelperService.swift` | Implements the helper protocol — Accessibility checks and authorization prompts. |
| `OpenFlowVoiceHelper/HelperDelegate.swift` | `NSXPCListenerDelegate` that vends `HelperService` instances. |
| `OpenFlowVoiceHelper/HelperProtocol.swift` | Mirrored protocol definition (must stay in sync with `Core/HelperProtocol.swift`). |

---

## The Settings System

All settings live in `Support/Settings.swift` as typed keys. Read and write via `UserDefaults` directly or through SwiftUI bindings.

Key settings:

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `transcriptionEngine` | `String` | `"apple"` | `"apple"` or `"parakeet"` |
| `formattingMode` | `String` | `"foundationModel"` | `"off"`, `"foundationModel"`, or `"cloud"` |
| `hotkeyCode` | `Int` | Left Option | CGKeyCode of the push-to-talk key |
| `excludedBundleIDs` | `[String]` | `[]` | Apps where dictation is suppressed |
| `cloudAPIKey` | stored in Keychain | — | Key for cloud enhancement (via `KeychainStore`) |

---

## Data Flow

### Record → Inject

```
[Hotkey key-down] → HotkeyMonitor
                        ↓
                    DictationController.startRecording()
                        ↓ starts AudioCapture, shows HUDPanel
[Hotkey key-up]  → HotkeyMonitor
                        ↓
                    DictationController.stopRecording()
                        ↓ stops AudioCapture
                    TranscriptionEngine.transcribe(audio:)
                        ↓ raw transcript String
                    SensitivityScanner.isSensitive()   ← if true, skip formatting
                        ↓
                    TextFormatter.format(raw:)
                        ↓ formatted String
                    DictionaryCorrector.apply(to:)
                        ↓ corrected String
                    TextInjector.inject(text:)
                        ↓ text appears at cursor
                    HUDPanel hides
```

### Sensitivity suppression

```
[Text injection requested]
  → SensitivityScanner checks focused AXUIElement for AXIsPasswordField / role hints
  → if sensitive: skip formatting, skip logging, inject raw transcript only
  → if not sensitive: normal pipeline
```

---

## How to Add Features

### Add a new transcription engine

1. **`Transcription/TranscriptionEngine.swift`** — Conform to `TranscriptionEngine`:
   ```swift
   actor MyEngine: TranscriptionEngine {
       func transcribe(audio: AVAudioPCMBuffer) async throws -> String { ... }
   }
   ```

2. **`Support/Settings.swift`** — Add a case to the engine identifier:
   ```swift
   static let engineMyEngine = "myEngine"
   ```

3. **`Core/DictationController.swift`** — Add the case to `makeEngine()`:
   ```swift
   case Settings.engineMyEngine:
       return MyEngine()
   ```

4. **`UI/MainWindow.swift`** — Add the picker option in the engine selection view.

5. **`UI/OnboardingView.swift`** — Add it to the engine step if it should appear during onboarding.

---

### Add a new formatting mode

1. **`Formatting/TextFormatter.swift`** — Add a case to the routing switch:
   ```swift
   case "myFormatter":
       return try await MyFormatter().format(text)
   ```

2. Create `Formatting/MyFormatter.swift` with a `format(_ text: String) async throws -> String` method.

3. **`Support/Settings.swift`** — Add the mode identifier string constant.

4. **`UI/MainWindow.swift`** — Add the UI toggle/picker.

---

### Add a new user setting

1. **`Support/Settings.swift`** — Add a key:
   ```swift
   static let myNewSetting = "myNewSetting"
   static let myNewSettingDefault = false
   ```

2. Read it anywhere:
   ```swift
   UserDefaults.standard.bool(forKey: Settings.myNewSetting)
   ```

3. **`UI/MainWindow.swift`** — Add the UI control in the appropriate section.

---

### Add an app to the exclusion list

The exclusion list is stored in `Settings.excludedBundleIDs`. `DictationController` checks it before starting a recording — if the frontmost app's bundle ID is in the list, the hotkey press is ignored. The UI for managing the list lives in `UI/OnboardingView.swift` (onboarding step) and `UI/MainWindow.swift` (settings).

---

## Design Language

### Colors

- Follow `UI/DesignSystem.swift` for all color values.
- The HUD uses a dark translucent material (`NSVisualEffectView` with `.hudWindow` material).
- Never hardcode colors outside `DesignSystem.swift`.

### HUD

- The HUD must never steal focus (`NSPanel` with `becomesKeyOnlyIfNeeded = false`, `acceptsMouseMovedEvents = false`).
- It positions itself near the bottom-center of the screen, clear of the Dock.
- Appear/disappear with a short opacity animation (≤ 0.2 s).

### Text Injection

- Prefer `CGEvent`-based keystroke injection for speed.
- Fall back to `NSPasteboard` + `Cmd+V` for apps that don't accept synthetic key events.
- Never inject into a field where `SensitivityScanner` returned `true`.

---

## Files to Treat With Care

| File | Why |
|------|-----|
| `Core/HotkeyMonitor.swift` | CGEvent tap runs at `.cghidEventTap` (head insert). Changes here affect every keypress on the system while the app is running. |
| `Core/TextInjector.swift` | Injects into other processes via Accessibility. Bugs here can corrupt text in any app. Test with a wide variety of targets (Terminal, VS Code, Safari, Mail). |
| `Core/HelperProtocol.swift` | Shared between the main app and XPC helper. Adding required methods without updating both sides will break the XPC connection silently. Add `extension` defaults instead. |
| `Support/Settings.swift` — key name strings | Renaming a key string silently resets that preference for all existing users. Never rename; add new keys instead. |
| `Formatting/SensitivityScanner.swift` | This is the privacy gate. Any regression here could log or format text from password fields. |

---

## Files Safe to Freely Edit

- Anything inside `UI/MainWindow.swift` — adding settings rows doesn't affect runtime behaviour
- Any individual SwiftUI view file — they're leaf nodes; changes are isolated
- `UI/DesignSystem.swift` — purely presentational
- `UI/OnboardingView.swift` — only shown once; changes don't affect the core pipeline
- `Dictionary/` — fully isolated from transcription and injection

---

## Package Dependencies

| Package | Purpose |
|---------|---------|
| `FluidAudio` | Parakeet ASR engine — on-device high-accuracy transcription |

---

## XPC Helper

`OpenFlowVoiceHelper` is a small XPC process that handles Accessibility permission checks and prompts, which the sandboxed main app cannot do directly. It is accessed through `Core/XPCHelperClient.swift`.

The XPC protocol is defined in `Core/HelperProtocol.swift` (main app side) and mirrored in `OpenFlowVoiceHelper/HelperProtocol.swift`. Both must stay in sync. If you need to add a new privileged operation, add it to the protocol and implement it in `HelperService.swift` — do not implement it in the main app target.

Service name: `co.sushisushi.openflowvoice.helper`

---

## Common Patterns

**Reading a setting:**
```swift
let engine = UserDefaults.standard.string(forKey: Settings.transcriptionEngine) ?? Settings.engineApple
```

**Checking if the frontmost app is excluded:**
```swift
let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
let excluded = UserDefaults.standard.stringArray(forKey: Settings.excludedBundleIDs) ?? []
guard !excluded.contains(bundleID) else { return }
```

**Storing a secret (API key):**
```swift
try KeychainStore.shared.set(apiKey, forKey: .cloudAPIKey)
let key = try KeychainStore.shared.get(.cloudAPIKey)
```

**Showing the HUD:**
```swift
HUDPanel.shared.show(engine: currentEngine)
// ... recording ...
HUDPanel.shared.hide()
```

**Logging a run:**
```swift
RunLog.shared.append(RunEntry(engine: "parakeet", duration: elapsed, wordCount: words))
```
