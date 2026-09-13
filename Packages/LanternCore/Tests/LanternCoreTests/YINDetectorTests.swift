import Foundation
import Testing

@testable import LanternCore

@Suite("YIN detector")
struct YINDetectorTests {

    @Test("Pure sines read within a cent", arguments: Tuning.standard.strings, TestSignal.detunings)
    func sinesAreAccurate(string: InstrumentString, detune: Double) throws {
        let detector = YINDetector()
        let target = Cents.detune(string.frequency(), by: detune)
        let samples = TestSignal.sine(frequency: target, count: detector.configuration.frameSize)

        let observation = try #require(detector.detect(samples))
        let error = Cents.between(frequency: observation.frequency, reference: target)
        #expect(abs(error) <= 1, "\(string.label) at \(detune)¢ read \(observation.frequency) Hz, off by \(error)¢")
    }

    @Test("Plucked strings read within a cent", arguments: Tuning.standard.strings, TestSignal.detunings)
    func plucksAreAccurate(string: InstrumentString, detune: Double) throws {
        let detector = YINDetector()
        let target = Cents.detune(string.frequency(), by: detune)
        let samples = TestSignal.pluck(frequency: target, count: detector.configuration.frameSize)

        let observation = try #require(detector.detect(samples))
        let error = Cents.between(frequency: observation.frequency, reference: target)
        #expect(abs(error) <= 1, "\(string.label) at \(detune)¢ read \(observation.frequency) Hz, off by \(error)¢")
    }

    @Test("A near-missing fundamental still reads as the low string, not its octave")
    func octaveGuardRecoversTheFundamental() throws {
        let detector = YINDetector()
        let target = Tuning.standard.strings[0].frequency()
        // The classic low-E failure: the second harmonic carries the note and the fundamental is
        // barely there, so the first dip below threshold sits at half the true period.
        let samples = TestSignal.partials(
            fundamental: target,
            amplitudes: [0.15, 1.0, 0.05, 0.5, 0.02, 0.3],
            count: detector.configuration.frameSize
        )

        let observation = try #require(detector.detect(samples))
        let error = Cents.between(frequency: observation.frequency, reference: target)
        #expect(abs(error) <= 1, "read \(observation.frequency) Hz, expected ~\(target) Hz")
    }

    @Test("The octave guard leaves a clean tone alone", arguments: [110.0, 220.0, 440.0, 880.0])
    func octaveGuardDoesNotDragCleanTonesDown(frequency: Double) throws {
        let detector = YINDetector()
        let samples = TestSignal.sine(frequency: frequency, count: detector.configuration.frameSize)

        let observation = try #require(detector.detect(samples))
        let error = Cents.between(frequency: observation.frequency, reference: frequency)
        #expect(abs(error) <= 1, "\(frequency) Hz read as \(observation.frequency) Hz")
    }

    @Test("Both ends of the declared range are reachable", arguments: [60.0, 1200.0])
    func rangeEndpointsAreDetected(frequency: Double) throws {
        let detector = YINDetector()
        let samples = TestSignal.sine(frequency: frequency, count: detector.configuration.frameSize)

        let observation = try #require(detector.detect(samples))
        let error = Cents.between(frequency: observation.frequency, reference: frequency)
        #expect(abs(error) <= 1, "\(frequency) Hz read as \(observation.frequency) Hz")
    }

    @Test("Silence and noise floor produce nothing")
    func quietFramesAreRejected() {
        let detector = YINDetector()
        let size = detector.configuration.frameSize

        #expect(detector.detect([Float](repeating: 0, count: size)) == nil)
        #expect(detector.detect(TestSignal.sine(frequency: 110, count: size, amplitude: 0.0005)) == nil)
    }

    @Test("A short frame is refused rather than read")
    func shortFramesAreRejected() {
        let detector = YINDetector()
        #expect(detector.detect(TestSignal.sine(frequency: 110, count: 512)) == nil)
    }

    @Test("Clarity separates a tone from noise")
    func clarityReflectsPeriodicity() throws {
        let detector = YINDetector()
        let size = detector.configuration.frameSize

        let tone = try #require(detector.detect(TestSignal.sine(frequency: 196, count: size)))
        #expect(tone.clarity > 0.95)

        var generator = LinearCongruential(seed: 7)
        let noise = (0..<size).map { _ in Float(generator.nextUnitInterval() * 2 - 1) * 0.5 }
        if let reading = detector.detect(noise) {
            #expect(reading.clarity < 0.6, "white noise reported clarity \(reading.clarity)")
        }
    }

    @Test("A4 can be moved off 440")
    func alternateConcertPitchIsRespected() throws {
        let reference = TuningReference(a4: 432)
        let detector = YINDetector()
        let target = Tuning.standard.strings[1].frequency(reference: reference)

        let observation = try #require(
            detector.detect(TestSignal.sine(frequency: target, count: detector.configuration.frameSize))
        )
        #expect(abs(Cents.between(frequency: observation.frequency, reference: target)) <= 1)
    }
}
