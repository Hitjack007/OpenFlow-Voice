# Working on this repo

Read this before changing anything. It is written for a coding agent picking the project up
cold, and it is mostly a list of things that look wrong but aren't, plus things that look
fine and will bite you.

---

## What this is

Push-to-talk dictation for macOS. Hold a key, talk, release, and cleaned-up text is typed
into whatever had focus. Swift 6, SwiftUI, speech via Apple `SpeechAnalyzer` or Parakeet via
FluidAudio. **Works and is in daily use.**

A plain Xcode project — `OpenFlowVoice.xcodeproj`, one target, no wrapper build system. Open
it, pick your Team in Signing & Capabilities once, and ⌘R.

---

## Things that look like bugs and are not

**Compare mode doesn't type anything.** By design — `Settings.compareMode` runs every engine
on one recording and shows them side by side. If both injected, two transcripts would fight
over one text field. This is the single most confusing behaviour in the app.

**The timing column isn't comparing like with like.** Apple and Parakeet are timed on local
compute with the clock started *after* model load. Wispr Flow's number is its own
`e2eLatency`, which includes a network round trip and its cleanup pass. Don't present them
as one ranking.

**`MainActor.assumeIsolated` will crash the process.** It does not check the claim, it
asserts it. Use `await MainActor.run` from any non-main-actor context. This took the app
down once already.

**Mutating `@State` inside a `Canvas` draw closure floods the log and corrupts state.** The
VU meter keeps its needle physics in a plain reference type the view merely holds, which is
invisible to SwiftUI's state graph. Don't "clean that up" into `@State`.

---

## Design system

`OpenFlowVoice/UI/DesignSystem.swift` defines every colour, size, radius, duration and
material token. **Views must not contain literal values.** If a component needs a number
that isn't a token, add the token rather than inlining it.

The direction is 1980s field recorders — Sony TC-D5, Marantz PMD, Nakamichi, Braun. Silver
face in light appearance, black face in dark. Two rules that are not negotiable:

- **Red means recording.** Nothing else in the app is red.
- **Amber and green are instrumentation only** — level meters, never UI chrome.

Explicitly ruled out: neon, vaporwave, synthwave, purple/pink gradients, glowing text, chrome
lettering, grid horizons. There are **no gradients anywhere**; depth comes from flat panels,
hairline bevels and procedurally-drawn brushed grain.

---

## macOS specifics

**Code signing is load-bearing, not cosmetic.** TCC stores a code-signing *requirement* per
entry, not just a path. Xcode's Automatic signing reuses one stable certificate across
rebuilds, which is what keeps the Accessibility/Microphone grants sticky — don't switch the
target to ad-hoc (`-`) signing, which mints a new identity every build and resets both grants.

If a grant does get wedged, reset that one row — never toggle, and never omit the bundle ID:

```bash
tccutil reset Accessibility com.Hitjack007.OpenFlow-Voice
```

A bare `tccutil reset Accessibility` wipes every app on the machine. Then quit System
Settings entirely (⌘Q) before reopening; the Privacy pane caches its list.

**`log` may be shadowed in the user's shell.** Use `/usr/bin/log` explicitly.

**Don't run the `.app` straight out of DerivedData for daily use.** It's a build artifact,
not a stable path — Product ▸ Archive is the way to get a copy worth keeping in
`/Applications`.

---

## Regex, if you touch the dictionary

Stay inside the safe subset — `\b`, `\d`, `\w`, `\s`, character classes, greedy/lazy
quantifiers, alternation, `(?<name>…)`, fixed-length lookbehind, lookahead, `\p{L}`, and
`$1`–`$9` in replacements. Nothing else.

**NFC normalization matters.** macOS returns decomposed strings in several places, so without
normalizing first an accented trigger can silently never fire.

---

## What isn't built

1. **Command Mode** — select text, hold a second key, "make this more formal."
2. **Onboarding** — a first-run window walking through the macOS permissions.
3. **Notarization** — the app is unsigned for distribution.
