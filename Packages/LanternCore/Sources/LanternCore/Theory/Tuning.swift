import Foundation

/// One course of the instrument, numbered from the lowest string up.
public struct InstrumentString: Hashable, Sendable, Identifiable {
    public let index: Int
    public let note: Note
    /// What the string row in the UI shows — lowercase marks the high octave, as guitarists write it.
    public let label: String

    public var id: Int { index }

    public init(index: Int, note: Note, label: String) {
        self.index = index
        self.note = note
        self.label = label
    }

    public func frequency(reference: TuningReference = .standard) -> Double {
        note.frequency(reference: reference)
    }
}

public struct Tuning: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let strings: [InstrumentString]

    public init(id: String, name: String, notes: [Note], labels: [String]) {
        precondition(notes.count == labels.count, "every string needs a label")
        self.id = id
        self.name = name
        self.strings = zip(notes, labels).enumerated().map { offset, pair in
            InstrumentString(index: offset, note: pair.0, label: pair.1)
        }
    }

    /// The string whose pitch is closest to `frequency`, measured in cents so the comparison is
    /// even-handed across octaves.
    public func nearestString(to frequency: Double, reference: TuningReference = .standard) -> InstrumentString? {
        guard frequency > 0 else { return nil }
        return strings.min {
            abs(Cents.between(frequency: frequency, reference: $0.frequency(reference: reference)))
                < abs(Cents.between(frequency: frequency, reference: $1.frequency(reference: reference)))
        }
    }
}

private func note(_ name: String) -> Note {
    guard let note = Note(name) else { preconditionFailure("bad note literal: \(name)") }
    return note
}

extension Tuning {
    public static let standard = Tuning(
        id: "standard",
        name: "Standard",
        notes: [note("E2"), note("A2"), note("D3"), note("G3"), note("B3"), note("E4")],
        labels: ["E", "A", "D", "G", "B", "e"]
    )

    public static let dropD = Tuning(
        id: "drop-d",
        name: "Drop D",
        notes: [note("D2"), note("A2"), note("D3"), note("G3"), note("B3"), note("E4")],
        labels: ["D", "A", "D", "G", "B", "e"]
    )

    public static let dadgad = Tuning(
        id: "dadgad",
        name: "DADGAD",
        notes: [note("D2"), note("A2"), note("D3"), note("G3"), note("A3"), note("D4")],
        labels: ["D", "A", "D", "G", "A", "d"]
    )

    public static let ebStandard = Tuning(
        id: "eb-standard",
        name: "E♭ Standard",
        notes: [note("Eb2"), note("Ab2"), note("Db3"), note("Gb3"), note("Bb3"), note("Eb4")],
        labels: ["E♭", "A♭", "D♭", "G♭", "B♭", "e♭"]
    )

    public static let all: [Tuning] = [.standard, .dropD, .dadgad, .ebStandard]
}
