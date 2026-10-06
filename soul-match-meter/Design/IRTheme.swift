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

    /// Metric bars and progress: every bar starts at the cold origin and runs to ink white.
    static let track = LinearGradient(colors: [thermal20, thermal50], startPoint: .leading, endPoint: .trailing)

    // MARK: - Plates (the only legal ground for text)

    static let plate = Color(hex: 0x12151B, alpha: 0.88)
    static let plateTranslucent = Color(hex: 0x12151B, alpha: 0.72)
    static let plateScrim = Color(hex: 0x0C0E13, alpha: 0.62)
    static let plateSolid = Color(hex: 0x12151B)

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

    // Semantic colours, all borrowed from the ramp. Only ever a 3pt marker
    // and text, never a fill.
    static let error = Color(hex: 0xFF8272)
    static let success = Color(hex: 0x7FD44E)
    static let info = Color(hex: 0x2DD4D8)
    static let outline = Color.white
    static let outlineQuiet = Color(hex: 0x2A2F38)

    // MARK: - Spacing (4dp grid, with the two documented off-grid kit values)

    static let screenInset: CGFloat = 14
    static let stackGap: CGFloat = 9
    static let platePadY: CGFloat = 11
    static let platePadX: CGFloat = 13
    static let scaleReserve: CGFloat = 64
    static let touchMin: CGFloat = 44

    // MARK: - Motion
    //
    // --ease-hud is the interface's only curve. --ease-rise is reserved for the
    // question card, --ease-cam for the camera's focus pull.

    static func hud(_ duration: Double) -> Animation { .timingCurve(0.2, 0.7, 0.2, 1, duration: duration) }
    static func easeRise(_ duration: Double) -> Animation { .timingCurve(0.16, 0.72, 0.24, 1, duration: duration) }
    static func easeCam(_ duration: Double) -> Animation { .timingCurve(0.22, 0.62, 0.18, 1, duration: duration) }

    static let durPress = 0.13
    static let durHover = 0.16
    static let durAdvance = 0.26
    static let durLock = 0.52
    static let pressScale: CGFloat = 0.965

    static let uiCurve = hud(0.26)
    static let uiCurveFast = hud(durPress)

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
    /// What fills the optical subject. Every source falls back to `image`
    /// when the camera is unavailable or never produced a frame.
    var source: Source = .still

    enum Source {
        /// `image` only.
        case still
        /// The front camera's simulated thermal feed.
        case live
        /// The frame frozen at the end of the hold.
        case snapshot
        /// A frozen frame handed in, rather than the camera's latest snapshot.
        case frame(CGImage)
        /// Two frozen frames, this phone's over the peer's; a still stands in
        /// for either one that is missing.
        case frames(top: CGImage?, peer: CGImage?, peerStill: String)
    }

    /// Screens on the live feed share one field, drawn under them by ContentView.
    var isLive: Bool {
        switch source {
        case .live: true
        default: false
        }
    }

    static let boot = FieldPreset(image: nil, midStop: 0.52, scrim: 0)
    static let home = FieldPreset(image: "ir-scene", midStop: 0.46, scrim: 0.30, source: .live)
    static let serial = FieldPreset(image: "ir-scene-empty", midStop: 0.44, scrim: 0.30, source: .live)
    static let calibration = FieldPreset(image: "ir-scene-solo", midStop: 0.46, scrim: 0.30, source: .live)
    static let faceLive = FieldPreset(image: "ir-scene-face", midStop: 0.44, scrim: 0.30, source: .live)
    static let receipt = FieldPreset(image: "ir-scene-face", midStop: 0.44, scrim: 0.30, source: .snapshot)
    /// The receipt over a given frozen frame, or its still.
    static func receipt(frame: CGImage?) -> FieldPreset {
        guard let frame else { return receipt }
        return FieldPreset(image: "ir-scene-face", midStop: 0.44, scrim: 0.30, source: .frame(frame))
    }

    /// A report over the pair's frozen frames (see `MeterModel.reportField`).
    static func report(top: CGImage?, peer: CGImage?) -> FieldPreset {
        FieldPreset(
            image: "ir-scene-face", midStop: 0.44, scrim: 0.30,
            source: .frames(top: top, peer: peer, peerStill: "ir-scene-solo")
        )
    }

    static let settings = FieldPreset(image: "ir-scene-target", midStop: 0.46, scrim: 0.30, source: .live)
    static let history = FieldPreset(image: "ir-scene-empty", midStop: 0.44, scrim: 0.30, source: .live)
}
