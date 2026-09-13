import Accelerate
import Foundation

/// YIN fundamental-frequency estimator (de Cheveigné & Kawahara, 2002).
///
/// Implements steps 1–5 of the paper: squared difference function, cumulative mean normalized
/// difference, absolute threshold with local-minimum descent, and parabolic interpolation. Step 6
/// of the paper ("best local estimate") is left out; `PitchTracker` does the equivalent job across
/// frames with a median and an EMA.
///
/// Not thread-safe — it owns scratch buffers and is meant to be owned by the audio tap feeding it.
public final class YINDetector {

    public struct Configuration: Hashable, Sendable {
        /// Sample rate of the incoming frames.
        public var sampleRate: Double
        /// Samples per analysis frame.
        public var frameSize: Int
        public var minFrequency: Double
        public var maxFrequency: Double
        /// Absolute threshold on the cumulative mean normalized difference (paper: 0.1–0.15).
        public var threshold: Float
        /// Frames quieter than this RMS are treated as silence.
        public var rmsFloor: Float
        /// When no dip clears `threshold`, the global minimum is accepted only below this.
        public var maxAperiodicity: Float
        /// The octave below wins only if its dip is this much better, as a ratio of the current one.
        public var octaveGuardRatio: Float
        /// …and better by at least this much in absolute terms, which keeps the guard away from
        /// dips that are already essentially perfect.
        public var octaveGuardMinimumGain: Float

        public init(
            sampleRate: Double = 44100,
            frameSize: Int = 4096,
            minFrequency: Double = 60,
            maxFrequency: Double = 1200,
            threshold: Float = 0.12,
            rmsFloor: Float = 0.003,
            maxAperiodicity: Float = 0.5,
            octaveGuardRatio: Float = 0.6,
            octaveGuardMinimumGain: Float = 0.005
        ) {
            self.sampleRate = sampleRate
            self.frameSize = frameSize
            self.minFrequency = minFrequency
            self.maxFrequency = maxFrequency
            self.threshold = threshold
            self.rmsFloor = rmsFloor
            self.maxAperiodicity = maxAperiodicity
            self.octaveGuardRatio = octaveGuardRatio
            self.octaveGuardMinimumGain = octaveGuardMinimumGain
        }
    }

    public struct Observation: Hashable, Sendable {
        public let frequency: Double
        /// 1 − aperiodicity at the chosen lag. 1 is a perfectly periodic frame.
        public let clarity: Double
        public let rms: Double

        public init(frequency: Double, clarity: Double, rms: Double) {
            self.frequency = frequency
            self.clarity = clarity
            self.rms = rms
        }
    }

    public let configuration: Configuration

    private let minLag: Int
    private let maxLag: Int
    private let windowSize: Int
    private let difference: UnsafeMutablePointer<Float>
    private let normalized: UnsafeMutablePointer<Float>
    private let scratch: UnsafeMutablePointer<Float>

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration

        let highestLag = min(
            configuration.frameSize / 2,
            Int((configuration.sampleRate / configuration.minFrequency).rounded(.up))
        )
        let lowestLag = max(2, Int((configuration.sampleRate / configuration.maxFrequency).rounded(.down)))
        precondition(lowestLag + 1 < highestLag, "frequency range does not fit the frame size")

        minLag = lowestLag
        maxLag = highestLag
        windowSize = configuration.frameSize - highestLag
        precondition(windowSize >= highestLag, "frame is too short for the requested minimum frequency")

