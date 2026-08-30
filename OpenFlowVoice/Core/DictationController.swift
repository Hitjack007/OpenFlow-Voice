import AVFoundation
import AppKit
import Foundation
import Observation

/// Builds the engine named by the current setting.
///
/// Deliberately at file scope rather than a static on `DictationController`: the class is
/// `@MainActor`, which would make a static method main-actor-isolated and therefore
/// ineligible to be `@Sendable`. Reading the setting per-utterance is what lets the menu's
/// engine picker take effect on the very next hold instead of needing a restart.
@Sendable
func engineForCurrentSetting() -> any TranscriptionEngine {
    // Always invoked from `beginDictation`, which runs on the main actor.
    MainActor.assumeIsolated {
        switch Settings.shared.engine {
        case .apple: AppleSpeechEngine()
        case .parakeet: ParakeetEngine()
        }
    }
}

@MainActor
@Observable
final class DictationController {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case finishing
        /// Dictation succeeded but no text field had focus — the HUD shows a copy fallback.
        case noTarget(String)
        /// Cloud enhancement was requested and sensitive data was detected; waiting for user to confirm.
        case awaitingEnhancement(text: String, flagged: [SensitiveMatch])
        /// Enhancement is running; HUD stays expanded with a loading indicator.
        case enhancing
        /// Cloud enhancement failed; HUD asks whether to retry with local AI.
        case awaitingRetry(text: String)
        case error(String)

        var isActive: Bool {
            switch self {
            case .starting, .listening, .finishing: true
            default: false
            }
        }

