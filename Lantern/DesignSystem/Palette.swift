import LanternCore
import SwiftUI

/// The palette from the mockups. Near-black ground, cream ink, and the three lamp colours from
/// handoff section 4.
enum Palette {
    static let background = Color(hex: 0x0B0B0D)
    static let panel = Color(hex: 0x16161A)

    static let ink = Color(hex: 0xEDE6D8)
    static let inkDim = Color(hex: 0xCFCBC2)
    static let inkFaint = Color(hex: 0x6E6E76)

    static let far = Color(hex: 0xE5573A)
    static let close = Color(hex: 0xF2B441)
    static let inTune = Color(hex: 0x4BE378)

    static func lamp(_ state: TuningLockState?) -> Color {
        switch state {
        case .far: far
        case .close: close
        case .inTune: inTune
        case nil: inkFaint
        }
    }
}

extension Font {
    /// The big numerals. `.serif` resolves to New York on device, which is the closest thing
    /// on-system to the Fraunces in the mockups.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .light, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
