import Foundation

/// The capo/transpose control, which shows two numbers at once: the shapes the player fingers
/// and the key the room hears.
///
/// `transpose` moves the music itself; `capoFret` moves only the fingering, because the capo
/// raises whatever is played above it. So the sounding key ignores the capo, and the shapes come
/// out a capo's worth lower.
public struct CapoTransposition: Hashable, Sendable {
    public var capoFret: Int
    public var transpose: Int

    public init(capoFret: Int = 0, transpose: Int = 0) {
        self.capoFret = capoFret
        self.transpose = transpose
    }

    public var isIdentity: Bool { capoFret == 0 && transpose == 0 }

    /// What the listener hears for a chart originally written in `original`.
    public func soundingKey(original: PitchClass) -> PitchClass {
        original + transpose
    }

    /// The shapes the player actually fingers.
    public func shapeKey(original: PitchClass) -> PitchClass {
        original + transpose - capoFret
    }

    public func soundingChord(_ chord: ChordSymbol) -> ChordSymbol {
        chord.transposed(by: transpose)
    }

    public func shapeChord(_ chord: ChordSymbol) -> ChordSymbol {
        chord.transposed(by: transpose - capoFret)
    }
}