        var showsHUD: Bool {
            switch self {
            case .starting, .listening, .finishing, .noTarget, .awaitingEnhancement, .enhancing, .awaitingRetry: true
            case .idle, .error: false
            }
        }
    }

    private(set) var isHandsFree = false
    private(set) var state: State = .idle
    var hotkeyBlocked = false
    /// Live transcript, updated as the engine revises it. Drives the HUD.
    private(set) var transcript = ""
    /// Per-band mel spectrum levels (0…1) for the waveform; 10 bands, envelope-followed.
    private(set) var levels: [Float] = [Float](repeating: 0, count: 10)

    private let capture = AudioCapture()
    private let makeEngine: @Sendable () -> any TranscriptionEngine

    /// Injected only by tests; production reads the setting per-utterance below.
    private let formatter: (any TextFormatter)?

    /// Chosen per-utterance so the menu toggle applies to the very next hold.
    private var activeFormatter: any TextFormatter {
        if let formatter { return formatter }
        return Settings.shared.smartCleanup
            ? FoundationModelFormatter()
            : RuleBasedFormatter()
    }

    private var engine: (any TranscriptionEngine)?
    private var consumeTask: Task<Void, Never>?
    /// Returns the ordered recording when compare mode is on, empty otherwise.
    private var feedTask: Task<[AudioChunk], Never>?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    /// Timestamps for the dashboard: when the key went down, and when it came up.
    private var holdStarted: Date?
    private var releasedAt: Date?
    private var engineName = ""

    /// Compare mode only: the recording, kept so every engine sees identical audio.
    private var recorded: [AudioChunk] = []
    private var isComparing = false

    /// Suspended while waiting for the user to resolve the enhancement confirmation.
    private var enhancementContinuation: CheckedContinuation<Bool, Never>?
    /// Suspended while waiting for the user to choose retry-local or skip after cloud failure.
    private var retryContinuation: CheckedContinuation<Bool, Never>?

    init(
        formatter: (any TextFormatter)? = nil,
        makeEngine: @escaping @Sendable () -> any TranscriptionEngine = engineForCurrentSetting
    ) {
        self.formatter = formatter
        self.makeEngine = makeEngine
    }

    // MARK: - Lifecycle

    /// Wires the hotkey callbacks and installs the event tap in this process.
    func activate() {
        let monitor = HotkeyMonitor.shared
        monitor.onPress = { [weak self] in
            guard let self, !self.hotkeyBlocked else { return }
            if self.isHandsFree {
                self.isHandsFree = false
                self.endDictation()
            } else {
                self.beginDictation()
            }
        }
        monitor.onRelease = { [weak self] in
            guard let self, !self.hotkeyBlocked else { return }
            if !self.isHandsFree { self.endDictation() }
        }
        monitor.onDoubleTap = { [weak self] in
            guard let self, !self.hotkeyBlocked else { return }
            self.beginHandsFreeMode()
        }
        let ok = monitor.start(key: Settings.shared.pushToTalkKey)
        if !ok {
            Log.hotkey.error("couldn't install event tap — Accessibility permission missing?")
        }
    }

    func deactivate() {
        isHandsFree = false
        HotkeyMonitor.shared.stop()
        cancelDictation()
    }

    /// Re-arms the tap after the user picks a different push-to-talk key.
    func reloadHotkey() {
        activate()
    }

    private func beginHandsFreeMode() {
        isHandsFree = true
        beginDictation()
    }

    // MARK: - Button-driven recording

    /// Starts a recording from a Record button rather than the hotkey.
    ///
    /// Wispr Flow's hotkey is held down for the duration **only in compare mode**. Reaching
    /// into another app is a comparison affordance; during ordinary dictation it would mean
    /// every recording silently shipped your audio to a third party's servers.
    func startButtonRecording() {
        guard case .idle = state else { return }
        if Settings.shared.compareMode { WisprTrigger.press() }
        beginDictation()
    }

    /// Releases Wispr's hotkey first, so its upload starts while our own engines are still
    /// finishing — otherwise every run would wait the full round trip end to end.
    func stopButtonRecording() {
        WisprTrigger.release()
        endDictation()
    }

    // MARK: - Enhancement confirmation

    /// Called by the HUD's confirmation buttons. Resumes the suspended enhancement flow.
    func resolveEnhancement(sendToCloud: Bool) {
        state = .enhancing  // keep HUD expanded while work runs
        enhancementContinuation?.resume(returning: sendToCloud)
        enhancementContinuation = nil
    }

    /// Called by the retry HUD buttons after cloud enhancement fails.
    func resolveRetry(useLocal: Bool) {
        if useLocal { state = .enhancing }  // show spinner while local model runs
        retryContinuation?.resume(returning: useLocal)
        retryContinuation = nil
    }

    // MARK: - Dictation

    private func beginDictation() {
        guard case .idle = state else { return }
        state = .starting
        transcript = ""
        holdStarted = Date()
        isComparing = Settings.shared.compareMode
        recorded.removeAll(keepingCapacity: true)
        engineName = isComparing ? "Comparing…" : Settings.shared.engine.displayName

        Task { @MainActor in
            do {
                guard await Permissions.requestMicrophone() else {
                    fail("Microphone access is off. Enable it in System Settings ▸ Privacy & Security ▸ Microphone.")
                    return
                }

                // Yield the actor once so any concurrent endDictation() that was queued
                // during a brief key tap can flip state before we commit to engine startup.
                // Without this, teardown() would call engine.finish() on an analyzer that
                // has never received audio, causing finalizeAndFinishThroughEndOfInput() to
                // hang indefinitely.
                await Task.yield()
                guard case .starting = self.state else { return }

                let engine = makeEngine()
                self.engine = engine

                let chunks = try await engine.start()

                // Compare mode captures in *Apple's* format, not a format of our choosing.
                //
                // SpeechAnalyzer enforces `Audio sample data must be 16-bit signed integers`
                // as a hard precondition — feeding it float32 doesn't fail gracefully, it
                // kills the process. Parakeet is the flexible one (its `feed` converts
                // int16/int32/float32), so the strict engine picks the format and the
                // tolerant engine adapts. Both still replay the identical buffers.
                let formatOwner: any TranscriptionEngine = isComparing ? AppleSpeechEngine() : engine
                guard let format = await formatOwner.preferredInputFormat() else {
                    throw TranscriptionError.noAudioFormat
                }

                // Audio must reach the engine in capture order. A stream plus a single
                // draining task guarantees that; spawning a Task per buffer would not.
                let (audioStream, audioContinuation) = AsyncStream<AudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
                self.audioContinuation = audioContinuation

                // The recording is accumulated *inside* the ordered drain, not by spawning
                // a task per buffer. Unstructured tasks have no ordering guarantee, so
                // collecting them separately could assemble the replay audio out of order
                // and silently produce word-salad from the comparison.
                let comparing = isComparing
                self.feedTask = Task.detached(priority: .userInitiated) {
                    var recording: [AudioChunk] = []
                    for await chunk in audioStream {
                        if comparing { recording.append(chunk) }
                        await engine.feed(chunk)
                    }
                    return recording
                }

                try capture.start(
                    outputFormat: format,
                    onBuffer: { chunk in
                        audioContinuation.yield(chunk)
                    },
                    onLevel: { [weak self] bands in
                        Task { @MainActor in self?.updateLevel(bands) }
                    }
                )

                // Bail out if the user already let go while we were spinning up.
                guard case .starting = self.state else {
                    await self.teardown()
                    return
                }

                self.state = .listening
                if Settings.shared.soundEnabled { NSSound(named: "Tink")?.play() }

                self.consumeTask = Task { @MainActor in
                    do {
                        for try await chunk in chunks {
                            self.transcript = chunk.text
                        }
                    } catch {
                        self.fail(error.localizedDescription)
                    }
                }
            } catch {
                // If state already moved past .starting (endDictation fired and cleaned up
                // while we were initializing the engine), this error is from a canceled
                // startup — not something the user needs to see.
                guard case .starting = self.state else { return }
                self.fail(error.localizedDescription)
            }
        }
    }

    private func endDictation() {
        // `.finishing` is "active", so without this a second press during processing would
        // run the whole tail again — re-reading `transcript` before the first pass cleared
        // it and pasting the same utterance twice. The window is wide: Parakeet transcribes
        // inside `finish()`, and smart cleanup adds up to 4s on top.
        guard state.isActive, state != .finishing else { return }
        state = .finishing
        capture.stop()
        levels = [Float](repeating: 0, count: 10)
        releasedAt = Date()

        Task { @MainActor in
            // Drain every captured buffer into the engine before asking it to finalize,
            // or the tail of the utterance gets dropped.
            audioContinuation?.finish()
            audioContinuation = nil
            Log.speech.info("cleanup: draining feed task")
            recorded = await feedTask?.value ?? []
            feedTask = nil
            Log.speech.info("cleanup: feed done — calling engine.finish()")
            await engine?.finish()
            Log.speech.info("cleanup: engine done — awaiting consumeTask")
            await consumeTask?.value
            Log.speech.info("cleanup: consumeTask done")
            consumeTask = nil
            engine = nil

            if isComparing {
                await runComparison()
                return
            }

            let raw = transcript
            guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                state = .idle
                transcript = ""
                return
            }

            // Short utterances skip both LLM passes — the model startup cost (~1-4s) is
            // never worth it for a single word or brief phrase that rule-based cleanup handles well.
            let isShort = raw.split(whereSeparator: \.isWhitespace).count <= 10

            let cleaned = Settings.shared.cleanupEnabled
                ? await (isShort ? RuleBasedFormatter() : activeFormatter).format(raw)
                : raw

            let enhanced = isShort ? cleaned : await runEnhancement(cleaned, rawTranscript: raw)

            // The dictionary runs last, and runs regardless of the cleanup setting. Biasing
            // only raises the odds of the right word; this is the pass that guarantees it,
            // so it must not be something the user can accidentally switch off.
            let (output, corrections) = DictionaryStore.shared.corrector.apply(to: enhanced)
            if !corrections.isEmpty {
                Log.speech.info("dictionary · \(corrections.count, privacy: .public) correction(s) applied")
            }

            recordRun(text: output, corrections: corrections)
            let inserted = await TextInjector.insert(output)
            if Settings.shared.soundEnabled { NSSound(named: "Pop")?.play() }

            if inserted {
                state = .idle
                transcript = ""
            } else {
                state = .noTarget(output)
                transcript = ""
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(8))
                    if case .noTarget = state { state = .idle }
                }
            }
        }
    }

    func dismissNoTarget() {
        guard case .noTarget = state else { return }
        state = .idle
    }

    private func cancelDictation() {
        isHandsFree = false
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        consumeTask?.cancel()
        consumeTask = nil

        // If we're waiting for the user to confirm cloud enhancement or retry, resolve with
        // "no"/"skip" so the suspended endDictation task can clean up rather than leak.
        if let cont = enhancementContinuation {
            cont.resume(returning: false)
            enhancementContinuation = nil
        }
        if let cont = retryContinuation {
            cont.resume(returning: false)
            retryContinuation = nil
        }

        let engine = self.engine
        self.engine = nil
        Task { await engine?.finish() }

        state = .idle
        transcript = ""
        levels = [Float](repeating: 0, count: 10)
    }

    private func teardown() async {
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        await feedTask?.value
        feedTask = nil
        await engine?.finish()
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .idle
    }

    // MARK: - Enhancement

    private func runEnhancement(_ text: String, rawTranscript: String = "") async -> String {
        switch Settings.shared.enhancementMode {
        case .off:
            return text

        case .local:
            state = .enhancing
            return await FoundationModelFormatter.enhance(text)

        case .cloud:
            let provider = Settings.shared.cloudProvider
            guard let apiKey = KeychainStore.load(forKey: provider.keychainKey), !apiKey.isEmpty else {
                Log.speech.info("Cloud enhancement: no API key for \(provider.rawValue, privacy: .public) — falling back to local")
                state = .enhancing
                return await FoundationModelFormatter.enhance(text)
            }

            // Scan cleaned text for redactable positions; scan raw transcript for detection
            // coverage (cleanup can corrupt spoken numbers into forms the regex can't match).
            let redactMatches = SensitivityScanner.scan(text)
            var allKinds = Set(redactMatches.map(\.kind))
            if !rawTranscript.isEmpty {
                allKinds.formUnion(SensitivityScanner.scan(rawTranscript).map(\.kind))
            }
            Log.speech.info("sensitivity: \(redactMatches.count, privacy: .public) redactable, \(allKinds.count, privacy: .public) total kind(s) in: \(text, privacy: .private)")

            if allKinds.isEmpty {
                // No sensitive data found in either scan — send directly to cloud.
                state = .enhancing
                do {
                    return try await CloudEnhancer.enhance(text, provider: provider)
                } catch {
                    Log.speech.error("Cloud enhancement failed: \(error.localizedDescription)")
                    let useLocal: Bool = await withCheckedContinuation { continuation in
                        retryContinuation = continuation
                        state = .awaitingRetry(text: text)
                    }
                    return useLocal ? await FoundationModelFormatter.enhance(text) : text
                }
            }

            // Build display list: real redactable matches + synthetic kind-only entries
            // for kinds found in raw text that have no corresponding span in cleaned text.
            let redactKinds = Set(redactMatches.map(\.kind))
            var displayMatches = redactMatches
            for kind in allKinds.subtracting(redactKinds) {
                displayMatches.append(SensitiveMatch(
                    kind: kind, placeholder: "", original: "",
                    nsRange: NSRange(location: NSNotFound, length: 0)
                ))
            }

            // Suspend and show HUD confirmation.
            let sendToCloud: Bool = await withCheckedContinuation { continuation in
                self.enhancementContinuation = continuation
                self.state = .awaitingEnhancement(text: text, flagged: displayMatches)
            }

            if !sendToCloud {
                return await FoundationModelFormatter.enhance(text)
            }

            // If no redactable spans exist in the cleaned text (sensitive data was only
            // detected in the raw transcript), the cleanup already transformed those values.
            // Sending to cloud unredacted would expose them — use local instead.
            guard !redactMatches.isEmpty else {
                Log.speech.info("Sensitive kinds detected in raw transcript but not redactable in cleaned text — using local enhancement")
                return await FoundationModelFormatter.enhance(text)
            }

            let redacted = SensitivityScanner.redact(text, matches: redactMatches)
            let mapping = Dictionary(uniqueKeysWithValues: redactMatches.map { ($0.placeholder, $0.original) })
            do {
                let cloudResult = try await CloudEnhancer.enhance(redacted, provider: provider)
                return await FoundationModelFormatter.restore(
                    redactedInput: redacted,
                    mapping: mapping,
                    cloudOutput: cloudResult
                )
            } catch {
                Log.speech.error("Cloud enhancement (redacted) failed: \(error.localizedDescription)")
                var restored = redacted
                for (placeholder, original) in mapping {
                    restored = restored.replacingOccurrences(of: placeholder, with: original)
                }
                let useLocal: Bool = await withCheckedContinuation { continuation in
                    retryContinuation = continuation
                    state = .awaitingRetry(text: restored)
                }
                return useLocal ? await FoundationModelFormatter.enhance(restored) : restored
            }
        }
    }

    // MARK: - Helpers

    private func retainForComparison(_ chunk: AudioChunk) {
        guard isComparing else { return }
        recorded.append(chunk)
    }

    /// Replays the recording through every engine and files the results as one group.
    ///
    /// Nothing is injected in this mode — the point is to read the outputs side by side,
    /// and typing one of them into whatever had focus would be a surprise.
    private func runComparison() async {
        let chunks = recorded
        recorded.removeAll(keepingCapacity: false)

        guard !chunks.isEmpty, let holdStarted, let releasedAt else {
            state = .idle
            transcript = ""
            return
        }

        transcript = "Running both engines…"

        let group = UUID().uuidString
        let held = releasedAt.timeIntervalSince(holdStarted)

        // Filed one at a time as each engine finishes, so the window fills in progressively
        // rather than snapping both rows into place at the end.
        let results = await EngineComparison.run(chunks: chunks) { result in
            RunLog.record(
                DictationRun(
                    date: releasedAt,
                    engine: result.engine,
                    audioSeconds: held,
                    processSeconds: result.seconds,
                    text: result.text,
                    group: group
                )
            )
        }

        for result in results {
            Log.speech.info("""
                compare · \(result.engine, privacy: .public): \
                \(result.seconds, format: .fixed(precision: 2))s — \
                \(result.text, privacy: .public)
                """)
        }

        // Wispr Flow, if its hotkey was held for this same utterance. It transcribes in the
        // cloud, so its row lands after both local engines have already finished — the wait
        // happens here rather than blocking the rows above from appearing.
        if WisprReader.isInstalled {
            transcript = "Waiting for Wispr Flow…"
            if let wispr = await WisprReader.result(after: holdStarted, timeout: 8) {
                RunLog.record(
                    DictationRun(
                        date: releasedAt,
                        engine: wispr.engine,
                        audioSeconds: held,
                        processSeconds: wispr.seconds,
                        text: wispr.text,
                        group: group
                    )
                )
                Log.speech.info("""
                    compare · \(wispr.engine, privacy: .public): \
                    \(wispr.seconds, format: .fixed(precision: 2))s — \
                    \(wispr.text, privacy: .public)
                    """)
            } else {
                Log.speech.info("compare · Wispr Flow: no result (hotkey not held, or timed out)")
            }
        }

        self.holdStarted = nil
        self.releasedAt = nil
        isComparing = false
        state = .idle
        transcript = ""

        if Settings.shared.soundEnabled { NSSound(named: "Glass")?.play() }
    }

    /// Files the finished utterance for the dashboard.
    ///
    /// `processSeconds` is measured from key release, not from capture start — that's the
    /// wait the user actually experiences, and it's the only number on which a streaming
    /// engine and a batch engine can be compared honestly.
    private func recordRun(text: String, corrections: [AppliedCorrection] = []) {
        guard let holdStarted, let releasedAt else { return }
        RunLog.record(
            DictationRun(
                date: releasedAt,
                engine: engineName,
                audioSeconds: releasedAt.timeIntervalSince(holdStarted),
                processSeconds: Date().timeIntervalSince(releasedAt),
                text: text,
                corrections: corrections.isEmpty ? nil : corrections
            )
        )
        self.holdStarted = nil
        self.releasedAt = nil
    }

    private func updateLevel(_ new: [Float]) {
        levels = new
    }

    private func fail(_ message: String) {
        Log.app.error("\(message)")
        capture.stop()
        audioContinuation?.finish()
        audioContinuation = nil
        feedTask?.cancel()
        feedTask = nil
        engine = nil
        consumeTask?.cancel()
        consumeTask = nil
        state = .error(message)
        levels = [Float](repeating: 0, count: 10)

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if case .error = state { state = .idle }
        }
    }
}
