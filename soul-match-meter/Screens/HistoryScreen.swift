import SwiftUI

/// 08 · LOG — 24 hours of snapshots, which usually means none.
struct HistoryScreen: View {
    let model: MeterModel

    var body: some View {
        HudScreen(preset: .history) {
            HStack(alignment: .center, spacing: 6) {
                IconButton(glyph: .back, label: "返回") { model.go(.home) }
                Spacer(minLength: 0)
                ReadoutChip(text: "\(model.history.count) SNAPSHOTS", size: .s)
            }

            if model.history.isEmpty {
                emptyState
            } else {
                filledState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: IR.stackGap) {
            VStack(spacing: 12) {
                HudPlate {
                    VStack(alignment: .leading, spacing: 0) {
                        EmptyState(label: "0 SNAPSHOTS")

                        Text("還沒有任何測量紀錄")
                            .font(IR.cjk(20, .bold))
                            .foregroundStyle(IR.onPlate)
                            .padding(.top, 12)

                        Text("本機只保存 24 小時內的快照。目前是空的，這很正常。")
                            .font(IR.cjk(12.5))
                            .lineSpacing(8)
                            .foregroundStyle(IR.onPlateVariant)
                            .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HudButton(title: "去測第一次", role: .primary) { model.startHost() }
            }
            .frame(maxHeight: .infinity)

            // Clearing the log lands here, so its confirmation does too.
            if !model.toast.isEmpty {
                HudToast(message: model.toast)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var filledState: some View {
        VStack(spacing: IR.stackGap) {
            VStack(spacing: 7) {
                ForEach(model.history) { entry in
                    if entry.report != nil {
                        Button { model.open(entry) } label: {
                            HistoryRow(entry: entry)
                                .background(IR.plateTranslucent)
                                .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1.5) }
                                .contentShape(Rectangle())
                        }
                        .hudPress()
                        .accessibilityHint("開啟配對報告")
                    } else {
                        HistoryRow(entry: entry)
                            .background(IR.plate)
                    }
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            if !model.toast.isEmpty {
                HudToast(message: model.toast)
            }

            HudButton(title: "清空紀錄") { model.clearHistory() }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Thumbnail, serial (or pair) and meta, then the state. A finished pair
/// reads its score and points onward; a pending one just waits.
private struct HistoryRow: View {
    let entry: HistoryEntry

    @Environment(\.thermalPalette) private var palette

    private var done: Bool { entry.report != nil }

    var body: some View {
        HStack(spacing: 11) {
            palette.vertical
                .frame(width: 34, height: 34)
                .border(Color.black, width: 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.serial)
                    .font(IR.mono(13))
                    .foregroundStyle(IR.onPlate)
                Text(entry.meta)
                    .font(IR.mono(11.5))
                    .tracking(1.5)
                    .foregroundStyle(IR.onPlateMuted)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 8)

            Text(entry.state)
                .font(done ? IR.mono(13, .semibold) : IR.cjk(13, .medium))
                .foregroundStyle(done ? IR.onPlate : IR.onPlateVariant)

            if done {
                PointerTriangle(direction: .right)
                    .fill(IR.onPlate)
                    .frame(width: 7, height: 9)
                    .accessibilityHidden(true)
            }
        }
        .padding(13)
        .accessibilityElement(children: .combine)
    }
}