        difference = .allocate(capacity: highestLag + 1)
        normalized = .allocate(capacity: highestLag + 1)
        scratch = .allocate(capacity: windowSize)
    }

    deinit {
        difference.deallocate()
        normalized.deallocate()
        scratch.deallocate()
    }

    /// Frequency in hertz for one frame, or nil when the frame is too quiet or too aperiodic to call.
    public func detect(_ samples: [Float]) -> Observation? {
        samples.withUnsafeBufferPointer { detect($0) }
    }

    public func detect(_ samples: UnsafeBufferPointer<Float>) -> Observation? {
        guard let base = samples.baseAddress, samples.count >= configuration.frameSize else { return nil }

        var rms: Float = 0
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(configuration.frameSize))
        guard rms >= configuration.rmsFloor else { return nil }

        computeDifference(base)
        computeNormalizedDifference()

        guard let lag = selectLag() else { return nil }
        let refined = interpolate(around: lag)
        guard refined > 0 else { return nil }

        return Observation(
            frequency: configuration.sampleRate / refined,
            clarity: Double(max(0, min(1, 1 - normalized[lag]))),
            rms: Double(rms)
        )
    }

    // MARK: - YIN steps

    /// d(τ) = Σ (x[j] − x[j+τ])², computed straight rather than via the autocorrelation identity.
    /// The identity form subtracts two nearly equal energies where d(τ) is small, and that
    /// cancellation is exactly where the cent-level precision lives.
    private func computeDifference(_ samples: UnsafePointer<Float>) {
        difference[0] = 0
        let count = vDSP_Length(windowSize)
        for lag in 1...maxLag {
            vDSP_vsub(samples, 1, samples + lag, 1, scratch, 1, count)
            var sum: Float = 0
            vDSP_svesq(scratch, 1, &sum, count)
            difference[lag] = sum
        }
    }

    private func computeNormalizedDifference() {
        normalized[0] = 1
        var running: Float = 0
        for lag in 1...maxLag {
            running += difference[lag]
            normalized[lag] = running > 0 ? difference[lag] * Float(lag) / running : 1
        }
    }

    private func selectLag() -> Int? {
        var chosen: Int?
        var lag = minLag

        while lag <= maxLag {
            if normalized[lag] < configuration.threshold {
                while lag + 1 <= maxLag, normalized[lag + 1] < normalized[lag] { lag += 1 }
                chosen = lag
                break
            }
            lag += 1
        }

        if chosen == nil {
            var best = minLag
            for candidate in minLag...maxLag where normalized[candidate] < normalized[best] { best = candidate }
            guard normalized[best] <= configuration.maxAperiodicity else { return nil }
            chosen = best
        }

        return chosen.map(applyOctaveGuard)
    }

    /// Guards the classic low-E error: a strong second harmonic puts a dip at half the true period
    /// and the smallest-lag rule takes it, reporting 165 Hz for an 82 Hz string.
    ///
    /// The handoff asks to prefer the lower octave when its dip is "within ~0.05" of the chosen
    /// one. Taken literally that also fires on a clean sine — a sine dips just as deeply at 2τ as
    /// at τ — and would drop every pure tone an octave. Instead the lower octave has to be better
    /// both by a ratio and by an absolute margin, so a dip that is already near-perfect is never
    /// second-guessed on numerical noise. See docs/decisions.md.
    private func applyOctaveGuard(_ lag: Int) -> Int {
        var current = lag
        for _ in 0..<2 {
            let doubled = current * 2
            guard doubled <= maxLag else { break }

            // The true period is rarely exactly 2τ: strings are slightly inharmonic and lags are
            // integers, so take the best dip in a narrow band around it.
            let low = max(minLag, Int(Double(doubled) * 0.97))
            let high = min(maxLag, Int((Double(doubled) * 1.03).rounded(.up)))
            guard low <= high else { break }

            var best = low
            for candidate in low...high where normalized[candidate] < normalized[best] { best = candidate }

            guard normalized[best] < configuration.octaveGuardRatio * normalized[current],
                  normalized[current] - normalized[best] >= configuration.octaveGuardMinimumGain
            else { break }

            current = best
        }
        return current
    }

    private func interpolate(around lag: Int) -> Double {
        guard lag > 0, lag < maxLag else { return Double(lag) }
        let before = Double(normalized[lag - 1])
        let at = Double(normalized[lag])
        let after = Double(normalized[lag + 1])

        let denominator = before - 2 * at + after
        guard abs(denominator) > .ulpOfOne else { return Double(lag) }

        let offset = 0.5 * (before - after) / denominator
        return Double(lag) + min(1, max(-1, offset))
    }
}
