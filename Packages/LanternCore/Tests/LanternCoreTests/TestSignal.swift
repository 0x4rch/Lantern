import Foundation

/// Deterministic test signals. Partial phases come from a small LCG seeded by the frequency, so a
/// failing case reproduces exactly rather than only on some runs.
enum TestSignal {
    static let sampleRate: Double = 44100

    /// The detunings the handoff calls for: dead on, and ±5 and ±20 cents either side.
    static let detunings: [Double] = [0, -5, 5, -20, 20]

    static func sine(
        frequency: Double,
        count: Int,
        sampleRate: Double = sampleRate,
        amplitude: Double = 0.5,
        startTime: Double = 0
    ) -> [Float] {
        (0..<count).map { index in
            let time = startTime + Double(index) / sampleRate
            return Float(amplitude * sin(2 * .pi * frequency * time))
        }
    }

    /// A sum of partials at fixed relative amplitudes, for building pathological spectra such as a
    /// near-missing fundamental.
    static func partials(
        fundamental: Double,
        amplitudes: [Double],
        count: Int,
        sampleRate: Double = sampleRate,
        startTime: Double = 0
    ) -> [Float] {
        var generator = LinearCongruential(seed: UInt64(fundamental * 100))
        let components: [(frequency: Double, amplitude: Double, phase: Double)] =
            amplitudes.enumerated().compactMap { offset, amplitude in
                let frequency = fundamental * Double(offset + 1)
                guard frequency < sampleRate / 2 else { return nil }
                return (frequency, amplitude, generator.nextUnitInterval() * 2 * .pi)
            }

        return (0..<count).map { index in
            let time = startTime + Double(index) / sampleRate
            let value = components.reduce(0.0) {
                $0 + $1.amplitude * sin(2 * .pi * $1.frequency * time + $1.phase)
            }
            return Float(value * 0.3)
        }
    }

    /// A harmonic-rich plucked string: 1/n partials, each decaying faster than the one below it.
    /// Sampled from `startTime` so the window sits past the attack, where a tuner would read it.
    static func pluck(
        frequency: Double,
        count: Int,
        sampleRate: Double = sampleRate,
        harmonics: Int = 14,
        decaySeconds: Double = 1.8,
        startTime: Double = 0.15
    ) -> [Float] {
        var generator = LinearCongruential(seed: UInt64(frequency * 100))
        let components: [(frequency: Double, amplitude: Double, phase: Double, decay: Double)] =
            (1...harmonics).compactMap { harmonic in
                let partial = frequency * Double(harmonic)
                guard partial < sampleRate / 2 else { return nil }
                return (
                    partial,
                    1 / Double(harmonic),
                    generator.nextUnitInterval() * 2 * .pi,
                    decaySeconds / (1 + 0.25 * Double(harmonic - 1))
                )
            }

        return (0..<count).map { index in
            let time = startTime + Double(index) / sampleRate
            let value = components.reduce(0.0) {
                $0 + $1.amplitude * exp(-time / $1.decay) * sin(2 * .pi * $1.frequency * time + $1.phase)
            }
            return Float(value * 0.35)
        }
    }
}

struct LinearCongruential {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed | 1
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextUnitInterval() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
