import AVFAudio
import Foundation
import Synchronization

/// Microphone in, `TunerReading` out.
///
/// Owns the audio graph and the analysis chain so callers never touch either directly. The tap
/// only copies samples into a pending buffer; the actual detection happens on `analysisQueue`, so
/// nothing expensive runs on the audio thread.
///
/// `@unchecked Sendable` because the state it shares across threads is either inside a `Mutex` or
/// confined to `analysisQueue` — see the notes on each property.
public final class TunerEngine: @unchecked Sendable {

    public struct Configuration: Sendable, Hashable {
        public var frameSize: Int
        public var hopSize: Int
        public var minFrequency: Double
        public var maxFrequency: Double

        public init(
            frameSize: Int = 4096,
            hopSize: Int = 1024,
            minFrequency: Double = 60,
            maxFrequency: Double = 1200
        ) {
            self.frameSize = frameSize
            self.hopSize = hopSize
            self.minFrequency = minFrequency
            self.maxFrequency = maxFrequency
        }
    }

    public enum StartError: LocalizedError, Sendable {
        case microphonePermissionDenied
        /// No input route at all. Common on the Simulator when the Mac has no microphone.
        case noAudioInput
        /// The input node reported a format we can't analyse.
        case unusableInputFormat(sampleRate: Double, channelCount: UInt32)

        public var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                "Lantern needs permission to use the microphone."
            case .noAudioInput:
                "No microphone is available for Lantern to listen through."
            case .unusableInputFormat(let sampleRate, let channelCount):
                "The audio input reported a format Lantern can't read "
                    + "(\(Int(sampleRate)) Hz, \(channelCount) channels)."
            }
        }
    }

    private struct Settings {
        var tuning: Tuning
        var target: TunerTarget
        var reference: TuningReference
    }

    public let configuration: Configuration

    private let engine = AVAudioEngine()

    /// Written by the audio thread, drained by `analysisQueue`.
    private let pending = Mutex<[Float]>([])
    /// Read by `analysisQueue`, written by whoever changes the tuning or target.
    private let settings: Mutex<Settings>
    private let isRunning = Mutex(false)

    private let analysisQueue = DispatchQueue(label: "dev.noinfo.Lantern.tuner-analysis", qos: .userInitiated)

    /// Both confined to `analysisQueue` after `start` hands them over.
    private var tracker: PitchTracker?
    private var onReading: (@Sendable (TunerReading?) -> Void)?

    public init(
        configuration: Configuration = Configuration(),
        tuning: Tuning = .standard,
        target: TunerTarget = .auto,
        reference: TuningReference = .standard
    ) {
        self.configuration = configuration
        self.settings = Mutex(Settings(tuning: tuning, target: target, reference: reference))
    }

    deinit {
        if isRunning.withLock({ $0 }) {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
    }

    // MARK: - Settings, changeable while running

    public var tuning: Tuning {
        get { settings.withLock { $0.tuning } }
        set { settings.withLock { $0.tuning = newValue } }
    }

    public var target: TunerTarget {
        get { settings.withLock { $0.target } }
        set { settings.withLock { $0.target = newValue } }
    }

    public var reference: TuningReference {
        get { settings.withLock { $0.reference } }
        set { settings.withLock { $0.reference = newValue } }
    }

    // MARK: - Lifecycle

    /// Asks for the microphone if needed, then starts listening. `onReading` is called on the main
    /// queue once per hop — with nil when the frame was silent, unpitched, or inside the
    /// post-onset hold.
    public func start(onReading: @escaping @Sendable (TunerReading?) -> Void) async throws {
        guard await MicrophoneAccess.request() else { throw StartError.microphonePermissionDenied }
        guard !isRunning.withLock({ $0 }) else { return }

        try activateSession()

        #if os(iOS)
        guard AVAudioSession.sharedInstance().isInputAvailable else { throw StartError.noAudioInput }
        #endif

        // Read the format only after the session is live; an inactive session reports 0 Hz.
        let format = engine.inputNode.outputFormat(forBus: 0)
        // A zero sample rate means there is no input route, not a format we could work around.
        guard format.sampleRate > 0 else { throw StartError.noAudioInput }
        guard format.channelCount > 0 else {
            throw StartError.unusableInputFormat(
                sampleRate: format.sampleRate,
                channelCount: format.channelCount
            )
        }

        let current = settings.withLock { $0 }
        // The hardware rate is whatever the device gives us — 48 kHz on most iPhones, not the
        // 44.1 kHz the detector defaults to — so both configs are built from it.
        let newTracker = PitchTracker(
            detector: YINDetector(
                configuration: YINDetector.Configuration(
                    sampleRate: format.sampleRate,
                    frameSize: configuration.frameSize,
                    minFrequency: configuration.minFrequency,
                    maxFrequency: configuration.maxFrequency
                )
            ),
            configuration: PitchTracker.Configuration(
                sampleRate: format.sampleRate,
                hopSize: configuration.hopSize
            ),
            tuning: current.tuning,
            target: current.target,
            reference: current.reference
        )

        analysisQueue.sync {
            self.tracker = newTracker
            self.onReading = onReading
        }
        pending.withLock { samples in
            samples.removeAll(keepingCapacity: true)
            samples.reserveCapacity(configuration.frameSize * 4)
        }

        engine.inputNode.installTap(
            onBus: 0,
            bufferSize: AVAudioFrameCount(configuration.hopSize),
            format: format
        ) { [weak self] buffer, _ in
            self?.ingest(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        isRunning.withLock { $0 = true }
    }

    public func stop() {
        guard isRunning.withLock({ $0 }) else { return }
        isRunning.withLock { $0 = false }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        pending.withLock { $0.removeAll(keepingCapacity: true) }
        analysisQueue.async {
            self.tracker?.reset()
            self.onReading = nil
        }
        deactivateSession()
    }

    // MARK: - Audio thread

    private func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        pending.withLock { samples in
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: count))
            // If analysis ever falls behind, stay current rather than working through stale audio.
            let ceiling = configuration.frameSize * 8
            if samples.count > ceiling {
                samples.removeFirst(samples.count - ceiling)
            }
        }
        analysisQueue.async { [weak self] in self?.drain() }
    }

    // MARK: - Analysis queue

    private func drain() {
        guard let tracker else { return }

        let current = settings.withLock { $0 }
        tracker.tuning = current.tuning
        tracker.target = current.target
        tracker.reference = current.reference

        while true {
            let frame: [Float]? = pending.withLock { samples in
                guard samples.count >= configuration.frameSize else { return nil }
                let frame = Array(samples[0..<configuration.frameSize])
                samples.removeFirst(configuration.hopSize)
                return frame
            }
            guard let frame else { return }

            let reading = tracker.process(frame: frame)
            let callback = onReading
            DispatchQueue.main.async { callback?(reading) }
        }
    }

    // MARK: - Session

    private func activateSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        // `.measurement` turns off the input processing chain — AGC and noise suppression both
        // bend pitch, which is the one thing this app can't tolerate.
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        #endif
    }

    private func deactivateSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
