import Foundation
import Testing

@testable import LanternCore

@Suite("Tuning lock")
struct TuningLockMachineTests {
    private let frame = 1024.0 / 44100  // ~23.2 ms, one hop at the default settings

    @Test("Green needs six accurate frames in a row")
    func inTuneNeedsASustainedRun() {
        var machine = TuningLockMachine()
        for _ in 0..<5 {
            #expect(machine.update(cents: 1, frameDuration: frame) == .close)
        }
        #expect(machine.update(cents: 1, frameDuration: frame) == .inTune)
    }

    @Test("A single bad frame restarts the run")
    func oneBadFrameResetsTheRun() {
        var machine = TuningLockMachine()
        for _ in 0..<5 { machine.update(cents: 1, frameDuration: frame) }
        #expect(machine.update(cents: 9, frameDuration: frame) == .close)
        for _ in 0..<5 {
            #expect(machine.update(cents: 1, frameDuration: frame) == .close)
        }
        #expect(machine.update(cents: 1, frameDuration: frame) == .inTune)
    }

    @Test("Green holds through a brief wobble and lets go after 400 ms")
    func releaseIsHeldOff() {
        var machine = TuningLockMachine()
        for _ in 0..<6 { machine.update(cents: 0, frameDuration: frame) }
        #expect(machine.state == .inTune)

        for _ in 0..<10 { machine.update(cents: 8, frameDuration: frame) }  // ~232 ms
        #expect(machine.state == .inTune)

        for _ in 0..<8 { machine.update(cents: 8, frameDuration: frame) }  // past 400 ms
        #expect(machine.state == .close)
    }

    @Test("Drifting inside the release band never drops the lamp")
    func smallDriftDoesNotRelease() {
        var machine = TuningLockMachine()
        for _ in 0..<6 { machine.update(cents: 0, frameDuration: frame) }
        for _ in 0..<100 { machine.update(cents: 4, frameDuration: frame) }
        #expect(machine.state == .inTune)
    }

    @Test("A wobble that keeps returning to true never releases either")
    func intermittentDriftDoesNotRelease() {
        var machine = TuningLockMachine()
        for _ in 0..<6 { machine.update(cents: 0, frameDuration: frame) }
        for step in 0..<100 {
            machine.update(cents: step.isMultiple(of: 4) ? 1 : 9, frameDuration: frame)
        }
        #expect(machine.state == .inTune)
    }

    @Test("Red, amber and green fall on the spec's boundaries")
    func stateBoundaries() {
        var machine = TuningLockMachine()
        #expect(machine.update(cents: -40, frameDuration: frame) == .far)
        #expect(machine.update(cents: -16, frameDuration: frame) == .far)
        #expect(machine.update(cents: -15, frameDuration: frame) == .close)
        #expect(machine.update(cents: 10, frameDuration: frame) == .close)

        machine.reset()
        #expect(machine.state == .far)
    }
}

@Suite("Pitch tracker")
struct PitchTrackerTests {

    private func frames(_ samples: [Float], size: Int, hop: Int) -> [[Float]] {
        guard samples.count >= size else { return [] }
        return stride(from: 0, through: samples.count - size, by: hop).map {
            Array(samples[$0..<($0 + size)])
        }
    }

    private func readings(
        frequency: Double,
        seconds: Double = 1,
        configure: (PitchTracker) -> Void = { _ in }
    ) -> [TunerReading] {
        let detector = YINDetector()
        let tracker = PitchTracker(detector: detector)
        configure(tracker)

        let samples = TestSignal.pluck(frequency: frequency, count: Int(44100 * seconds))
        return frames(samples, size: detector.configuration.frameSize, hop: tracker.configuration.hopSize)
            .compactMap { tracker.process(frame: $0) }
    }

    @Test("A plucked low E settles on the right string and locks green")
    func settlesAndLocks() throws {
        let target = Tuning.standard.strings[0].frequency()
        let reading = try #require(readings(frequency: target).last)

        #expect(reading.string?.index == 0)
        #expect(abs(reading.cents) <= 1, "settled \(reading.cents)¢ off")
        #expect(reading.state == .inTune)
    }

