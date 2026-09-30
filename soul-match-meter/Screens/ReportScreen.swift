import SwiftUI

/// 06 · REPORT — a completely unfounded percentage, reported with confidence.
/// 08c reuses it for a finished report reopened from the log.
struct ReportScreen: View {
    let model: MeterModel
    /// 08c: back to the log instead of a retest, and stills instead of this
    /// session's snapshot.
    var archived = false

    @Environment(\.thermalPalette) private var palette

    private var report: MatchReport {
        archived ? (model.viewing ?? model.liveReport) : model.liveReport
    }

    var body: some View {
        HudScreen(preset: archived ? .archive : .report) {
            header

            Spacer(minLength: 0)

            ReportGrid(report: report, shownScore: model.scoreAnim ?? report.score, barsOn: model.barsOn)

            Spacer(minLength: 0)

            HudButton(title: model.shared ? "已匯出 · 再匯出一次" : "匯出熱像報告") {
                exportReport()
            }

            if !archived {
                HudButton(title: "再測一次（結果會變）", role: .primary) {
                    model.confirming = true
                }
            }
        }
        .overlay {
            if model.confirming {
                ZStack {
                    Color(hex: 0x04060E, alpha: 0.78).ignoresSafeArea()

                    ConfirmDialog(
                        title: "確定要重測？",
                        confirmLabel: "重測",
                        onCancel: { model.confirming = false },
                        onConfirm: { model.again() }
                    )
                    .padding(IR.screenInset)
                }
            }
        }
        .animation(IR.uiCurveFast, value: model.confirming)
    }

    @ViewBuilder private var header: some View {
        if archived {
            HStack(alignment: .center, spacing: 6) {
                IconButton(glyph: .back, label: "返回") { model.go(.history) }
                Spacer(minLength: 0)
                ReadoutChip(text: report.pair, size: .xs)
            }
        } else {
            HStack(alignment: .top, spacing: 6) {
                ReadoutChip(text: "MATCH REPORT", size: .s)
                Spacer(minLength: 0)
                ReadoutChip(text: report.pair, size: .xs)
            }
        }
    }

    /// Renders the finished report as an image and hands it to the share sheet.
    private func exportReport() {
        let card = ReportExportCard(report: report, preset: archived ? .archive : .report)
            .environment(\.thermalPalette, palette)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        SharePresenter.share([image]) { completed in
            if completed { model.shared = true }
        }
    }
}

/// The report's middle row: the score on the left, sized to its number, and
/// the title with three metric bars filling the rest. Both plates share a height.
struct ReportGrid: View {
    let report: MatchReport
    let shownScore: Int
    let barsOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ScoreReadout(shown: shownScore, final: report.score)
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxHeight: .infinity)
                .background(IR.plate)

            HudPlate(padX: 10, padY: 11) {
                VStack(alignment: .leading, spacing: 9) {
                    Text(report.title)
                        .font(IR.cjk(15, .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(IR.onPlate)
                        .accessibilityAddTraits(.isHeader)

                    ForEach(report.metrics) { metric in
                        MetricBar(
                            label: metric.key,
                            value: barsOn ? metric.value : "0%",
                            amount: barsOn ? metric.amount : 0
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The score as the prototype sets it: the number, then a small "%" on the
/// same baseline. The design system would put the unit on a unit line
/// instead; this layout is interim until the design settles, and lives only
/// here so it can be swapped. Space for the final number is reserved so the
/// count-up doesn't push the right-hand plate around.
private struct ScoreReadout: View {
    let shown: Int
    let final: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            BigReadout(value: String(final), bare: true)
                .hidden()
                .overlay(alignment: .trailing) {
                    BigReadout(value: String(shown), bare: true)
                }
            Text("%")
                .font(IR.mono(16, .semibold))
                .foregroundStyle(IR.onPlate)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("配對度 \(final) %")
    }
}

/// A still, phone-sized copy of the report for sharing: no buttons, no
/// animation, and the instrument's name at the foot.
private struct ReportExportCard: View {
    let report: MatchReport
    let preset: FieldPreset

    var body: some View {
        VStack(alignment: .leading, spacing: IR.stackGap) {
            HStack(alignment: .top, spacing: 6) {
                ReadoutChip(text: "MATCH REPORT", size: .s)
                Spacer(minLength: 0)
                ReadoutChip(text: report.pair, size: .xs)
            }

            Spacer(minLength: 0)

            ReportGrid(report: report, shownScore: report.score, barsOn: true)

            Spacer(minLength: 0)

            ReadoutChip(text: "SOUL MATCH METER · 靈魂配對測量儀", size: .s)
        }
        .padding(.horizontal, IR.screenInset)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(width: 390, height: 844, alignment: .top)
        .background { ThermalField(preset: preset, animated: false) }
        .environment(\.colorScheme, .dark)
    }
}
