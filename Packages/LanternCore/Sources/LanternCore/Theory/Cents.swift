import Foundation

public enum Cents {
    /// Interval from `reference` up to `frequency`, in cents. Positive is sharp.
    public static func between(frequency: Double, reference: Double) -> Double {
        guard frequency > 0, reference > 0 else { return 0 }
        return 1200 * log2(frequency / reference)
    }

    /// Shifts a frequency by a cent offset.
    public static func detune(_ frequency: Double, by cents: Double) -> Double {
        frequency * pow(2, cents / 1200)
    }
}
