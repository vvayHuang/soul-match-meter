import SwiftUI

/// 03 · CALIB — three questions with no correct answer, each option carrying a temperature.
struct CalibrationScreen: View {
    let model: MeterModel

    @State private var cardIn = false

    private var question: CalibrationQuestion { model.currentQuestion }
    private var index: Int { min(model.questionIndex, model.questions.count - 1) }

    var body: some View {
        HudScreen(preset: .calibration, scanlines: model.scanlines) {
            HStack(spacing: 8) {
                ReadoutChip(text: "CALIBRATION", size: 11)
                Spacer(minLength: 0)
                ReadoutChip(text: "\(index + 1) / 3", size: 11)
            }

            MetricTrack(progress: Double(index) / 3)
                .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.42), value: index)

            HudPlate(padX: 13, padY: 15) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%02d", index + 1))
                        .font(IR.mono(38, .semibold))
                        .foregroundStyle(IR.primary)

                    Text(question.text)
                        .font(IR.cjk(24, .bold))
                        .lineSpacing(7)
                        .foregroundStyle(IR.onPlate)
                        .padding(.top, 7)

                    Text("SINGLE SELECT · NO CORRECT ANSWER")
                        .font(IR.mono(10.5))
                        .tracking(1)
                        .foregroundStyle(IR.onPlateMuted)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 12)
            .opacity(cardIn ? 1 : 0)
            .offset(y: cardIn ? 0 : 13)

            Spacer(minLength: 0)

            VStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, label in
                    OptionRow(
                        code: String(format: "%02d", optionIndex + 1),
                        label: label,
                        temp: question.temps[optionIndex],
                        selected: model.answers[model.questionIndex] == optionIndex
                    ) {
                        model.pick(option: optionIndex)
                    }
                }
            }
        }
        .onAppear { animateCard() }
        .onChange(of: model.questionIndex) { _, _ in
            cardIn = false
            animateCard()
        }
    }

    private func animateCard() {
        withAnimation(.timingCurve(0.16, 0.72, 0.24, 1, duration: 0.68)) { cardIn = true }
    }
}
