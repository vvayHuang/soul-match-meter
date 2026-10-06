import SwiftUI

/// 04 · HOLD — five seconds of contact. Let go and the reading cools to 0.0s.
struct HoldScreen: View {
    let model: MeterModel

    private var locked: Bool { model.holdPct >= 100 }

    private var tempLabel: String {
        String(format: "%.1f °C", model.liveTemperature)
    }

    private var secondsLabel: String {
        String(format: "%.1fs", model.holdFraction * model.holdSeconds)
    }

    private var totalLabel: String {
        let state: String
        if model.holding {
            state = "RISING"
        } else if locked {
            state = "LOCKED"
        } else {
            state = "IDLE"
        }
        return String(format: "/ %.1fs · %@", model.holdSeconds, state)
    }

    var body: some View {
        HudScreen(preset: .faceLive, scrollable: false) {
            HStack(alignment: .top, spacing: 6) {
                ReadoutChip(text: tempLabel, tone: .hot)
                Spacer(minLength: 0)
                ReadoutChip(text: "\(locked ? "DONE" : "MEASURING")\nHOLD", size: .xs)
            }

            BigReadout(value: secondsLabel, unitLine: totalLabel)

            Crosshair(size: 44, locked: locked)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.dropped {
                HudToast(tone: .error, message: "手指離開就會冷掉，從 0.0s 重來。", blink: true)
            }

            HoldTarget(
                label: locked ? "好了" : (model.holding ? "別放" : "按住"),
                holding: model.holding,
                onDown: { model.startHold() },
                onUp: { model.endHold() }
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 4)

            HStack {
                ReadoutChip(text: "x 1", size: .s)
                Spacer(minLength: 0)
                ReadoutChip(text: "ε = 0.80", size: .s)
            }
        }
        // Continuous buzz while pressing, heavier as the reading climbs.
        .sensoryFeedback(trigger: model.buzzTick) { _, tick in
            guard model.holding, tick.isMultiple(of: 2) else { return nil }
            return .impact(weight: .light, intensity: 0.35 + 0.65 * model.holdFraction)
        }
        .sensoryFeedback(trigger: model.holding) { _, isHolding in
            isHolding ? .impact(weight: .medium) : nil
        }
        .sensoryFeedback(trigger: locked) { _, done in
            done ? .success : nil
        }
        .sensoryFeedback(trigger: model.dropped) { _, dropped in
            dropped ? .error : nil
        }
        .overlay(alignment: .topTrailing) {
            PaletteScale(height: 230, marker: (model.holdFraction * 100).rounded())
                .padding(.trailing, IR.screenInset)
                .padding(.top, 96)
        }
    }
}
