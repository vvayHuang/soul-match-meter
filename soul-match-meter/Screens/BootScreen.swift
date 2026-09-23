import SwiftUI

/// 00 · BOOT — two seconds of wordmark, or one tap to skip.
struct BootScreen: View {
    let model: MeterModel

    @State private var lineOne = false
    @State private var lineTwo = false
    @State private var markerUp = false

    private let scaleHeight: CGFloat = 320

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("SOUL MATCH\nMETER · IR")
                    .font(IR.mono(34, .semibold))
                    .tracking(-1)
                    .lineSpacing(-1)
                    .foregroundStyle(IR.primary)
                    .opacity(lineOne ? 1 : 0)
                    .offset(y: lineOne ? 0 : 22)

                Text("靈魂配對測量儀")
                    .font(IR.cjk(19, .bold))
                    .tracking(5)
                    .foregroundStyle(IR.onPlateVariant)
                    .opacity(lineTwo ? 1 : 0)
                    .offset(y: lineTwo ? 0 : 22)
            }

            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 6) {
                CursorTriangleLeft()
                    .fill(Color.white)
                    .frame(width: 14, height: 18)
                    .offset(y: markerUp ? 0 : scaleHeight - 18)

                IR.rampVertical
                    .frame(width: 26, height: scaleHeight)
                    .border(Color.black, width: 1)
            }
            .frame(height: scaleHeight, alignment: .top)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0x050912), location: 0),
                    .init(color: Color(hex: 0x080E22), location: 0.52),
                    .init(color: Color(hex: 0x04070F), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .overlay {
                RadialGradient(
                    colors: [Color(hex: 0x1560B8, alpha: 0.42), Color(hex: 0x081046, alpha: 0)],
                    center: UnitPoint(x: 0.5, y: 0.44),
                    startRadius: 0,
                    endRadius: 320
                )
            }
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture { model.finishBoot() }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.55).delay(0.1)) { lineOne = true }
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.55).delay(0.38)) { lineTwo = true }
            withAnimation(.timingCurve(0.45, 0.05, 0.3, 1, duration: 2)) { markerUp = true }
        }
    }
}

/// The boot marker points right, into the scale.
private struct CursorTriangleLeft: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
