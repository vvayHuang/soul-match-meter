import SwiftUI

/// 07 · SETUP — none of these change the result. They just feel good to adjust.
struct SettingsScreen: View {
    let model: MeterModel

    private let holdOptions: [Double] = [3, 5, 10]

    var body: some View {
        HudScreen(preset: .settings) {
            HStack(alignment: .center, spacing: 6) {
                IconButton(glyph: .back, label: "返回") { model.go(.home) }
                Spacer(minLength: 0)
                ReadoutChip(text: "INSTRUMENT SETUP", size: .s)
            }

            HudPlate {
                VStack(alignment: .leading, spacing: 5) {
                    Text("設定")
                        .font(IR.cjk(20, .bold))
                        .foregroundStyle(IR.onPlate)
                    Text("這些設定完全不影響結果，但調起來很有感覺。")
                        .font(IR.cjk(12.5))
                        .lineSpacing(8)
                        .foregroundStyle(IR.onPlateVariant)
                    // App Review 1.4.1: the readouts must not pass for a thermometer.
                    Text("娛樂用途，不會測量真實溫度。")
                        .font(IR.cjk(12.5))
                        .lineSpacing(8)
                        .foregroundStyle(IR.onPlateMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 0) {
                SettingRow(title: "色盤", code: "PALETTE") {
                    SegmentedField(
                        options: ThermalPalette.allCases,
                        selection: model.palette,
                        title: \.rawValue
                    ) { model.palette = $0 }
                }

                SettingRow(title: "測量時長", code: "HOLD TIME") {
                    SegmentedField(
                        options: holdOptions,
                        selection: model.holdSeconds,
                        title: { "\(Int($0)) s" }
                    ) { model.holdSeconds = $0 }
                }

                SettingRow(title: "快門音效", code: "SHUTTER", divider: false) {
                    HudToggle(isOn: model.shutter) { model.setShutter($0) }
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)

            if !model.toast.isEmpty {
                HudToast(message: model.toast)
            }

            HudButton(title: "回復原廠設定") { model.factoryReset() }
        }
    }
}

/// A Chinese title over its mono code, with the control on the right. The
/// last row in a list turns its divider off.
private struct SettingRow<Control: View>: View {
    let title: String
    let code: String
    var divider = true
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(IR.cjk(16.5, .medium))
                    .foregroundStyle(IR.onPlate)
                Text(code)
                    .font(IR.mono(11.5))
                    .tracking(1.5)
                    .foregroundStyle(IR.onPlateMuted)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            control
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(IR.plate)
        .overlay(alignment: .bottom) {
            if divider {
                Rectangle().fill(IR.outlineQuiet).frame(height: 1)
            }
        }
    }
}
