import Foundation

/// A chord symbol such as `C`, `F#m7`, or `Bb/D`.
///
/// The quality text is kept verbatim rather than parsed into an interval set: charts are display
/// material, and preserving what the writer typed means a transpose round trip never rewrites
/// someone's `sus4add9` into something it thinks is equivalent.
public struct ChordSymbol: Hashable, Sendable, CustomStringConvertible {
    public let root: PitchClass
    public let quality: String
    public let bass: PitchClass?

    public init(root: PitchClass, quality: String = "", bass: PitchClass? = nil) {
        self.root = root
        self.quality = quality
        self.bass = bass
    }

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let (root, consumed) = PitchClass.parse(Substring(trimmed)) else { return nil }

        var remainder = trimmed.dropFirst(consumed)
        var bass: PitchClass?
        if let slash = remainder.firstIndex(of: "/") {
            let bassText = remainder[remainder.index(after: slash)...]
            guard let parsed = PitchClass.parse(bassText), parsed.consumed == bassText.count else { return nil }
            bass = parsed.pitchClass
            remainder = remainder[..<slash]
        }

        self.init(root: root, quality: String(remainder), bass: bass)
    }

    public func transposed(by semitones: Int) -> ChordSymbol {
        ChordSymbol(root: root + semitones, quality: quality, bass: bass.map { $0 + semitones })
    }

    public func text(style: AccidentalStyle = .sharps) -> String {
        var text = root.name(style: style) + quality
        if let bass {
            text += "/" + bass.name(style: style)
        }
        return text
    }

    public var description: String { text() }
}
