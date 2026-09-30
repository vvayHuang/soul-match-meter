import SwiftUI

/// 03 · CALIB — three questions with no correct answer.
struct CalibrationScreen: View {
    let model: MeterModel

    private var question: CalibrationQuestion { model.currentQuestion }
    private var index: Int { min(model.questionIndex, model.questions.count - 1) }

    var body: some View {
        HudScreen(preset: .calibration) {
            HStack(alignment: .center, spacing: 12) {
                MetricTrack(progress: Double(index + 1) / Double(model.questions.count))
                    .animation(IR.hud(IR.durHover), value: index)
                IconButton(glyph: .close, label: "關閉") { model.go(.home) }
            }

            HudPlate(padX: 13, padY: 15) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%02d", index + 1))
                        .font(IR.mono(38, .semibold))
                        .foregroundStyle(IR.onPlate)

                    Text(question.text)
                        .font(IR.cjk(29, .bold))
                        .lineSpacing(6)
                        .foregroundStyle(IR.onPlate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .modifier(RiseIn())
            // A fresh card per question, so each one rises in on its own.
            .id(model.questionIndex)
            .padding(.top, 12)

            Spacer(minLength: 0)

            VStack(spacing: 7) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, label in
                    HudButton(
                        title: label,
                        role: model.answers[model.questionIndex] == optionIndex ? .primary : .secondary
                    ) {
                        model.pick(option: optionIndex)
                    }
                }
            }
        }
    }
}

/// irRise: the question card fades up 13pt as it lands.
private struct RiseIn: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 13)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(IR.easeRise(0.68)) { shown = true }
            }
    }
}
