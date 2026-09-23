import SwiftUI

/// 08 · LOG — 24 hours of snapshots, which usually means none.
struct HistoryScreen: View {
    let model: MeterModel

    var body: some View {
        HudScreen(preset: .history, scanlines: model.scanlines) {
            HStack(spacing: 8) {
                HudChipButton(title: "← BACK") { model.go(.home) }
                Spacer(minLength: 0)
                ReadoutChip(text: "\(model.history.count) SNAPSHOTS", size: 11)
            }

            if model.history.isEmpty {
                emptyState
            } else {
                filledState
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .stroke(IR.onPlateMuted, lineWidth: 2)
                        .frame(width: 26, height: 26)
                    Rectangle()
                        .fill(IR.onPlateMuted)
                        .frame(width: 26, height: 2)
                        .offset(x: -2)
                }
                .frame(width: 26, height: 26)

                Text("0 SNAPSHOTS")
                    .font(IR.mono(13))
                    .tracking(1.5)
                    .foregroundStyle(IR.onPlateMuted)
            }

            HudPlate(padX: 13, padY: 11) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("還沒有任何測量紀錄")
                        .font(IR.cjk(20, .bold))
                        .foregroundStyle(IR.onPlate)
                    Text("本機只保存 24 小時內的快照。目前是空的，這很正常。")
                        .font(IR.cjk(12.5))
                        .lineSpacing(6)
                        .foregroundStyle(IR.onPlateVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HudButton(title: "去測第一次", role: .primary) { model.startHost() }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }

    private var filledState: some View {
        VStack(spacing: IR.stackGap) {
            VStack(spacing: 7) {
                ForEach(model.history) { entry in
                    HStack(spacing: 11) {
                        IR.rampVertical
                            .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.serial)
                                .font(IR.mono(13))
                                .foregroundStyle(IR.onPlate)
                            Text(entry.meta)
                                .font(IR.mono(11.5))
                                .tracking(1.5)
                                .foregroundStyle(IR.onPlateMuted)
                        }

                        Spacer(minLength: 8)

                        Text(entry.state)
                            .font(IR.cjk(13, .medium))
                            .foregroundStyle(IR.onPlateVariant)
                    }
                    .padding(13)
                    .background(IR.plate)
                }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)

            HudButton(title: "清空紀錄", role: .secondary, size: 15) { model.clearHistory() }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if !model.toast.isEmpty {
                HudToast(tag: "LOG", message: model.toast)
                    .padding(.bottom, 76)
                    .transition(.opacity.combined(with: .offset(y: 16)))
            }
        }
    }
}
