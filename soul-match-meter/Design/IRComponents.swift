import SwiftUI

// MARK: - Thermal field

/// Scanline + sensor-noise overlay. 1px dark line every 3px, drawn once into a Canvas.
struct ScanlineOverlay: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(0.26))
                )
                context.fill(
                    Path(CGRect(x: 0, y: y + 1, width: size.width, height: 2)),
                    with: .color(.white.opacity(0.015))
                )
                y += 3
            }
        }
        .allowsHitTesting(false)
    }
}

/// The three-layer optical ground. Runs the instrument's focus-pull on appear:
/// the sensor settles from a blurred, over-scaled frame into a locked image.
struct ThermalField: View {
    let preset: FieldPreset
    /// Off for still renders: starts settled, with no focus pull.
    var animated: Bool = true

    @State private var settled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(preset: FieldPreset, animated: Bool = true) {
        self.preset = preset
        self.animated = animated
        _settled = State(initialValue: !animated)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x0A1A6E), location: 0),
                    .init(color: Color(hex: 0x0C2280), location: preset.midStop),
                    .init(color: Color(hex: 0x06103A), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if preset.image != nil {
                GeometryReader { geo in
                    subject
                        .frame(width: geo.size.width * 1.28, height: geo.size.height * 1.28)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .clipped()
                }
                // irCam: shifted, tilted, over-scaled and blown out, then settles.
                .rotationEffect(.degrees(settled ? 0 : 1.6))
                .scaleEffect(settled ? 1 : 1.24)
                .offset(x: settled ? 0 : 42, y: settled ? 0 : 30)
                .blur(radius: settled ? 0 : 13)
                .brightness(settled ? 0 : 0.2)
            }

            Color(hex: 0x04060E).opacity(preset.scrim)

            ScanlineOverlay()
        }
        .ignoresSafeArea()
        .onAppear {
            // Reduced motion lands on the settled frame, as in the design system.
            guard animated, !reduceMotion else {
                settled = true
                return
            }
            settled = false
            withAnimation(IR.easeCam(0.92)) { settled = true }
        }
    }

    @ViewBuilder private var subject: some View {
        switch (preset.source, ThermalCamera.shared.snapshot) {
        case (.live, _):
            LiveThermalImage(fallback: preset.image)
        case (.snapshot, let snapshot?):
            ThermalFrame(image: snapshot)
        case (.frame(let frame), _):
            ThermalFrame(image: frame)
        case (.frames(let top, let peer, let peerStill), _):
            // This phone's reading over the peer's.
            split {
                if let top {
                    ThermalFrame(image: top)
                } else if let image = preset.image {
                    SceneImage(name: image)
                }
            } bottom: {
                if let peer {
                    ThermalFrame(image: peer)
                } else {
                    SceneImage(name: peerStill)
                }
            }
        default:
            if let image = preset.image {
                SceneImage(name: image)
            }
        }
    }

    /// Two halves joined by a 1pt hairline.
    private func split(@ViewBuilder top: () -> some View, @ViewBuilder bottom: () -> some View) -> some View {
        VStack(spacing: 0) {
            fillHalf(top)
            fillHalf(bottom)
                .overlay(alignment: .top) { IR.outlineQuiet.frame(height: 1) }
        }
    }

    /// Takes the proposed size and crops its content to it.
    private func fillHalf(@ViewBuilder _ content: () -> some View) -> some View {
        Color.clear
            .overlay { content() }
            .clipped()
    }
}

/// A sensor-resolution thermal frame, upscaled soft.
private struct ThermalFrame: View {
    let image: CGImage

    var body: some View {
        // Bilinear upscale from sensor resolution gives the soft thermal blobs.
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fill)
    }
}

/// The front camera's simulated thermal feed. Shows the preset's still until
/// the first frame lands, and for good when the camera is denied or missing
/// (e.g. the simulator).
private struct LiveThermalImage: View {
    let fallback: String?

    private var camera: ThermalCamera { .shared }

    var body: some View {
        ZStack {
            if let frame = camera.frame {
                ThermalFrame(image: frame)
            } else if let fallback {
                // Also covers the permission prompt and the first frame's latency.
                // The field outlives the screen, so each screen's still fades in.
                SceneImage(name: fallback)
                    .id(fallback)
                    .transition(.opacity)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.45), trigger: camera.nucTick)
    }
}