    @Test("Every open string settles within a cent", arguments: Tuning.standard.strings)
    func everyStringSettles(string: InstrumentString) throws {
        let reading = try #require(readings(frequency: string.frequency()).last)
        #expect(reading.string?.index == string.index)
        #expect(abs(reading.cents) <= 1, "\(string.label) settled \(reading.cents)¢ off")
    }

    @Test("How far off the string is drives the lamp")
    func lampFollowsDistanceFromTheString() throws {
        let string = Tuning.standard.strings[2]

        let green = try #require(readings(frequency: string.frequency()).last)
        #expect(green.state == .inTune)

        // Ten cents flat is inside the amber band...
        let amber = try #require(readings(frequency: Cents.detune(string.frequency(), by: -10)).last)
        #expect(amber.string?.index == 2)
        #expect(abs(amber.cents - -10) <= 1, "read \(amber.cents)¢")
        #expect(amber.state == .close)

        // ...and twenty is past it, so the lamp goes red.
        let red = try #require(readings(frequency: Cents.detune(string.frequency(), by: -20)).last)
        #expect(red.string?.index == 2)
        #expect(abs(red.cents - -20) <= 1, "read \(red.cents)¢")
        #expect(red.state == .far)
    }

    @Test("The attack transient is suppressed")
    func onsetIsSuppressed() throws {
        let detector = YINDetector()
        let tracker = PitchTracker(detector: detector)
        let samples = TestSignal.pluck(frequency: 110, count: detector.configuration.frameSize * 4)
        let all = frames(samples, size: detector.configuration.frameSize, hop: tracker.configuration.hopSize)
        try #require(all.count > 5)

        // ~100 ms at a 1024-sample hop is five frames held back before anything is reported.
        #expect(all.prefix(5).allSatisfy { tracker.process(frame: $0) == nil })
        #expect(tracker.process(frame: all[5]) != nil)
    }

    @Test("Silence produces no reading")
    func silenceIsIgnored() {
        let detector = YINDetector()
        let tracker = PitchTracker(detector: detector)
        let silence = [Float](repeating: 0, count: detector.configuration.frameSize)

        #expect(tracker.process(frame: silence) == nil)
        #expect(tracker.process(frame: silence) == nil)
    }

    @Test("Targeting a string overrides auto selection")
    func explicitTargetOverridesAuto() throws {
        // Sounding an A against the low E target: five semitones, so 500 cents sharp, and red.
        let reading = try #require(
            readings(frequency: 110) { $0.target = .string(0) }.last
        )

        #expect(reading.string?.index == 0)
        #expect(abs(reading.cents - 500) <= 1, "read \(reading.cents)¢")
        #expect(reading.state == .far)
    }

    @Test("Alternate tunings drive the string row")
    func alternateTuningChangesTheTarget() throws {
        let target = Tuning.dropD.strings[0].frequency()
        let reading = try #require(
            readings(frequency: target) { $0.tuning = .dropD }.last
        )

        #expect(reading.string?.index == 0)
        #expect(reading.string?.label == "D")
        #expect(abs(reading.cents) <= 1)
    }

    @Test("Smoothing rides over a single bad frame")
    func medianRejectsAnOutlier() throws {
        let detector = YINDetector()
        let tracker = PitchTracker(detector: detector)
        let target = Tuning.standard.strings[1].frequency()

        let steady = TestSignal.pluck(frequency: target, count: 44100)
        var all = frames(steady, size: detector.configuration.frameSize, hop: tracker.configuration.hopSize)
        // Drop an octave-error frame into the middle of an otherwise clean note.
        all[20] = TestSignal.sine(frequency: target * 2, count: detector.configuration.frameSize)

        let results = all.compactMap { tracker.process(frame: $0) }
        let afterGlitch = try #require(results.dropFirst(20).first)
        #expect(abs(afterGlitch.cents) <= 15, "one bad frame moved the display \(afterGlitch.cents)¢")
    }

    @Test("Reset clears the lock")
    func resetClearsState() throws {
        let detector = YINDetector()
        let tracker = PitchTracker(detector: detector)
        let target = Tuning.standard.strings[0].frequency()
        let samples = TestSignal.pluck(frequency: target, count: 44100)

        let all = frames(samples, size: detector.configuration.frameSize, hop: tracker.configuration.hopSize)
        for frame in all { _ = tracker.process(frame: frame) }
        tracker.reset()

        #expect(tracker.process(frame: all[0]) == nil)
    }
}
