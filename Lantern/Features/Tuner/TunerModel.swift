import LanternCore
import Observation
import SwiftUI

@MainActor
@Observable
final class TunerModel {

    /// The reading on screen. Held briefly through silence so the display doesn't blink between
    /// plucks — `nil` only once the player has actually stopped.
    private(set) var reading: TunerReading?
    private(set) var isListening = false
    private(set) var failure: String?

    var tuning: Tuning = .standard {
        didSet { engine.tuning = tuning }
    }

    var target: TunerTarget = .auto {
        didSet { engine.target = target }
    }

    var concertA: Double = 440 {
        didSet { engine.reference = TuningReference(a4: concertA) }
    }

    private let engine = TunerEngine()
    private var silentFrames = 0
    /// `start()` awaits the permission prompt, so `isListening` stays false for as long as the
    /// dialog is up. Without this, the scene becoming active fires a second start that asks for
    /// permission again — and a second ask while one is pending is refused outright.
    private var isStarting = false

    /// About a second at a 1024-sample hop. Long enough to ride out the gap between plucks,
    /// short enough that walking away clears the display.
    private let silenceLimit = 45

    func start() async {
        guard !isListening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            try await engine.start { [weak self] reading in
                // TunerEngine delivers on the main queue, so this is already the right actor.
                MainActor.assumeIsolated {
                    self?.receive(reading)
                }
            }
            isListening = true
            failure = nil
        } catch TunerEngine.StartError.microphonePermissionDenied {
            failure = "Lantern needs the microphone to hear your guitar. Turn it on in Settings."
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop() {
        guard isListening else { return }
        engine.stop()
        isListening = false
        reading = nil
        silentFrames = 0
    }

    private func receive(_ incoming: TunerReading?) {
        if let incoming {
            silentFrames = 0
            reading = incoming
        } else {
            silentFrames += 1
            if silentFrames > silenceLimit {
                reading = nil
            }
        }
    }
}
