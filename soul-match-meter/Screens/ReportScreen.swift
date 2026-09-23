import SwiftUI

/// 06 · REPORT — a completely unfounded percentage, reported with a reference range.
struct ReportScreen: View {
    let model: MeterModel

    @State private var scoreIn = false

    private var scoreView: String { String(model.scoreAnim ?? model.score) }

    var body: some View {
        HudScreen(preset: .report, scanlines: model.scanlines) {
            ReportReadout(model: model, scoreText: scoreView, barsOn: model.barsOn, scoreIn: scoreIn)

            Spacer(minLength: 0)

            HudButton(
                title: model.shared ? "已匯出 · 再匯出一次" : "匯出熱像報告",
                role: .secondary,
                size: 15
            ) {
                exportReport()
            }

            HudButton(title: "再測一次（結果會變）", role: .primary) {
                model.confirming = true
            }
        }
        .overlay(alignment: .topTrailing) {
            ReportScale(model: model)
        }
        .overlay {
            if model.confirming {
                confirmDialog
            }
        }
        .animation(IR.uiCurveFast, value: model.confirming)
        .onAppear {
            scoreIn = false
            withAnimation(.easeOut(duration: 0.4)) { scoreIn = true }
        }
    }

    /// Renders the finished report as an image and hands it to the share sheet.
    private func exportReport() {
        let renderer = ImageRenderer(content: ReportExportCard(model: model))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        SharePresenter.share([image]) { completed in
            if completed { model.shared = true }
        }
    }

    private var confirmDialog: some View {
        ZStack {
            Color(hex: 0x04060E, alpha: 0.78).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                Text("CFM 01")
                    .font(IR.mono(11.5))
                    .tracking(1.5)
                    .foregroundStyle(IR.onPlateMuted)

                Text("確定要重測？")
                    .font(IR.cjk(20, .bold))
                    .foregroundStyle(IR.onPlate)

                Text("目前的讀數與序號會作廢，兩個人要重新測量、重新交換序號。")
                    .font(IR.cjk(12.5))
                    .lineSpacing(6)
                    .foregroundStyle(IR.onPlateVariant)

                HStack(spacing: 8) {
                    Button { model.confirming = false } label: {
                        Text("留著")
                            .font(IR.cjk(16, .bold))
                            .foregroundStyle(IR.onPlate)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
                            .contentShape(Rectangle())
                    }
                    .hudPress()

                    Button { model.again() } label: {
                        Text("重測")
                            .font(IR.cjk(16, .bold))
                            .foregroundStyle(IR.primaryInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(IR.primary)
                            .contentShape(Rectangle())
                    }
                    .hudPress()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IR.plateSolid)
            .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
            .padding(IR.screenInset)
        }
    }
}

/// The report's readings: pair label, score, tier and metrics. Shared by the
/// screen (animated) and the exported image (final values).
private struct ReportReadout: View {
    let model: MeterModel
    let scoreText: String
    let barsOn: Bool
    var scoreIn = true

    var body: some View {
        HStack(spacing: 8) {
            ReadoutChip(text: "MATCH REPORT", size: 11)
            Spacer(minLength: 0)
            ReadoutChip(text: model.pairLabel, size: 10)
        }

        HudPlate(padX: 13, padY: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scoreText)
                    .font(IR.mono(104, .semibold))
                    .tracking(-6)
                    .foregroundStyle(IR.onPlate)
                    .monospacedDigit()

                Text(model.deltaLabel)
                    .font(IR.mono(12))
                    .tracking(2)
                    .foregroundStyle(IR.primary)
            }
        }
        .fixedSize()
        .padding(.top, 8)
        .opacity(scoreIn ? 1 : 0)
        .scaleEffect(scoreIn ? 1 : 0.8)

        HudPlate(padX: 13, padY: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(model.resultTier.title)
                    .font(IR.cjk(19, .bold))
                    .foregroundStyle(IR.onPlate)
                Text(model.resultTier.subtitle)
                    .font(IR.cjk(12.5))
                    .lineSpacing(5)
                    .foregroundStyle(IR.onPlateVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.trailing, 52)

        HudPlate(padX: 13, padY: 11) {
            VStack(spacing: 8) {
                ForEach(model.metrics) { metric in
                    MetricBar(
                        key: metric.key,
                        value: metric.value,
                        filled: barsOn,
                        amount: metric.amount
                    )
                }
            }
        }
        .padding(.trailing, IR.scaleReserve)
    }
}

/// The right-edge palette scale, pointing at the score.
private struct ReportScale: View {
    let model: MeterModel

    var body: some View {
        PaletteScale(
            height: 190,
            position: Double(model.score) / 100,
            animated: false
        )
        .padding(.trailing, IR.scaleInset)
        .padding(.top, 148)
    }
}

/// A still, phone-sized copy of the report for sharing: no buttons, no
/// animation, and the instrument's name at the foot.
private struct ReportExportCard: View {
    let model: MeterModel

    private let topInset: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: IR.stackGap) {
            ReportReadout(model: model, scoreText: String(model.score), barsOn: true)

            Spacer(minLength: 0)

            ReadoutChip(text: "SOUL MATCH METER · 靈魂配對測量儀", size: 11)
        }
        .padding(.horizontal, IR.screenInset)
        .padding(.top, topInset)
        .padding(.bottom, 28)
        .frame(width: 390, height: 844, alignment: .top)
        .overlay(alignment: .topTrailing) {
            ReportScale(model: model)
                .padding(.top, topInset)
        }
        .background { ThermalField(preset: .report, scanlines: model.scanlines, animated: false) }
        .environment(\.colorScheme, .dark)
    }
}
