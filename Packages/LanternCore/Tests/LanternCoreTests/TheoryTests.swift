import Foundation
import Testing

@testable import LanternCore

@Suite("Theory")
struct TheoryTests {

    @Test("Standard tuning sits on the published open-string frequencies")
    func standardTuningFrequencies() {
        let expected: [Double] = [82.4069, 110, 146.8324, 195.9977, 246.9417, 329.6276]
        for (string, frequency) in zip(Tuning.standard.strings, expected) {
            #expect(abs(string.frequency() - frequency) < 0.001, "\(string.label) was \(string.frequency())")
        }
    }

    @Test("A4 is the reference")
    func a4IsTheReference() throws {
        #expect(try #require(Note("A4")).frequency() == 440)
        #expect(try #require(Note("A4")).midi == 69)
    }

    @Test("Note names parse", arguments: [("E2", 40), ("A#3", 58), ("Bb3", 58), ("C4", 60), ("C-1", 0), ("g3", 55)])
    func noteNamesParse(name: String, midi: Int) throws {
        #expect(try #require(Note(name)).midi == midi)
    }

    @Test("Nonsense note names are refused", arguments: ["", "H2", "E", "##4", "E#x"])
    func badNoteNamesAreRefused(name: String) {
        #expect(Note(name) == nil)
    }

    @Test("Octave numbering follows scientific pitch notation")
    func octaveNumbering() {
        #expect(Note(midi: 60).octave == 4)
        #expect(Note(midi: 59).octave == 3)
        #expect(Note(midi: 0).octave == -1)
        #expect(Note(midi: 60).name() == "C4")
        #expect(Note(midi: 58).name(style: .flats) == "Bb3")
    }

    @Test("Cents are logarithmic and symmetric")
    func centsMath() {
        #expect(Cents.between(frequency: 440, reference: 440) == 0)
        #expect(abs(Cents.between(frequency: 880, reference: 440) - 1200) < 1e-9)
        #expect(abs(Cents.between(frequency: 220, reference: 440) + 1200) < 1e-9)

        let detuned = Cents.detune(440, by: 17)
        #expect(abs(Cents.between(frequency: detuned, reference: 440) - 17) < 1e-9)
    }

    @Test("Auto mode picks the nearest string in cents, not hertz")
    func nearestStringSelection() throws {
        let tuning = Tuning.standard
        #expect(try #require(tuning.nearestString(to: 83)).index == 0)
        #expect(try #require(tuning.nearestString(to: 110.5)).index == 1)
        #expect(try #require(tuning.nearestString(to: 330)).index == 5)
        // Exactly between D3 and G3 in cents; either neighbour is defensible, but not a far one.
        let middle = try #require(tuning.nearestString(to: sqrt(146.8324 * 195.9977)))
        #expect([2, 3].contains(middle.index))
    }

    @Test("Alternate tunings are spelled correctly")
    func alternateTunings() {
        #expect(Tuning.dropD.strings[0].note == Note(midi: 38))
        #expect(Tuning.dropD.strings[5].note == Tuning.standard.strings[5].note)
        #expect(Tuning.dadgad.strings.map(\.note.pitchClass.value) == [2, 9, 2, 7, 9, 2])
        for (flat, standard) in zip(Tuning.ebStandard.strings, Tuning.standard.strings) {
            #expect(flat.note.midi == standard.note.midi - 1)
        }
    }

    @Test("Concert pitch moves every string together")
    func referenceShiftsEverything() {
        let reference = TuningReference(a4: 432)
        for string in Tuning.standard.strings {
            let shift = Cents.between(
                frequency: string.frequency(reference: reference),
                reference: string.frequency()
            )
            #expect(abs(shift - Cents.between(frequency: 432, reference: 440)) < 1e-9)
        }
    }

    @Test("Chord symbols parse root, quality and bass")
    func chordParsing() throws {
        let chord = try #require(ChordSymbol("F#m7"))
        #expect(chord.root == PitchClass(6))
        #expect(chord.quality == "m7")
        #expect(chord.bass == nil)

        let slash = try #require(ChordSymbol("Bb/D"))
        #expect(slash.root == PitchClass(10))
        #expect(slash.bass == PitchClass(2))
        #expect(slash.quality == "")
    }

    @Test("Unusual qualities survive a transpose round trip")
    func chordTransposition() throws {
        let chord = try #require(ChordSymbol("Csus4add9"))
        #expect(chord.transposed(by: 2).text() == "Dsus4add9")
        #expect(chord.transposed(by: 12).text() == chord.text())

        let slash = try #require(ChordSymbol("Bb/D"))
        #expect(slash.transposed(by: 2).text(style: .flats) == "C/E")
    }

    @Test("Nonsense chord symbols are refused", arguments: ["", "H", "/G", "7"])
    func badChordsAreRefused(text: String) {
        #expect(ChordSymbol(text) == nil)
    }

    @Test("Capo moves the shapes, transpose moves the key")
    func capoAndTransposeAreSeparateNumbers() throws {
        let c = PitchClass(0)

        // Written in C, wanting to hear D, with a capo on 2: play the C shapes you already know.
        let up = CapoTransposition(capoFret: 2, transpose: 2)
        #expect(up.soundingKey(original: c) == PitchClass(2))
        #expect(up.shapeKey(original: c) == c)

        // Capo alone doesn't change the key, only what your hands do.
        let capoOnly = CapoTransposition(capoFret: 3)
        #expect(capoOnly.soundingKey(original: c) == c)
        #expect(capoOnly.shapeKey(original: c) == PitchClass(9))

        let chord = try #require(ChordSymbol("Am7"))
        #expect(up.soundingChord(chord).text() == "Bm7")
        #expect(up.shapeChord(chord).text() == "Am7")
        #expect(CapoTransposition().isIdentity)
    }
}