// MARK: - Plates and chips

/// An opaque black plate. Depth in this system is plating, never shadow.
struct HudPlate<Content: View>: View {
    var fill: Color = IR.plate
    var padX: CGFloat = IR.platePadX
    var padY: CGFloat = IR.platePadY
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, padX)
            .padding(.vertical, padY)
            .background(fill)
    }
}

/// A readout on a plate. No outline, so never clickable — data only.
struct ReadoutChip: View {
    enum Size {
        case l, m, s, xs

        var points: CGFloat {
            switch self {
            case .l: 17
            case .m: 13
            case .s: 11.5
            case .xs: 10
            }
        }
    }

    enum Tone {
        case ink, hot, muted

        var color: Color {
            switch self {
            case .ink: IR.onPlate
            case .hot: IR.thermal70
            case .muted: IR.onPlateMuted
            }
        }
    }

    let text: String
    var size: Size = .l
    var tone: Tone = .ink
    var boxed = false

    var body: some View {
        let pt = size.points
        Text(text)
            .font(IR.mono(pt))
            .tracking(pt <= 13 ? 1.5 : 0)
            // Line height 1.45 of the mono face's natural ~1.19.
            .lineSpacing(pt * 0.26)
            .foregroundStyle(tone.color)
            .padding(.horizontal, pt >= 17 ? 9 : 8)
            .padding(.vertical, (pt >= 17 ? 5 : 4) + pt * 0.13)
            .background(IR.plate)
            .overlay {
                if boxed {
                    Rectangle().strokeBorder(IR.outline, lineWidth: 1)
                }
            }
    }
}

/// The right-edge palette scale: the ramp itself plus a triangle pointing
/// into it. It stays inside the 64pt scale gutter, so any plate sharing its
/// vertical band must reserve `IR.scaleReserve` on the right.
struct PaletteScale: View {
    let height: CGFloat
    /// 0…100 of the way up the ramp. Nil hides the marker.
    var marker: Double?
    var width: CGFloat = 14

    @Environment(\.thermalPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            if let marker {
                PointerTriangle(direction: .right)
                    .fill(IR.onPlate)
                    .frame(width: 10, height: 12)
                    .padding(.top, max(0, height * (1 - marker / 100) - 6))
                    .animation(IR.hud(0.92), value: marker)
            }
            palette.vertical
                .frame(width: width, height: height)
                .border(Color.black, width: 1)
        }
        .frame(width: IR.scaleReserve, alignment: .topTrailing)
        .accessibilityHidden(true)
    }
}

/// Two bars through a centre square: hollow while searching, white-hot once
/// the reading locks. There is no icon set in this system; HUD glyphs are
/// geometric primitives.
struct Crosshair: View {
    var size: CGFloat = 34
    var locked = false

    private var box: CGFloat { (size * 0.35).rounded() }

    var body: some View {
        ZStack {
            Rectangle().fill(IR.onPlate).frame(width: 2, height: size)
            Rectangle().fill(IR.onPlate).frame(width: size, height: 2)
            Rectangle()
                .fill(locked ? IR.thermal70 : Color.clear)
                .overlay {
                    if !locked {
                        Rectangle().strokeBorder(IR.onPlate, lineWidth: 1)
                    }
                }
                .frame(width: box, height: box)
        }
        .frame(width: size, height: size)
        .animation(IR.hud(IR.durPress), value: locked)
        .accessibilityHidden(true)
    }
}

/// A solid triangle whose tip points the given way.
struct PointerTriangle: Shape {
    enum Direction { case left, right }

    var direction: Direction

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .right:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        case .left:
            p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Controls

/// Press feedback shared by every interactive surface: 0.965 scale plus the
/// design's brightness(1.25). That filter multiplies, so on near-black plates
/// and near-white fills it is only a faint lift.
private struct HudPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? IR.pressScale : 1)
            .animation(IR.hud(IR.durPress), value: configuration.isPressed)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(IR.hud(IR.durHover), value: configuration.isPressed)
    }
}

