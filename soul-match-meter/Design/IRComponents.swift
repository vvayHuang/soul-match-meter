import SwiftUI

// MARK: - Thermal field

/// Scanline + sensor-noise overlay. 1px dark line every 3px, drawn once into a Canvas.
private struct ScanlineOverlay: View {
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
    var scanlines: Bool = true

    @State private var settled = false

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

            if let image = preset.image {
                GeometryReader { geo in
                    Image(image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width * 1.28, height: geo.size.height * 1.28)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .clipped()
                }
                // Stays well inside the 14% overscan margin on each side.
                .parallax(40)
                .scaleEffect(settled ? 1 : 1.16)
                .blur(radius: settled ? 0 : 11)
                .brightness(settled ? 0 : 0.22)
            }

            Color(hex: 0x04060E).opacity(preset.scrim)

            if scanlines {
                ScanlineOverlay()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            settled = false
            withAnimation(.timingCurve(0.22, 0.62, 0.18, 1, duration: 0.92)) { settled = true }
        }
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

/// A boxed readout. Never clickable — data only.
struct ReadoutChip: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = IR.onPlate
    var tracking: CGFloat = 0

    var body: some View {
        Text(text)
            .font(IR.mono(size))
            .tracking(tracking)
            .foregroundStyle(color)
            .padding(.horizontal, IR.chipPadX)
            .padding(.vertical, IR.chipPadY)
            .background(IR.plate)
    }
}

/// The right-edge palette scale: false-colour legend plus a triangular cursor.
/// Any plate sharing its vertical band must reserve `IR.scaleReserve` on the right.
struct PaletteScale: View {
    let height: CGFloat
    /// 0 = cold floor, 1 = white-hot. Drives the cursor position.
    let position: Double
    var topLabel: String = "40.5 °C"
    var bottomLabel: String = "20.0 °C"
    var animated: Bool = true

    private let cursorHeight: CGFloat = 12

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            ReadoutChip(text: topLabel, size: 11)
                .padding(.horizontal, -2)

            HStack(alignment: .top, spacing: 4) {
                CursorTriangle()
                    .fill(Color.white)
                    .frame(width: 10, height: cursorHeight)
                    .offset(y: (height - cursorHeight) * (1 - position))
                    .animation(animated ? .linear(duration: 0.08) : nil, value: position)

                IR.rampVertical
                    .frame(width: 15, height: height)
                    .border(Color.black, width: 1)
            }
            .frame(height: height, alignment: .top)

            ReadoutChip(text: bottomLabel, size: 11)
                .padding(.horizontal, -2)
        }
    }
}

private struct CursorTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}

/// Two bars plus a false-colour centre square. There is no icon set in this
/// system; HUD glyphs are geometric primitives.
struct Crosshair: View {
    var size: CGFloat = 34
    var bar: CGFloat = 2
    var centre: Color = IR.thermal40

    private var centreSize: CGFloat { size * 12 / 34 }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white).frame(width: bar, height: size)
            Rectangle().fill(Color.white).frame(width: size, height: bar)
            Rectangle().fill(centre).frame(width: centreSize, height: centreSize)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Controls

/// Press feedback shared by every interactive surface: 0.965 scale, brightness lift.
private struct HudPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.13), value: configuration.isPressed)
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

struct HudButton: View {
    let title: String
    var role: HudButtonRole = .primary
    var size: CGFloat = 16
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(IR.cjk(size, .bold))
                .foregroundStyle(role == .primary ? IR.primaryInk : IR.onPlate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, role == .primary ? 15 : 14)
                .background(role == .primary ? AnyShapeStyle(IR.primary) : AnyShapeStyle(IR.plateTranslucent))
                .overlay {
                    if role == .secondary {
                        Rectangle().stroke(IR.outline, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .hudPress()
    }
}

/// A small mono chip that *is* tappable — navigation uses words, not arrows.
struct HudChipButton: View {
    let title: String
    var size: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(IR.mono(size))
                .foregroundStyle(IR.onPlate)
                .padding(.horizontal, IR.chipPadX)
                .padding(.vertical, IR.chipPadY)
                .background(IR.plate)
                .contentShape(Rectangle())
        }
        .hudPress()
    }
}

