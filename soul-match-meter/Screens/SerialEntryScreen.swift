import SwiftUI

/// 02 · SERIAL — six digits (the last one is a check digit) and one error line.
struct SerialEntryScreen: View {
    let model: MeterModel

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "RND", "0", "DEL"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var inputView: String {
        model.input.padding(toLength: SerialCodec.length, withPad: "_", startingAt: 0)
    }

    var body: some View {
        HudScreen(preset: .serial) {
            HStack {
                IconButton(glyph: .back, label: "返回") { model.serialBack() }
                Spacer(minLength: 0)
            }

            HudPlate {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.mode == .host && !model.myCode.isEmpty ? "輸入對方回傳的序號" : "輸入對方的測量序號")
                        .font(IR.cjk(20, .bold))
                        .foregroundStyle(IR.onPlate)

                    Text("SM-\(inputView)")
                        .font(IR.mono(26))
                        .tracking(4)
                        .foregroundStyle(IR.onPlate)
                        .accessibilityLabel("SM-\(model.input)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.codeError.isEmpty {
                HudToast(tone: .error, message: model.codeError, blink: true)
                    .id(model.codeError)
            }

            Spacer(minLength: 0)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    KeypadKey(label: key) { model.tapKey(key) }
                        .accessibilityLabel(keyName(key))
                }
            }

            HudButton(title: "確認序號", role: .primary) { model.submitCode() }
        }
    }

    private func keyName(_ key: String) -> String {
        switch key {
        case "RND": "隨機序號"
        case "DEL": "刪除"
        default: key
        }
    }
}
