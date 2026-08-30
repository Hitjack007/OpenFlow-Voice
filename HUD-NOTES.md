# How OpenFlow Voice Records and Injects Text

## Overview

When you press the push-to-talk hotkey, OpenFlow Voice intercepts the key event before any other app sees it, starts capturing microphone audio, and shows a minimal HUD overlay. When you release the key, it runs the audio through the transcription engine, formats the result, and injects it at the cursor in whatever app was in focus — all in under a second on Apple Silicon with Apple Speech.

---

## Full Pipeline

```
Hotkey key-down
  ↓
CGEvent Tap (HID level, head insert) — HotkeyMonitor
  ↓
DictationController.startRecording()
  ↓
AudioCapture starts AVAudioEngine mic session
  ↓
HUDPanel.show() — floating overlay appears
  ↓
[user speaks]
  ↓
Hotkey key-up → HotkeyMonitor
  ↓
DictationController.stopRecording()
  ↓
AudioCapture flushes PCM buffer
  ↓
TranscriptionEngine.transcribe(audio:) async
  ↓
SensitivityScanner.isSensitive() — checks focused AXUIElement
  ↓  (if not sensitive)
TextFormatter.format(raw:) — FoundationModel or Cloud
  ↓
DictionaryCorrector.apply(to:)
  ↓
TextInjector.inject(text:)
  ↓
HUDPanel.hide() — overlay disappears
```

---

## Step 1 — Key Interception (`HotkeyMonitor.swift`)

- Creates a **CGEvent tap** at `.cghidEventTap` with `.headInsertEventTap` placement — first in the chain, before any other app.
- Filters for the configured `hotkeyCode` (default: Left Option, `CGKeyCode(58)`).
- Distinguishes key-down from key-up via `CGEventType` (`.keyDown` / `.keyUp`).
- Requires **Accessibility permission** — `HotkeyMonitor` checks via `XPCHelperClient` before enabling the tap.
- While recording is active, the event is **consumed** (returns `nil`) so the Option key modifier does not reach the frontmost app.

---

## Step 2 — Audio Capture (`AudioCapture.swift`)

- Uses `AVAudioEngine` with the default input node.
- Installs a tap on the input node: `installTap(onBus:bufferSize:format:block:)`.
- Accumulates `AVAudioPCMBuffer` chunks into a single buffer for the full recording duration.
- On stop, detaches the tap and hands the complete buffer to `DictationController`.
- Sample rate is normalized to 16 kHz before passing to Parakeet (Apple Speech handles its own conversion internally).

---

## Step 3 — Transcription

### Apple Speech (`AppleSpeechEngine.swift`)
- Uses `SFSpeechRecognizer` with `SFSpeechAudioBufferRecognitionRequest`.
- On-device (`requiresOnDeviceRecognition = true` when available).
- Returns the `bestTranscription.formattedString` from the recognition result.
- Locale follows system language by default; configurable in settings.

### Parakeet (`ParakeetEngine.swift`)
- Wraps FluidAudio's Parakeet ASR model.
- Runs on Apple Neural Engine (Apple Silicon required).
- Higher word error rate accuracy than Apple Speech, especially for technical vocabulary.
- Model is downloaded on first use and cached locally.

---

## Step 4 — Sensitivity Check (`SensitivityScanner.swift`)

Before formatting or logging, `SensitivityScanner` inspects the focused UI element:

- Reads `kAXIsPasswordField` attribute via `AXUIElementCopyAttributeValue`.
- Also checks `kAXRole` for `AXSecureTextField`.
- If sensitive: formatting is skipped entirely, `RunLog` records nothing, and the raw transcript is injected directly.
- This check runs synchronously on the main thread before any async formatting work starts.

---

## Step 5 — Formatting

### FoundationModelFormatter (`FoundationModelFormatter.swift`)
- Uses Apple's on-device `FoundationModels` framework (Apple Intelligence).
- Prompts the model to add punctuation, fix capitalisation, and clean run-on sentences.
- No data leaves the device.

### CloudEnhancer (`CloudEnhancer.swift`)
- POSTs the raw transcript to a cloud AI API.
- API key retrieved from Keychain via `KeychainStore`.
- Includes a timeout; falls back to the raw transcript on error.

Both formatters receive the raw `String` and return a formatted `String`. `TextFormatter` routes between them based on `Settings.formattingMode`.

---

## Step 6 — Dictionary Correction (`DictionaryCorrector.swift`)

After formatting, `DictionaryCorrector` does a linear scan through all user-defined entries and applies case-insensitive whole-word substitutions. Example: spoken "gonna" → user-defined "going to". Applied last so formatting doesn't inadvertently break the substitution patterns.

---

## Step 7 — Text Injection (`TextInjector.swift`)

Two injection strategies, tried in order:

### CGEvent keystroke injection (preferred)
- Synthesizes individual `CGEvent` key-down/key-up pairs for each character.
- Fast and works in most native macOS apps.
- Posted to the HID event stream with the frontmost app as the target process.

### Pasteboard injection (fallback)
- Saves the current pasteboard contents.
- Writes the transcript to `NSPasteboard.general`.
- Synthesizes `Cmd+V` to paste.
- Restores the previous pasteboard contents after a short delay.
- Used for Electron apps and browser text fields that reject synthetic keystroke events.

---

## Step 8 — HUD (`HUDPanel.swift` / `HUDView.swift`)

**`HUDPanel`** is a `NSPanel` subclass:
- `styleMask = .borderless`
- `level = .floating`
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`
- `ignoresMouseEvents = true` — never steals clicks
- `hidesOnDeactivate = false` — stays visible regardless of focus

**Positioning**: centered horizontally, ~120 pt above the Dock (or screen bottom edge on external displays without a Dock).

**`HUDView`** (SwiftUI):
- Shows a pulsing waveform animation while recording is active.
- Displays the active engine name and elapsed recording time.
- Transitions to a brief "injecting…" state while `TextInjector` runs.
- Fades out over 0.15 s after injection completes.

---

## XPC Helper Protocol (`HelperProtocol.swift`)

The helper runs as a separate sandboxed process to check and request Accessibility authorization, which the main app cannot do without a prompt race condition:

```
isAccessibilityAuthorized(reply:)
requestAccessibilityAuthorization(reply:)
```

Service name: `co.sushisushi.openflowvoice.helper`

---

## Key Files

| File | Role |
|------|------|
| `Core/HotkeyMonitor.swift` | CGEvent tap, key-down/up detection, event consumption |
| `Core/AudioCapture.swift` | AVAudioEngine mic session, PCM buffer accumulation |
| `Transcription/AppleSpeechEngine.swift` | SFSpeechRecognizer wrapper |
| `Transcription/ParakeetEngine.swift` | FluidAudio Parakeet wrapper |
| `Formatting/SensitivityScanner.swift` | AXUIElement password field check |
| `Formatting/TextFormatter.swift` | Routes to FoundationModel or Cloud formatter |
| `Formatting/FoundationModelFormatter.swift` | On-device AI formatting |
| `Formatting/CloudEnhancer.swift` | Cloud AI formatting |
| `Dictionary/DictionaryCorrector.swift` | User word substitutions |
| `Core/TextInjector.swift` | CGEvent / pasteboard text injection |
| `UI/HUDPanel.swift` | Floating NSPanel for the recording overlay |
| `UI/HUDView.swift` | SwiftUI recording indicator |
| `Core/XPCHelperClient.swift` | XPC connection to privileged helper |
