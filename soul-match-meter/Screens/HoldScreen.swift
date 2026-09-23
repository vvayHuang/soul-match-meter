import SwiftUI

/// 04 · HOLD — five seconds of contact. Let go and the reading cools to 0.0s.
struct HoldScreen: View {
    let model: MeterModel

    private var tempLabel: String {
        String(format: "%.1f °C", model.liveTemperature)
    }

    private var totalLabel: String {
        let state: String
        if model.holding {
            state = "RISING"
        } else if model.holdPct >= 100 {
            state = "LOCKED"
        } else {
            state = "IDLE"
        }
        return String(format: "/ %.1fs · %@", model.holdSeconds, state)
    }

    var body: some View {
        HudScreen(preset: .faceLive, scanlines: model.scanlines, scrollable: false) {
            HStack(alignment: .top, spacing: 8) {
                ReadoutChip(text: tempLabel, size: 17, color: IR.thermal70)
                Spacer(minLength: 0)
                Text("\(model.holdPct >= 100 ? "DONE" : "MEASURING")\nHOLD")
                    .font(IR.mono(10))
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(IR.onPlate)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(IR.plate)
            }

            HudPlate(padX: 12, padY: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text(String(format: "%.1f", model.holdFraction * model.holdSeconds))
                            .font(IR.mono(62, .semibold))
                            .tracking(-2)
                        Text("s").font(IR.mono(24, .semibold))
                    }
                    .foregroundStyle(IR.onPlate)

                    Text(totalLabel)
                        .font(IR.mono(11.5))
                        .tracking(1.5)
                        .foregroundStyle(IR.primary)
                }
            }
            .fixedSize()

            Spacer(minLength: 0)
            Crosshair(size: 44, centre: model.spotColor)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)

            if model.hasStatus {
                Text(model.statusText)
                    .font(IR.cjk(15, .bold))
                    .foregroundStyle(IR.onPlate)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(IR.plate)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }

            Text(model.dropped ? "手指離開就會冷掉，從 0.0s 重來。" : " ")
                .font(IR.cjk(13, .bold))
                .foregroundStyle(IR.error)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                .background(IR.plate)

            HoldTarget(
                hint: model.holding ? "DO NOT RELEASE" : "PRESS & HOLD 5s",
                label: model.holdPct >= 100 ? "好了" : (model.holding ? "別放" : "按住"),
                holding: model.holding,
                onDown: { model.startHold() },
                onUp: { model.endHold() }
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            HStack {
                ReadoutChip(text: "x 1", size: 11.5)
                Spacer(minLength: 0)
                ReadoutChip(text: "ε = 0.80", size: 11.5)
            }
            .padding(.top, 6)
        }
        .animation(IR.uiCurve, value: model.hasStatus)
        // Continuous buzz while pressing, heavier as the gauge climbs.
        .sensoryFeedback(trigger: model.buzzTick) { _, tick in
            guard model.holding, tick.isMultiple(of: 2) else { return nil }
            return .impact(weight: .light, intensity: 0.35 + 0.65 * model.gaugeFraction)
        }
        // The gauge almost tops out, then slips back — a hard knock sells it.
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: model.slipTick)
        .sensoryFeedback(trigger: model.holding) { _, isHolding in
            isHolding ? .impact(weight: .medium) : nil
        }
        .sensoryFeedback(trigger: model.holdPct >= 100) { _, done in
            done ? .success : nil
        }
        .sensoryFeedback(trigger: model.dropped) { _, dropped in
            dropped ? .error : nil
        }
        .overlay(alignment: .topTrailing) {
            PaletteScale(
                height: 230,
                position: model.gaugeFraction,
                topLabel: tempLabel
            )
            .padding(.trailing, IR.scaleInset)
            .padding(.top, 96)
        }
    }
}
