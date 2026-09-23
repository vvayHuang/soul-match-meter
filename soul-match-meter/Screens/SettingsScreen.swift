import SwiftUI

/// 07 · SETUP — none of these change the result. They just feel good to adjust.
struct SettingsScreen: View {
    let model: MeterModel

    var body: some View {
        HudScreen(preset: .settings, scanlines: model.scanlines) {
            HStack(spacing: 8) {
                HudChipButton(title: "← BACK") { model.go(.home) }
                Spacer(minLength: 0)
                ReadoutChip(text: "INSTRUMENT SETUP", size: 11)
            }

            HudPlate(padX: 13, padY: 11) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("設定")
                        .font(IR.cjk(20, .bold))
                        .foregroundStyle(IR.onPlate)
                    Text("這些設定完全不影響結果，但調起來很有感覺。")
                        .font(IR.cjk(12.5))
                        .lineSpacing(6)
                        .foregroundStyle(IR.onPlateVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 10)

            VStack(spacing: 0) {
                SettingRow(title: "溫度單位", code: "UNIT", divider: true) {
                    HStack(spacing: 0) {
                        ForEach(["°C", "°F"], id: \.self) { option in
                            Button { model.unit = option } label: {
                                Text(option)
                                    .font(IR.mono(13))
                                    .foregroundStyle(model.unit == option ? IR.primaryInk : IR.onPlate)
                                    .frame(minWidth: 52, minHeight: 36)
                                    .background(model.unit == option ? IR.primary : Color.clear)
                                    .overlay(alignment: .leading) {
                                        if option == "°F" {
                                            Rectangle().fill(IR.outline).frame(width: 1)
                                        }
                                    }
                                    .contentShape(Rectangle())
                            }
                            .hudPress()
                        }
                    }
                    .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
                }

                SettingRow(title: "發射率", code: "EMISSIVITY · 0.10–1.00", divider: true) {
                    HStack(spacing: 0) {
                        Button { model.stepEmissivity(-0.05) } label: {
                            Text("−")
                                .font(IR.mono(17))
                                .foregroundStyle(IR.onPlate)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .hudPress()

                        Text(model.epsLabel)
                            .font(IR.mono(13))
                            .foregroundStyle(IR.onPlate)
                            .frame(minWidth: 56, minHeight: 36)
                            .overlay(alignment: .leading) { Rectangle().fill(IR.outline).frame(width: 1) }
                            .overlay(alignment: .trailing) { Rectangle().fill(IR.outline).frame(width: 1) }

                        Button { model.stepEmissivity(0.05) } label: {
                            Text("+")
                                .font(IR.mono(17))
                                .foregroundStyle(IR.onPlate)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                        .hudPress()
                    }
                    .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
                }

                SettingRow(title: "掃描線", code: "SCANLINES", divider: true) {
                    Button { model.scanlines.toggle() } label: {
                        Text(model.scanlines ? "ON" : "OFF")
                            .font(IR.mono(13))
                            .tracking(1.5)
                            .foregroundStyle(model.scanlines ? IR.primaryInk : IR.onPlateMuted)
                            .frame(width: 74, height: 36)
                            .background(model.scanlines ? IR.primary : Color.clear)
                            .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
                            .contentShape(Rectangle())
                    }
                    .hudPress()
                }

                SettingRow(title: "校正", code: "LAST CALIBRATED", divider: false) {
                    HStack(spacing: 12) {
                        Text("2019/04/02")
                            .font(IR.mono(13))
                            .foregroundStyle(IR.onPlateVariant)
                            .fixedSize()

                        Button { model.showToast("校正功能從沒做完") } label: {
                            Text("OFF")
                                .font(IR.mono(13))
                                .tracking(1.5)
                                .foregroundStyle(IR.onPlateMuted)
                                .frame(width: 74, height: 36)
                                .overlay { Rectangle().stroke(IR.outline, lineWidth: 1.5) }
                                .contentShape(Rectangle())
                        }
                        .hudPress()
                    }
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)

            HudButton(title: "回復原廠設定", role: .secondary, size: 15) { model.factoryReset() }
        }
        .overlay(alignment: .bottom) {
            if !model.toast.isEmpty {
                HudToast(tag: "SET", message: model.toast)
                    .padding(.horizontal, IR.screenInset)
                    .padding(.bottom, 96)
                    .transition(.opacity.combined(with: .offset(y: 16)))
            }
        }
    }
}

private struct SettingRow<Control: View>: View {
    let title: String
    let code: String
    let divider: Bool
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
