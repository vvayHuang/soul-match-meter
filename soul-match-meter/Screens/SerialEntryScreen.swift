import SwiftUI

/// 02 · SERIAL — five digits, a fixed prefix nobody can explain, and one error line.
struct SerialEntryScreen: View {
    let model: MeterModel

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "RND", "0", "DEL"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var inputView: String {
        model.input.padding(toLength: 5, withPad: "_", startingAt: 0)
    }

    var body: some View {
        HudScreen(preset: .serial, scanlines: model.scanlines) {
            HStack(alignment: .top, spacing: 8) {
                HudChipButton(title: "← BACK") { model.go(.home) }
                Spacer(minLength: 0)
                ReadoutChip(text: "PEER SERIAL", size: 11)
            }

            HudPlate {
                VStack(alignment: .leading, spacing: 8) {
                    Text("輸入對方的測量序號")
                        .font(IR.cjk(20, .bold))
                        .foregroundStyle(IR.onPlate)

                    Text("SM-\(inputView)")
                        .font(IR.mono(26))
                        .tracking(4)
                        .foregroundStyle(IR.primary)

                    Group {
                        if model.codeError.isEmpty {
                            Text(" ")
                        } else {
                            Text(model.codeError).blink(period: 1)
                        }
                    }
                    .font(IR.mono(11))
                    .tracking(1)
                    .foregroundStyle(IR.error)
                    .frame(minHeight: 16, alignment: .leading)
                    .id(model.codeError)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("前綴 SM- 為原廠固定，出廠文件沒有解釋原因。")
                .font(IR.cjk(12))
                .lineSpacing(5)
                .foregroundStyle(IR.onPlateVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x12151B, alpha: 0.8))

            Spacer(minLength: 0)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    KeypadKey(label: key) { model.tapKey(key) }
                }
            }

            HudButton(title: "確認序號", role: .primary) { model.submitCode() }
        }
    }
}
