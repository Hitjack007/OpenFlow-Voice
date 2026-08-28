import AVFoundation
import Foundation
import Speech

/// Streaming on-device transcription via macOS 26's `SpeechAnalyzer` / `SpeechTranscriber`.
///
/// No model ships with the app — the OS downloads and manages the assets, so the first
/// run for a given locale may block briefly while `AssetInstallationRequest` completes.
actor AppleSpeechEngine: TranscriptionEngine {
    private let locale: Locale

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    /// Drives `analyzeSequence()` + finalization in a background task so `finish()` has a
    /// concrete endpoint to await rather than using `finalizeAndFinishThroughEndOfInput()`,
    /// which hangs on very short recordings (brief taps that barely crossed into .listening).
    private var analyzerTask: Task<Void, Never>?

    /// Text the engine has committed. Volatile results are appended on top for display
    /// but discarded as soon as a final result covering the same range arrives.
    private var finalizedText = ""

    init(locale: Locale = Locale.current) {
        self.locale = locale
    }

    func preferredInputFormat() async -> AVAudioFormat? {
        let module = transcriber ?? Self.makeTranscriber(locale: locale)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module])
    }

    func start() async throws -> AsyncThrowingStream<TranscriptionChunk, Error> {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.localeUnsupported(locale)
        }

        let resolvedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
            ?? Locale(identifier: "en-US")

        let transcriber = Self.makeTranscriber(locale: resolvedLocale)
        self.transcriber = transcriber

        try await Self.ensureModelInstalled(for: transcriber)

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        // Bias the recognizer toward the dictionary's words before it hears anything. This
        // is a nudge, not a guarantee — `DictionaryCorrector` is the pass that actually
        // enforces spelling — but it's free and it catches things a post-hoc rewrite can't,
        // like a name the engine would otherwise split into two ordinary words.
        //
        // The list is capped at `DictionaryCorrector.biasLimit`. A long context list makes
        // these models drift: on quiet or ambiguous audio they start emitting the terms they
        // were primed with, which is a far worse failure than the misspelling it prevents.
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        if let context = await Self.context() {
            try? await analyzer.setContext(context)
        }

        finalizedText = ""

        let (chunks, chunkContinuation) = AsyncThrowingStream<TranscriptionChunk, Error>.makeStream()

        // Drain the transcriber's results into our simpler chunk stream.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { break }
                    let snapshot = await self.absorb(result)
                    chunkContinuation.yield(TranscriptionChunk(text: snapshot, isFinal: false))
                }
            } catch is CancellationError {
                // finish() canceled us because transcriber.results didn't terminate after
                // cancelAndFinishNow() (reproducible when analyzeSequence returned nil, i.e.
                // the analyzer processed zero audio). Fall through and close the stream with
                // whatever text was finalized before the cancel, same as the normal path.
            } catch {
                Log.speech.error("results stream failed: \(error.localizedDescription)")
                chunkContinuation.finish(throwing: error)
                return
            }
            let final = await self?.finalizedText ?? ""
            chunkContinuation.yield(TranscriptionChunk(text: final, isFinal: true))
            chunkContinuation.finish()
        }

        // `analyzeSequence()` blocks until the input stream ends, then returns the last
        // sample time. We run it in a background task so start() returns immediately (the
        // stream is still open; audio arrives via feed()).
        //
        // The finalization path depends on how much audio was captured:
        // - nil (empty input)         → cancelAndFinishNow()
        // - < 500 ms                  → cancelAndFinishNow()
        //   The on-device model needs a minimum context window (~400-500 ms) to produce
        //   results. For shorter audio — accidental key taps — finalizeAndFinish hangs
        //   waiting for a processing window that can never fill. The audio is too brief
        //   to contain usable speech anyway.
        // - ≥ 500 ms                  → finalizeAndFinish(through: lastSampleTime)
        //   By the time analyzeSequence() returns, most frames are already processed
        //   (autonomous analysis ran concurrently). Only the final chunk is outstanding,
        //   so this call completes quickly and captures the last word.
        analyzerTask = Task {
            do {
                Log.speech.info("analyzerTask: analyzeSequence starting")
                let lastSampleTime = try await analyzer.analyzeSequence(inputStream)
                Log.speech.info("analyzerTask: analyzeSequence done — lastSampleTime=\(lastSampleTime?.seconds ?? -1, format: .fixed(precision: 3))s")
                guard let lastSampleTime,
                      lastSampleTime >= CMTime(seconds: 0.5, preferredTimescale: 44100) else {
                    Log.speech.info("analyzerTask: short audio — calling cancelAndFinishNow")
                    await analyzer.cancelAndFinishNow()
                    Log.speech.info("analyzerTask: cancelAndFinishNow done")
                    return
                }
                Log.speech.info("analyzerTask: calling finalizeAndFinish")
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
                Log.speech.info("analyzerTask: finalizeAndFinish done")
            } catch is CancellationError {
                Log.speech.info("analyzerTask: CancellationError")
            } catch {
                Log.speech.info("analyzerTask: error — calling cancelAndFinishNow")
                await analyzer.cancelAndFinishNow()
                Log.speech.error("SpeechAnalyzer failed: \(error.localizedDescription)")
            }
        }

        Log.speech.info("SpeechAnalyzer started for \(resolvedLocale.identifier)")
        return chunks
    }

    func feed(_ chunk: AudioChunk) async {
        inputContinuation?.yield(AnalyzerInput(buffer: chunk.buffer))
    }

    func finish() async {
        // Closing the continuation ends the inputStream, which unblocks analyzeSequence().
        Log.speech.info("engine.finish: closing inputContinuation")
        inputContinuation?.finish()
        inputContinuation = nil

        // Wait for analyzeSequence + finalizeAndFinish (or cancelAndFinishNow) to complete
        // before tearing down, so the results task sees a proper end of the analysis session.
        Log.speech.info("engine.finish: awaiting analyzerTask")
        await analyzerTask?.value
        Log.speech.info("engine.finish: analyzerTask done")
        analyzerTask = nil

        // Cancel the results task AFTER the analysis session has ended. In the normal case
        // transcriber.results has already terminated and cancel is a no-op. In the degenerate
        // case (analyzeSequence returned nil, i.e. zero audio processed) cancelAndFinishNow()
        // completes but transcriber.results never signals EOF, so we cancel here to unblock
        // the for-try-await in resultsTask, which then falls into the CancellationError catch
        // and closes chunkContinuation normally so consumeTask can exit.
        resultsTask?.cancel()
        resultsTask = nil

        analyzer = nil
        transcriber = nil
    }

    // MARK: - Result accumulation

    /// Folds one result into the running transcript and returns the full text to display.
    ///
    /// Final results are committed; a volatile result is shown appended to the committed
    /// text but never stored, so the next revision replaces it cleanly.
    private func absorb(_ result: SpeechTranscriber.Result) -> String {
        let text = String(result.text.characters)
        guard result.isFinal else {
            return (finalizedText + text).trimmingCharacters(in: .whitespaces)
        }
        finalizedText += text
        return finalizedText.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Setup helpers

    /// The dictionary's words, handed to the analyzer as contextual strings.
    ///
    /// Reads the store on the main actor because that's where it lives; the resulting array
    /// of strings is plain value data and crosses back safely.
    /// - Returns: nil when the dictionary is empty, so an empty context is never set for
    ///   nothing.
    ///
    /// Hops to the main actor rather than asserting it. The store is main-actor isolated and
    /// this runs on the engine's own executor — `MainActor.assumeIsolated` here doesn't check
    /// that claim, it asserts it, and takes the whole process down when it's false.
    private static func context() async -> AnalysisContext? {
        let phrases = await MainActor.run { DictionaryStore.shared.biasPhrases }
        guard !phrases.isEmpty else { return nil }

        let context = AnalysisContext()
        context.contextualStrings[.general] = phrases
        Log.speech.info("biasing with \(phrases.count, privacy: .public) dictionary phrase(s)")
        return context
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            // `.volatileResults` is what makes live text appear while you're still talking.
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    private static func ensureModelInstalled(for transcriber: SpeechTranscriber) async throws {
        let installed = await SpeechTranscriber.installedLocales
        let selected = transcriber.selectedLocales
        let alreadyThere = selected.allSatisfy { locale in
            installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
        }
        guard !alreadyThere else { return }

        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                Log.speech.info("downloading speech model…")
                try await request.downloadAndInstall()
                Log.speech.info("speech model installed")
            }
        } catch {
            throw TranscriptionError.modelInstallFailed(error.localizedDescription)
        }
    }
}
