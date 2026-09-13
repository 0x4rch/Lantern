import Foundation

/// Preferred spelling for accidentals when rendering note and chord names.
public enum AccidentalStyle: String, Sendable, CaseIterable {
    case sharps
    case flats
}

/// One of the twelve pitch classes, where 0 is C.
public struct PitchClass: Hashable, Sendable, CustomStringConvertible {
    public let value: Int

    public init(_ value: Int) {
        self.value = ((value % 12) + 12) % 12
    }

    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    public func name(style: AccidentalStyle = .sharps) -> String {
        style == .sharps ? Self.sharpNames[value] : Self.flatNames[value]
    }

    public var description: String { name() }

    public static func + (lhs: PitchClass, rhs: Int) -> PitchClass { PitchClass(lhs.value + rhs) }
    public static func - (lhs: PitchClass, rhs: Int) -> PitchClass { PitchClass(lhs.value - rhs) }

    /// Reads a note name off the front of `text` — a letter plus any run of accidentals — and
    /// reports how many characters it consumed, so chord parsing can pick up where it left off.
    public static func parse(_ text: Substring) -> (pitchClass: PitchClass, consumed: Int)? {
        let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let first = text.first,
              let upper = first.uppercased().first,
              let base = letters[upper] else { return nil }

        var semitones = base
        var consumed = 1
        for character in text.dropFirst() {
            switch character {
            case "#", "♯": semitones += 1
            case "b", "♭": semitones -= 1
            default: return (PitchClass(semitones), consumed)
            }
            consumed += 1
        }
        return (PitchClass(semitones), consumed)
    }
}
