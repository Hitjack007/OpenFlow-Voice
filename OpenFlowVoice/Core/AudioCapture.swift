import AVFoundation
import Accelerate
import Foundation

/// Microphone capture with on-the-fly conversion to whatever format the speech engine wants.
///
/// The tap runs on a real-time audio thread, so everything it touches lives behind
/// `nonisolated(unsafe)` and is only ever mutated from that one thread.
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private nonisolated(unsafe) var converter: AVAudioConverter?
    private nonisolated(unsafe) var outputFormat: AVAudioFormat?
    private var isRunning = false
    private nonisolated(unsafe) var spectrumProcessor: MicSpectrumProcessor?

    /// Called on the audio thread with each converted buffer.
    private nonisolated(unsafe) var onBuffer: (@Sendable (AudioChunk) -> Void)?
    /// Called on the audio thread with 10 per-band mel levels (0…1) for the HUD waveform.
    private nonisolated(unsafe) var onLevel: (@Sendable ([Float]) -> Void)?

    func start(
        outputFormat: AVAudioFormat,
        onBuffer: @escaping @Sendable (AudioChunk) -> Void,
        onLevel: @escaping @Sendable ([Float]) -> Void
    ) throws {
        guard !isRunning else { return }

        self.onBuffer = onBuffer
        self.onLevel = onLevel
        self.outputFormat = outputFormat

        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        let sr = nativeFormat.sampleRate > 0 ? Float(nativeFormat.sampleRate) : 44100
        spectrumProcessor = MicSpectrumProcessor(sampleRate: sr)

        converter = nativeFormat == outputFormat
            ? nil
            : AVAudioConverter(from: nativeFormat, to: outputFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: nativeFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        Log.audio.info("capture started — native \(nativeFormat.sampleRate)Hz → engine \(outputFormat.sampleRate)Hz")
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil
        onBuffer = nil
        onLevel = nil
        spectrumProcessor = nil
        Log.audio.info("capture stopped")
    }

    // MARK: - Audio thread

    private func handle(_ buffer: AVAudioPCMBuffer) {
        if let processor = spectrumProcessor,
           let channel = buffer.floatChannelData?[0] {
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            onLevel?(processor.process(samples: samples))
        }

        guard let outputFormat else { return }

        // AVAudioEngine reuses the tap's buffer as soon as this returns, so the engine
        // must never see it directly — copy when no conversion would otherwise allocate.
        guard let converter else {
            if let copy = Self.copy(buffer) {
                onBuffer?(AudioChunk(buffer: copy))
            }
            return
        }

        // Output frame count scales with the sample-rate ratio; round up so we never clip.
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

        // The input block runs synchronously inside `convert`, on this thread.
        nonisolated(unsafe) let input = buffer
        let consumed = Latch()
        var error: NSError?
        let status = converter.convert(to: converted, error: &error) { _, outStatus in
            guard !consumed.take() else {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            return input
        }

        if let error {
            Log.audio.error("conversion failed: \(error.localizedDescription)")
            return
        }
        guard status != .error, converted.frameLength > 0 else { return }
        onBuffer?(AudioChunk(buffer: converted))
    }

    /// Deep-copies a tap buffer into storage we own.
    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }

        copy.frameLength = buffer.frameLength
        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else if let source = buffer.int32ChannelData, let destination = copy.int32ChannelData {
            for channel in 0..<channels {
                destination[channel].update(from: source[channel], count: frames)
            }
        } else {
            return nil
        }

        return copy
    }

    /// One-shot flag. Only touched from the audio thread inside a synchronous call.
    private final class Latch: @unchecked Sendable {
        private var fired = false
        /// - Returns: the value *before* this call, then latches to `true`.
        func take() -> Bool {
            defer { fired = true }
            return fired
        }
    }
}

// MARK: - Spectrum DSP (audio-thread only; all types are file-private)

private final class MicSpectrumProcessor: @unchecked Sendable {
    static let bandCount = 10
    private static let bufferSize = 1024
    private static let releaseTimes: [Float] = [
        0.120, 0.150, 0.180, 0.250, 0.320,
        0.350, 0.300, 0.250, 0.200, 0.180,
    ]

    private let sampleRate: Float
    private let log2n: vDSP_Length
    private var envelopes: [EnvelopeFollower]
    private let filterbank: MelFilterbank
    private let tilt: SpectralTilt
    private var fftSetup: FFTSetup?
    private let window: [Float]
    // Mic input is much quieter than system audio — calibrate accordingly.
    private let noiseFloor: Float = -80
    private let ceiling: Float = -20

