import Foundation

/// Concert-pitch reference. `a4` is the frequency of A4 in hertz; the tuner lets the player
/// move it off 440 for playing along with fixed-pitch recordings.
public struct TuningReference: Hashable, Sendable {
    public var a4: Double

    public init(a4: Double = 440) {
        self.a4 = a4
    }

    public static let standard = TuningReference()

    public func frequency(midi: Double) -> Double {
        a4 * pow(2, (midi - 69) / 12)
    }

    public func midi(frequency: Double) -> Double {
        69 + 12 * log2(frequency / a4)
    }
}

/// A pitch in scientific pitch notation, identified by MIDI note number (A4 = 69, middle C = C4).
public struct Note: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let midi: Int

    public init(midi: Int) {
        self.midi = midi
    }

    public init(_ pitchClass: PitchClass, octave: Int) {
        self.midi = (octave + 1) * 12 + pitchClass.value
    }

    /// Parses names like `E2`, `A#3`, `Bb3`.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let (pitchClass, consumed) = PitchClass.parse(Substring(trimmed)) else { return nil }
        guard let octave = Int(trimmed.dropFirst(consumed)) else { return nil }
        self.init(pitchClass, octave: octave)
    }

    public var pitchClass: PitchClass { PitchClass(midi) }

    public var octave: Int {
        Int((Double(midi) / 12).rounded(.down)) - 1
    }

    public func name(style: AccidentalStyle = .sharps) -> String {
        "\(pitchClass.name(style: style))\(octave)"
    }

    public var description: String { name() }

    public func frequency(reference: TuningReference = .standard) -> Double {
        reference.frequency(midi: Double(midi))
    }

    public func transposed(by semitones: Int) -> Note {
        Note(midi: midi + semitones)
    }

    public static func < (lhs: Note, rhs: Note) -> Bool { lhs.midi < rhs.midi }
}