struct KeypadKey: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(IR.mono(17))
                .foregroundStyle(IR.onPlate)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(IR.plateTranslucent)
                .overlay { Rectangle().stroke(IR.outline, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .hudPress()
    }
}

struct OptionRow: View {
    let code: String
    let label: String
    let temp: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Text(code)
                    .font(IR.mono(12))
                    .foregroundStyle(selected ? IR.primaryInk.opacity(0.6) : IR.onPlateMuted)
                Text(label)
                    .font(IR.cjk(16.5, .bold))
                    .foregroundStyle(selected ? IR.onInverse : IR.onPlate)
                Spacer(minLength: 8)
                Text(temp)
                    .font(IR.mono(11.5))
                    .foregroundStyle(selected ? IR.primaryInk.opacity(0.6) : IR.onPlateMuted)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 14)
            .background(selected ? AnyShapeStyle(IR.primary) : AnyShapeStyle(IR.plateDeep))
            .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
            .contentShape(Rectangle())
        }
        .hudPress()
    }
}

/// The one circular element in the system, and the only one that grows while held.
struct HoldTarget: View {
    let hint: String
    let label: String
    let holding: Bool
    let onDown: () -> Void
    let onUp: () -> Void

    @State private var pressed = false

    var body: some View {
        VStack(spacing: 3) {
            Text(hint)
                .font(IR.mono(10.5))
                .tracking(1.5)
                .foregroundStyle(IR.onPlate)
            Text(label)
                .font(IR.cjk(20, .bold))
                .foregroundStyle(IR.onPlate)
        }
        .frame(width: holding ? 168 : 156, height: holding ? 168 : 156)
        .background(IR.plateScrim)
        .clipShape(Circle())
        .overlay { Circle().stroke(IR.outline, lineWidth: 2) }
        .scaleEffect(pressed ? 0.965 : 1)
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18), value: holding)
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.13), value: pressed)
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
    }
}

// MARK: - Data

struct MetricBar: View {
    let key: String
    let value: String
    let filled: Bool
    /// 0…1 of the track width.
    let amount: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(key)
                    .font(IR.mono(11.5))
                    .foregroundStyle(IR.onPlateMuted)
                Spacer(minLength: 8)
                Text(value)
                    .font(IR.mono(11.5, .semibold))
                    .foregroundStyle(IR.onPlate)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(IR.outlineQuiet)
                    IR.track.frame(width: filled ? geo.size.width * amount : 0)
                }
            }
            .frame(height: 4)
        }
    }
}

/// A progress track. Every bar in this system starts at the cold origin.
struct MetricTrack: View {
    let progress: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.7)
                IR.track.frame(width: geo.size.width * progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Feedback

struct HudToast: View {
    let tag: String
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(IR.mono(10))
                .tracking(1.5)
                .foregroundStyle(IR.onPlateMuted)
            Text(message)
                .font(IR.cjk(13, .medium))
                .foregroundStyle(IR.onPlate)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(IR.plateSolid)
        .overlay(alignment: .leading) {
            Rectangle().fill(IR.primary).frame(width: 3)
        }
    }
}

/// 1s / 1.4s blinks are the only attention device; there is no spinner.
struct Blink: ViewModifier {
    let period: Double
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.3 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: period / 2).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

extension View {
    func blink(period: Double = 1) -> some View { modifier(Blink(period: period)) }
}

// MARK: - Screen scaffold

/// Every screen is the same box: field behind, insets 14 / safe area, 9pt stack gap.
struct HudScreen<Content: View>: View {
    let preset: FieldPreset
    var scanlines: Bool = true
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
            .parallax(-10)
        }
        .background { ThermalField(preset: preset, scanlines: scanlines) }
    }
}