    init(sampleRate: Float) {
        self.sampleRate = sampleRate
        let n = MicSpectrumProcessor.bufferSize
        log2n = vDSP_Length(log2(Double(n)))
        let times = MicSpectrumProcessor.releaseTimes
        envelopes = (0..<MicSpectrumProcessor.bandCount).map { i in
            EnvelopeFollower(releaseTime: i < times.count ? times[i] : 0.220)
        }
        filterbank = MelFilterbank(
            bandCount: MicSpectrumProcessor.bandCount,
            fftBinCount: n / 2,
            sampleRate: sampleRate
        )
        tilt = SpectralTilt(binCount: n / 2, sampleRate: sampleRate)
        var w = [Float](repeating: 0, count: n)
        vDSP_hann_window(&w, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        window = w
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = fftSetup { vDSP_destroy_fftsetup(setup) }
    }

    func process(samples: [Float]) -> [Float] {
        guard let setup = fftSetup else { return [Float](repeating: 0, count: MicSpectrumProcessor.bandCount) }
        let n = MicSpectrumProcessor.bufferSize

        // Zero-pad or use the most recent n samples
        var frame = [Float](repeating: 0, count: n)
        let tail = samples.suffix(n)
        let offset = n - tail.count
        for (i, v) in tail.enumerated() { frame[offset + i] = v }

        // Hann window to reduce spectral leakage
        var windowed = [Float](repeating: 0, count: n)
        vDSP_vmul(frame, 1, window, 1, &windowed, 1, vDSP_Length(n))

        // FFT via Accelerate
        var realParts = [Float](repeating: 0, count: n / 2)
        var imagParts = [Float](repeating: 0, count: n / 2)
        var magnitudes = [Float](repeating: 0, count: n / 2)

        realParts.withUnsafeMutableBufferPointer { realBuf in
            imagParts.withUnsafeMutableBufferPointer { imagBuf in
                windowed.withUnsafeBufferPointer { winBuf in
                    winBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cPtr in
                        var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                        vDSP_ctoz(cPtr, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                var split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

                var scale = Float(1.0) / Float(2 * n)
                vDSP_vsmul(realBuf.baseAddress!, 1, &scale, realBuf.baseAddress!, 1, vDSP_Length(n / 2))
                vDSP_vsmul(imagBuf.baseAddress!, 1, &scale, imagBuf.baseAddress!, 1, vDSP_Length(n / 2))

                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    split = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    vDSP_zvabs(&split, 1, magBuf.baseAddress!, 1, vDSP_Length(n / 2))
                }
            }
        }

        // Spectral tilt (linear domain) then dB conversion + normalize to [0, 1]
        let tilted = tilt.apply(magnitudes: magnitudes)
        var dB = [Float](repeating: 0, count: n / 2)
        var one: Float = 1.0
        vDSP_vdbcon(tilted, 1, &one, &dB, 1, vDSP_Length(n / 2), 1)
        var lo = noiseFloor, hi = ceiling
        vDSP_vclip(dB, 1, &lo, &hi, &dB, 1, vDSP_Length(n / 2))
        let range = ceiling - noiseFloor
        let normalized = dB.map { ($0 - noiseFloor) / range }

        // Mel filterbank collapses 512 bins into bandCount weighted averages
        let melBands = filterbank.apply(magnitudes: normalized)

        // Per-band instant-attack / exponential-release envelope following
        let dt = Float(n) / sampleRate
        var levels = [Float](repeating: 0, count: MicSpectrumProcessor.bandCount)
        for i in 0..<Swift.min(MicSpectrumProcessor.bandCount, melBands.count) {
            levels[i] = envelopes[i].process(input: melBands[i], dt: dt)
        }
        return levels
    }
}

private final class EnvelopeFollower {
    private var envelope: Float = 0
    private let releaseTime: Float

    init(releaseTime: Float) { self.releaseTime = releaseTime }

    func process(input: Float, dt: Float) -> Float {
        if input >= envelope {
            envelope = input
        } else {
            envelope *= Foundation.exp(-dt / releaseTime)
        }
        return envelope
    }
}

private struct MelFilterbank {
    private let weights: [[Float]]

    init(bandCount: Int, fftBinCount: Int, sampleRate: Float, minHz: Float = 80, maxHz: Float = 8000) {
        let minMel = 2595 * log10f(1 + minHz / 700)
        let maxMel = 2595 * log10f(1 + maxHz / 700)

        // bandCount + 2 evenly-spaced mel points (two edge anchors + bandCount centers)
        let melPoints = (0...bandCount + 1).map { i in
            minMel + Float(i) * (maxMel - minMel) / Float(bandCount + 1)
        }
        let hzPoints = melPoints.map { 700 * (powf(10, $0 / 2595) - 1) }
        let binPoints = hzPoints.map { hz in
            Swift.min(Swift.max(0, Int(hz / (sampleRate / 2) * Float(fftBinCount))), fftBinCount - 1)
        }

        var w = [[Float]](repeating: [Float](repeating: 0, count: fftBinCount), count: bandCount)
        for band in 0..<bandCount {
            let lo = binPoints[band], center = binPoints[band + 1], hi = binPoints[band + 2]
            guard lo < hi else { continue }
            for bin in lo..<center {
                let span = Float(center - lo)
                w[band][bin] = span > 0 ? Float(bin - lo) / span : 0
            }
            for bin in center..<hi {
                let span = Float(hi - center)
                w[band][bin] = span > 0 ? Float(hi - bin) / span : 0
            }
            let sum = w[band].reduce(0, +)
            if sum > 0 { w[band] = w[band].map { $0 / sum } }
        }
        weights = w
    }

    func apply(magnitudes: [Float]) -> [Float] {
        weights.map { filter in
            var result: Float = 0
            vDSP_dotpr(filter, 1, magnitudes, 1, &result, vDSP_Length(Swift.min(filter.count, magnitudes.count)))
            return result
        }
    }
}

private struct SpectralTilt {
    private let gains: [Float]

    // Applies a positive high-frequency tilt to counteract the natural 1/f rolloff of speech,
    // so high-frequency bands register visibly instead of being swamped by bass energy.
    init(binCount: Int, sampleRate: Float, tiltAmountDB: Float = 4.5) {
        let nyquist = sampleRate / 2
        let ref = nyquist / 2
        gains = (0..<binCount).map { bin in
            let freq = Float(bin + 1) * nyquist / Float(binCount)
            return powf(10, tiltAmountDB * log10f(freq / ref) / 20)
        }
    }

    func apply(magnitudes: [Float]) -> [Float] {
        var result = [Float](repeating: 0, count: magnitudes.count)
        vDSP_vmul(magnitudes, 1, gains, 1, &result, 1, vDSP_Length(magnitudes.count))
        return result
    }
}
