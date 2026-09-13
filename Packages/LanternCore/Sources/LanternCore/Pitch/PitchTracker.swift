import Foundation

/// Which string the tuner is judging against.
public enum TunerTarget: Hashable, Sendable {
    /// Snap to whichever string of the current tuning is nearest.
    case auto
    /// Judge against one string, by index into the tuning.
    case string(Int)
}

public struct TunerReading: Hashable, Sendable {
    /// This frame's raw YIN estimate.
    public let frequency: Double
    /// The median-then-EMA value the UI should draw.
    public let smoothedFrequency: Double
    public let string: InstrumentString?
    public let cents: Double
    public let state: TuningLockState
    public let clarity: Double

    public init(
        frequency: Double,
        smoothedFrequency: Double,
        string: InstrumentString?,
        cents: Double,
        state: TuningLockState,
        clarity: Double
    ) {
        self.frequency = frequency
        self.smoothedFrequency = smoothedFrequency
        self.string = string
        self.cents = cents
        self.state = state
        self.clarity = clarity
    }
}

/// Turns a stream of analysis frames into something steady enough to put on screen: gates the
/// attack transient, medians out octave flips and outliers, then eases the result with an EMA.
///
/// Not thread-safe; owned by the audio tap alongside its detector.
public final class PitchTracker {

    public struct Configuration: Hashable, Sendable {
        public var sampleRate: Double
        /// Samples between consecutive frames; sets the frame rate of the whole tracker.
        public var hopSize: Int
        public var medianWindow: Int
        public var emaAlpha: Double
        /// How long to stay quiet after an onset while the attack transient settles.
        public var onsetHoldSeconds: Double
        /// An RMS jump by this factor counts as a new note.
        public var onsetRiseRatio: Double

        public init(
            sampleRate: Double = 44100,
            hopSize: Int = 1024,
            medianWindow: Int = 5,
            emaAlpha: Double = 0.45,
            onsetHoldSeconds: Double = 0.1,
            onsetRiseRatio: Double = 2.5
        ) {
            self.sampleRate = sampleRate
            self.hopSize = hopSize
            self.medianWindow = medianWindow
            self.emaAlpha = emaAlpha
            self.onsetHoldSeconds = onsetHoldSeconds
            self.onsetRiseRatio = onsetRiseRatio
        }
    }

    public var tuning: Tuning
    public var target: TunerTarget
    public var reference: TuningReference

    public let configuration: Configuration

    private let detector: YINDetector
    private var lock: TuningLockMachine
    /// Recent estimates held as cents from A4, so the median and EMA work in a linear pitch space.
    private var history: [Double] = []
    private var smoothed: Double?
    private var previousRMS: Double = 0
    private var onsetFramesRemaining = 0

    public var frameDuration: Double {
        Double(configuration.hopSize) / configuration.sampleRate
    }

    public init(
        detector: YINDetector = YINDetector(),
        configuration: Configuration = Configuration(),
        lock: TuningLockMachine = TuningLockMachine(),
        tuning: Tuning = .standard,
        target: TunerTarget = .auto,
        reference: TuningReference = .standard
    ) {
        self.detector = detector
        self.configuration = configuration
        self.lock = lock
        self.tuning = tuning
        self.target = target
        self.reference = reference
    }

    public func reset() {
        history.removeAll()
        smoothed = nil
        previousRMS = 0
        onsetFramesRemaining = 0
        lock.reset()
    }

    /// Feeds one frame. Returns nil while the frame is silent, unpitched, or inside the
    /// post-onset hold.
    public func process(frame: [Float]) -> TunerReading? {
        guard let observation = detector.detect(frame) else {
            previousRMS = 0
            return nil
        }

        // A jump out of silence is itself an onset, which is why previousRMS resets to zero above.
        if previousRMS == 0 || observation.rms > previousRMS * configuration.onsetRiseRatio {
            onsetFramesRemaining = Int((configuration.onsetHoldSeconds / frameDuration).rounded(.up))
            history.removeAll()
            smoothed = nil
        }
        previousRMS = observation.rms

        if onsetFramesRemaining > 0 {
            onsetFramesRemaining -= 1
            return nil
        }

        let cents = Cents.between(frequency: observation.frequency, reference: reference.a4)
        history.append(cents)
        if history.count > configuration.medianWindow {
            history.removeFirst()
        }

        let median = history.sorted()[history.count / 2]
        let eased = smoothed.map { $0 + configuration.emaAlpha * (median - $0) } ?? median
        smoothed = eased

        let smoothedFrequency = Cents.detune(reference.a4, by: eased)
        let string = resolveString(for: smoothedFrequency)
        let centsFromTarget = string.map {
            Cents.between(frequency: smoothedFrequency, reference: $0.frequency(reference: reference))
        } ?? 0

        return TunerReading(
            frequency: observation.frequency,
            smoothedFrequency: smoothedFrequency,
            string: string,
            cents: centsFromTarget,
            state: lock.update(cents: centsFromTarget, frameDuration: frameDuration),
            clarity: observation.clarity
        )
    }

    private func resolveString(for frequency: Double) -> InstrumentString? {
        switch target {
        case .auto:
            return tuning.nearestString(to: frequency, reference: reference)
        case .string(let index):
            return tuning.strings.indices.contains(index) ? tuning.strings[index] : nil
        }
    }
}
