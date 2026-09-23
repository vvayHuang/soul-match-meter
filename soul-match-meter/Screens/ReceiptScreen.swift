import SwiftUI

/// 05 · RECEIPT — the snapshot. The only paper surface in the system.
struct ReceiptScreen: View {
    let model: MeterModel

    @State private var shutter = false

    var body: some View {
        HudScreen(preset: .face, scanlines: model.scanlines, gap: 10) {
            HStack(spacing: 8) {
                ReadoutChip(text: "SNAPSHOT SAVED", size: 11)
                Spacer(minLength: 0)
                ReadoutChip(text: model.imageNumber, size: 11)
            }

            receipt
                .opacity(shutter ? 1 : 0)
                .scaleEffect(shutter ? 1 : 0.9)
                .offset(y: shutter ? 0 : 16)

            Spacer(minLength: 0)

            HudButton(title: model.copied ? "已複製 · 去貼給他" : "複製序號", role: .secondary, size: 15) {
                model.copyCode()
            }

            HudButton(title: "傳送給對方", role: .primary) { model.sendCode() }

            if model.waiting && !model.friendArrived {
                Text("WAITING FOR PEER · 對方大概在洗澡")
                    .font(IR.mono(10.5))
                    .foregroundStyle(IR.onPlateVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(IR.plate)
                    .blink(period: 1.4)
            }

            if model.friendArrived {
                HudButton(title: "對方回傳了 · 看配對報告 →", role: .primary, size: 15.5) {
                    model.go(.report)
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(IR.pop, value: model.friendArrived)
        .overlay(alignment: .bottom) {
            if !model.toast.isEmpty {
                HudToast(tag: "LOG", message: model.toast)
                    .padding(.horizontal, IR.screenInset)
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .offset(y: 16)))
            }
        }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.46)) { shutter = true }
        }
    }

    private var receipt: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("IR MEASUREMENT RECEIPT")
                Spacer(minLength: 8)
                Text("NO.03")
            }
            .font(IR.mono(10))
            .tracking(1.5)
            .foregroundStyle(IR.onInverseMuted)

            Text(model.myCode)
                .font(IR.mono(29, .medium))
                .tracking(3)
                .foregroundStyle(IR.onInverse)

            IR.rampHorizontal.frame(height: 9)

            VStack(spacing: 6) {
                ForEach(model.receiptRows) { row in
                    HStack(spacing: 10) {
                        Text(row.key)
                            .foregroundStyle(IR.onInverseVariant)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .fontWeight(.semibold)
                            .foregroundStyle(IR.onInverse)
                    }
                }
            }
            .font(IR.mono(11.5))

            VStack(spacing: 10) {
                TearLine()
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(IR.tearLine)
                    .frame(height: 1.5)

                HStack(spacing: 5) {
                    ForEach(0..<14, id: \.self) { _ in
                        Circle().fill(IR.onInverseMuted).frame(width: 6, height: 6)
                    }
                }
            }

            Text("撕下，貼給對方")
                .font(IR.mono(10))
                .tracking(1)
                .foregroundStyle(IR.onInverseVariant)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .background(IR.inverseSurface)
    }
}

/// The only dashed line the system allows.
private struct TearLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
