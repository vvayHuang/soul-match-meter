import SwiftUI

// Design tokens for SM-9000 IR / 靈魂配對測量儀.
// Ported from the design system's tokens/*.css. Values are literal on purpose:
// this is a measurement instrument skin, not a themeable surface.

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum IR {

    // MARK: - Thermal ramp (DATA ONLY — never behind text, never as a text color)

    static let thermal00 = Color(hex: 0x0A1A6E) // 20.0 °C floor
    static let thermal10 = Color(hex: 0x1560B8) // 23.1
    static let thermal20 = Color(hex: 0x2DD4D8) // 26.3
    static let thermal30 = Color(hex: 0x7FD44E) // 29.4
    static let thermal40 = Color(hex: 0xE8F06A) // 32.5
    static let thermal50 = Color(hex: 0xF2F4F8) // 35.6 — ink white, shared with primary
    static let thermal60 = Color(hex: 0xE24A2B) // 38.7
    static let thermal70 = Color(hex: 0xFFF2C8) // 41.8 °C white-hot

    static let rampStops: [Gradient.Stop] = [
        .init(color: thermal00, location: 0.00),
        .init(color: thermal10, location: 0.15),
        .init(color: thermal20, location: 0.30),
        .init(color: thermal30, location: 0.45),
        .init(color: thermal40, location: 0.58),
        .init(color: thermal50, location: 0.70),
        .init(color: thermal60, location: 0.84),
        .init(color: thermal70, location: 1.00),
    ]

    /// Vertical ramp, cold at the bottom — the right-edge palette scale.
    static let rampVertical = LinearGradient(stops: rampStops, startPoint: .bottom, endPoint: .top)
    /// Horizontal ramp — the receipt band, history thumbnails.
    static let rampHorizontal = LinearGradient(stops: rampStops, startPoint: .leading, endPoint: .trailing)
    /// Metric bars and progress: every bar starts at the cold origin and runs to ink white.
    static let track = LinearGradient(colors: [thermal20, thermal50], startPoint: .leading, endPoint: .trailing)

    // MARK: - Plates (the only legal ground for text)

    static let plate = Color(hex: 0x12151B, alpha: 0.88)
    static let plateTranslucent = Color(hex: 0x12151B, alpha: 0.72)
    static let plateScrim = Color(hex: 0x0C0E13, alpha: 0.62)
    static let plateSolid = Color(hex: 0x12151B)
    /// The option rows in the calibration screen sit on a deeper plate.
    static let plateDeep = Color(hex: 0x000000, alpha: 0.82)

    static let onPlate = Color.white
    static let onPlateVariant = Color(hex: 0xD6DAE2)
    static let onPlateMuted = Color(hex: 0xB9BFC9)

    // MARK: - Roles

    static let primary = Color(hex: 0xF2F4F8)
    static let primaryInk = Color(hex: 0x0B0D11)
    static let inverseSurface = Color(hex: 0xF2F4F8) // receipt paper
    static let onInverse = Color.black
    static let onInverseVariant = Color(hex: 0x3A404C)
    static let onInverseMuted = Color(hex: 0x5C6270)

    static let error = Color(hex: 0xFF8272)
    static let outline = Color.white
    static let outlineQuiet = Color(hex: 0x2A2F38)
    static let tearLine = Color(hex: 0x8A919E)

    // MARK: - Spacing (4dp grid, with the two documented off-grid kit values)

    static let screenInset: CGFloat = 14
    static let stackGap: CGFloat = 9
    static let platePadY: CGFloat = 11
    static let platePadX: CGFloat = 13
    static let chipPadY: CGFloat = 5
    static let chipPadX: CGFloat = 9
    static let scaleInset: CGFloat = 12
    static let scaleReserve: CGFloat = 64
    static let touchMin: CGFloat = 44

    // MARK: - Motion

    static let uiCurve = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.26)
    static let uiCurveFast = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.12)
    static let uiCurveSlow = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.52)
    static let pop = Animation.easeOut(duration: 0.35)

    // MARK: - Type
    //
    // No font binaries ship with the design system, so Latin/numerals use the
    // system monospaced face and Chinese uses the system 黑體 (PingFang TC).
    // Swap in JetBrains Mono / Noto Sans TC here if licensed binaries are added.

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static func cjk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - Field presets

/// The three-layer heat field every screen sits on: base gradient, optical
/// subject, scrim, scanlines. Text may never be placed directly on it.
struct FieldPreset {
    let image: String?
    let midStop: Double
    let scrim: Double

    static let boot = FieldPreset(image: nil, midStop: 0.52, scrim: 0)
    static let home = FieldPreset(image: "ir-scene", midStop: 0.46, scrim: 0.28)
    static let serial = FieldPreset(image: "ir-scene-empty", midStop: 0.44, scrim: 0.30)
    static let calibration = FieldPreset(image: "ir-scene-solo", midStop: 0.46, scrim: 0.30)
    static let face = FieldPreset(image: "ir-scene-face", midStop: 0.44, scrim: 0.30)
    static let report = FieldPreset(image: "ir-scene-pair", midStop: 0.44, scrim: 0.30)
    static let settings = FieldPreset(image: "ir-scene-target", midStop: 0.46, scrim: 0.30)
    static let history = FieldPreset(image: "ir-scene-empty", midStop: 0.44, scrim: 0.30)
}