extension View {
    func hudPress() -> some View { buttonStyle(HudPressStyle()) }
}

enum HudButtonRole {
    /// White-hot fill. One per screen.
    case primary
    /// Outlined translucent plate.
    case secondary
}

/// Text button. Every tappable surface carries a white line; the one primary
/// on a screen is the white-hot fill instead.
struct HudButton: View {
    enum Size {
        /// Full width, 48 (primary) / 46 (secondary) tall.
        case regular
        /// 32 tall and only as wide as its label, with a 44pt touch target.
        case small
    }

    let title: String
    var role: HudButtonRole = .secondary
    var size: Size = .regular
    var disabled = false
    let action: () -> Void

    private var primary: Bool { role == .primary }

    private var fontSize: CGFloat {
        if size == .small { return 12.5 }
        return primary ? 16.5 : 15
    }

    private var height: CGFloat {
        if size == .small { return 32 }
        return primary ? 48 : 46
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(IR.cjk(fontSize, .bold))
                .lineLimit(1)
                .foregroundStyle(primary ? IR.primaryInk : IR.onPlate)
                .padding(.horizontal, size == .small ? 12 : 0)
                .frame(maxWidth: size == .small ? nil : .infinity, minHeight: height)
                .background(primary ? IR.primary : IR.plateTranslucent)
                .overlay {
                    if !primary {
                        Rectangle().strokeBorder(IR.outline, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle().inset(by: size == .small ? -6 : 0))
        }
        .hudPress()
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}

/// A square control drawn from bars and triangles — there is no icon set.
/// `label` is required: it is the only name VoiceOver gets.
struct IconButton: View {
    enum Glyph { case close, back, next, plus, minus, square, crosshair }

    enum Size {
        case lg, md, sm

        var points: CGFloat {
            switch self {
            case .lg: 44
            case .md: 40
            case .sm: 32
            }
        }
    }

    let glyph: Glyph
    let label: String
    var size: Size = .lg
    var role: HudButtonRole = .secondary
    let action: () -> Void

    var body: some View {
        let side = size.points
        let primary = role == .primary
        Button(action: action) {
            IconGlyph(glyph: glyph, box: side - (primary ? 0 : 3), color: primary ? IR.primaryInk : IR.onPlate)
                .frame(width: side, height: side)
                .background(primary ? IR.primary : IR.plateTranslucent)
                .overlay {
                    if !primary {
                        Rectangle().strokeBorder(IR.outline, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle().inset(by: size == .sm ? -6 : 0))
        }
        .hudPress()
        .accessibilityLabel(label)
    }
}

private struct IconGlyph: View {
    let glyph: IconButton.Glyph
    let box: CGFloat
    let color: Color

    var body: some View {
        let g = (box * 0.42).rounded()
        ZStack {
            switch glyph {
            case .plus:
                bar(g, 2)
                bar(2, g)
            case .minus:
                bar(g, 2)
            case .close:
                bar(g, 2).rotationEffect(.degrees(45))
                bar(g, 2).rotationEffect(.degrees(-45))
            case .back, .next:
                PointerTriangle(direction: glyph == .back ? .left : .right)
                    .fill(color)
                    .frame(width: (g * 0.6).rounded(), height: (g * 0.72).rounded())
            case .square:
                Rectangle().fill(color).frame(width: (g * 0.6).rounded(), height: (g * 0.6).rounded())
            case .crosshair:
                bar(2, g + 4)
                bar(g + 4, 2)
            }
        }
        .frame(width: box, height: box)
    }

    private func bar(_ width: CGFloat, _ height: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: width, height: height)
    }
}

/// One hairline thinner than a button. Digits at 16, word keys at 13 with tracking.
struct KeypadKey: View {
    let label: String
    let action: () -> Void

    private var isWord: Bool { label.count > 1 }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(IR.mono(isWord ? 13 : 16))
                .tracking(isWord ? 1.5 : 0)
                .foregroundStyle(IR.onPlate)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(IR.plateTranslucent)
                .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .hudPress()
    }
}

/// Mutually exclusive choices in one white-lined box. The chosen segment
/// flips to white-hot; segments are split by 1pt white lines.
struct SegmentedField<Value: Hashable>: View {
    let options: [Value]
    let selection: Value
    let title: (Value) -> String
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                let on = option == selection
                Button { onSelect(option) } label: {
                    Text(title(option))
                        .font(IR.mono(13))
                        .foregroundStyle(on ? IR.primaryInk : IR.onPlate)
                        .frame(minWidth: 48, minHeight: 36)
                        .background(on ? IR.primary : Color.clear)
                        .overlay(alignment: .leading) {
                            if index > 0 {
                                Rectangle().fill(IR.outline).frame(width: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .animation(IR.hud(IR.durHover), value: selection)
        .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1.5) }
    }
}

/// Not a sliding switch: a square key that flips between a white-hot ON
/// and an OFF on the plate.
struct HudToggle: View {
    let isOn: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button { onToggle(!isOn) } label: {
            Text(isOn ? "ON" : "OFF")
                .font(IR.mono(13))
                .tracking(1.5)
                .foregroundStyle(isOn ? IR.primaryInk : IR.onPlate)
                .frame(width: 74)
                .frame(minHeight: 36)
                .background(isOn ? IR.primary : IR.plateTranslucent)
                .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1.5) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(IR.hud(IR.durHover), value: isOn)
        .accessibilityValue(isOn ? "開啟" : "關閉")
        .accessibilityAddTraits(.isToggle)
    }
}

/// The one circular element in the system, and the only one that grows while
/// held: 156 → 168, with a white-hot ring breathing out behind it.
struct HoldTarget: View {
    let label: String
    let holding: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(IR.cjk(17, .bold))
            .foregroundStyle(IR.onPlate)
            .frame(width: 156, height: 156)
            .background(Circle().fill(IR.plateScrim))
            .overlay(Circle().strokeBorder(IR.outline, lineWidth: 2))
            .scaleEffect(holding ? 1.077 : 1)
            .animation(IR.hud(IR.durPress), value: holding)
            .background {
                if holding {
                    HoldRing()
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        onDown()
                    }
                    .onEnded { _ in
                        pressed = false
                        onUp()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

/// irRing: a 1pt T70 circle 10pt outside the target, swelling and fading
/// every 1.05s. Held still under reduced motion.
private struct HoldRing: View {
    @State private var out = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .strokeBorder(IR.thermal70, lineWidth: 1)
            .frame(width: 176, height: 176)
            .scaleEffect(reduceMotion ? 1 : (out ? 1.25 : 0.88))
            .opacity(reduceMotion ? 1 : (out ? 0 : 0.9))
            .allowsHitTesting(false)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(IR.hud(1.05).repeatForever(autoreverses: false)) { out = true }
            }
    }
}

// MARK: - Data

/// The biggest thing on a screen, one per screen: a mono display number on
/// plate 1, with an optional unit line under it.
struct BigReadout: View {
    enum Size { case l, m }

    let value: String
    var unitLine: String?
    var size: Size = .m
    /// Just the number: no plate, no padding — for composing inside another plate.
    var bare = false

    var body: some View {
        let big = size == .l
        let points: CGFloat = big ? 104 : 62
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(IR.mono(points, .semibold))
                .tracking(big ? -6 : -2)
                .monospacedDigit()
                .foregroundStyle(IR.onPlate)
                // Line height .85 / .92 of the size; the face's own is ~1.19.
                .padding(.vertical, -points * ((big ? 1.19 - 0.85 : 1.19 - 0.92) / 2))

            if let unitLine {
                Text(unitLine)
                    .font(IR.mono(11.5))
                    .tracking(1.5)
                    .foregroundStyle(IR.primary)
            }
        }
        .padding(.horizontal, bare ? 0 : 13)
        .padding(.vertical, bare ? 0 : 12)
        .background(bare ? Color.clear : IR.plate)
    }
}

/// Label in Chinese, value in mono, and a 4pt track that always runs from
/// the cold origin to ink white.
struct MetricBar: View {
    let label: String
    let value: String
    /// 0…1 of the track width.
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(IR.cjk(12.5, .medium))
                    .foregroundStyle(IR.onPlateVariant)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(value)
                    .font(IR.mono(11.5))
                    .tracking(1.5)
                    .foregroundStyle(IR.onPlate)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    IR.outlineQuiet
                    IR.track.frame(width: geo.size.width * amount)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A progress track. Every bar in this system starts at the cold origin.
struct MetricTrack: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                IR.outlineQuiet
                IR.track.frame(width: geo.size.width * progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Feedback

/// A 3pt semantic marker plus one line, both in the tone's colour, on the
/// chassis panel. Never a filled block.
struct HudToast: View {
    enum Tone {
        case log, error, success, info

        var color: Color {
            switch self {
            case .log: IR.onPlate
            case .error: IR.error
            case .success: IR.success
            case .info: IR.info
            }
        }
    }

    var tone: Tone = .log
    let message: String
    var blink = false

    var body: some View {
        Text(message)
            .font(IR.cjk(13, .medium))
            .foregroundStyle(tone.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .padding(.leading, 3)
            .background(IR.plateSolid)
            .overlay(alignment: .leading) {
                Rectangle().fill(tone.color).frame(width: 3)
            }
            .blink(period: tone == .error ? 1 : 1.4, active: blink)
    }
}

/// 1s / 1.4s blinks are the only attention device; there is no spinner.
/// Stepped, not faded: lit for 60% of the period, at .45 for the rest.
struct Blink: ViewModifier {
    let period: Double
    var active = true

    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.45 : 1)
            .task(id: active && !reduceMotion) {
                dim = false
                guard active, !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(period * 0.6))
                    guard !Task.isCancelled else { return }
                    dim = true
                    try? await Task.sleep(for: .seconds(period * 0.4))
                    guard !Task.isCancelled else { return }
                    dim = false
                }
            }
    }
}

extension View {
    func blink(period: Double = 1, active: Bool = true) -> some View {
        modifier(Blink(period: period, active: active))
    }
}

/// A struck-through box plus one mono count — the only empty-state glyph.
struct EmptyState: View {
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .strokeBorder(IR.onPlateMuted, lineWidth: 2)
                .frame(width: 26, height: 26)
                .overlay {
                    Rectangle().fill(IR.onPlateMuted).frame(width: 26, height: 2).offset(x: -2)
                }
                .accessibilityHidden(true)

