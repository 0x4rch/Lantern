import Foundation

/// What the lamp shows. The far half of the tented display is a flat fill of this state's colour,
/// so the transitions have to be steady enough that the wall doesn't flicker.
public enum TuningLockState: String, Sendable, CaseIterable {
    /// More than 15 cents out — red.
    case far
    /// Within 15 cents — amber.
    case close
    /// Within 3 cents and holding — green.
    case inTune
}

/// Hysteresis around the in-tune decision: getting in takes a sustained run of accurate frames,
/// and getting out takes a sustained run of inaccurate ones. Without the asymmetry the lamp
/// strobes on every vibrato wobble.
public struct TuningLockMachine: Sendable {

    public struct Configuration: Hashable, Sendable {
        public var closeCents: Double
        public var inTuneCents: Double
        public var inTuneFrames: Int
        public var releaseCents: Double
        public var releaseSeconds: Double

        public init(
            closeCents: Double = 15,
            inTuneCents: Double = 3,
            inTuneFrames: Int = 6,
            releaseCents: Double = 5,
            releaseSeconds: Double = 0.4
        ) {
            self.closeCents = closeCents
            self.inTuneCents = inTuneCents
            self.inTuneFrames = inTuneFrames
            self.releaseCents = releaseCents
            self.releaseSeconds = releaseSeconds
        }
    }

    public let configuration: Configuration
    public private(set) var state: TuningLockState = .far

    private var inTuneRun = 0
    private var offTargetSeconds: Double = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public mutating func reset() {
        state = .far
        inTuneRun = 0
        offTargetSeconds = 0
    }

    /// Advances one analysis frame.
    @discardableResult
    public mutating func update(cents: Double, frameDuration: Double) -> TuningLockState {
        let magnitude = abs(cents)

        if state == .inTune {
            if magnitude > configuration.releaseCents {
                offTargetSeconds += frameDuration
                if offTargetSeconds >= configuration.releaseSeconds {
                    state = magnitude <= configuration.closeCents ? .close : .far
                    inTuneRun = 0
                    offTargetSeconds = 0
                }
            } else {
                offTargetSeconds = 0
            }
            return state
        }

        if magnitude <= configuration.inTuneCents {
            inTuneRun += 1
            if inTuneRun >= configuration.inTuneFrames {
                state = .inTune
                offTargetSeconds = 0
                return state
            }
        } else {
            inTuneRun = 0
        }

        state = magnitude <= configuration.closeCents ? .close : .far
        return state
    }
}