            Text(label)
                .font(IR.mono(13))
                .tracking(1.5)
                .foregroundStyle(IR.onPlateMuted)
        }
    }
}

/// A question on the chassis panel with a white line, answered by an
/// outlined cancel and a white-hot confirm.
struct ConfirmDialog: View {
    let title: String
    let confirmLabel: String
    var cancelLabel = "留著"
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(IR.cjk(20, .bold))
                .foregroundStyle(IR.onPlate)

            HStack(spacing: 8) {
                Button(action: onCancel) {
                    label(cancelLabel)
                        .foregroundStyle(IR.onPlate)
                        .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1.5) }
                        .contentShape(Rectangle())
                }
                .hudPress()

                Button(action: onConfirm) {
                    label(confirmLabel)
                        .foregroundStyle(IR.primaryInk)
                        .background(IR.primary)
                        .contentShape(Rectangle())
                }
                .hudPress()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IR.plateSolid)
        .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1.5) }
        .accessibilityAddTraits(.isModal)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(IR.cjk(15, .bold))
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

// MARK: - Screen scaffold

/// Every screen is the same box: field behind, insets 14 / safe area, 9pt stack gap.
struct HudScreen<Content: View>: View {
    let preset: FieldPreset
    var gap: CGFloat = IR.stackGap
    /// The hold target owns a drag gesture, so its screen must not scroll.
    var scrollable: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        // The HUD is a fixed instrument face and normally fills the viewfinder
        // exactly. A couple of screens (the receipt, a full history) come within
        // a point or two of the bottom on a 6.3" phone and overrun it on smaller
        // ones, so the stack sits in a scroll view that only engages when the
        // content genuinely does not fit.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: gap) {
                    content
                }
                .padding(.horizontal, IR.screenInset)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .scrollDisabled(!scrollable)
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background {
            // The live feed is drawn once under the screens instead (see ContentView).
            if !preset.isLive {
                ThermalField(preset: preset)
            }
        }
    }
}
