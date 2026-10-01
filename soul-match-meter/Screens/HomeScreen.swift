import SwiftUI

/// 01 · HOME — the standby viewfinder. Two ways in: measure yourself, or enter a peer serial.
struct HomeScreen: View {
    let model: MeterModel

    var body: some View {
        HudScreen(preset: .home) {
            HStack(alignment: .center, spacing: 6) {
                ReadoutChip(text: "36.4 °C", tone: .hot)
                Spacer(minLength: 0)
                HStack(spacing: 1) {
                    ReadoutChip(text: "MAX 36.4 °C", size: .s)
                    ReadoutChip(text: "MIN 16.5 °C", size: .s)
                }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                HudButton(title: "設定", size: .small) { model.go(.settings) }
                HudButton(title: "紀錄", size: .small) { model.go(.history) }
            }

            if let entry = model.pending {
                PendingPlate(entry: entry) { model.open(entry) }
            }

            Spacer(minLength: 0)

            HudButton(title: "我先開始測", role: .primary) { model.startHost() }
            HudButton(title: "我有對方的序號") { model.startGuest() }
        }
    }
}

/// 01b / 01c — the newest exchange still in flight, one tap from where it
/// left off: info while the reply is out, success once it's in.
private struct PendingPlate: View {
    let entry: HistoryEntry
    let action: () -> Void

    private var waiting: Bool { entry.status == .waiting }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.serial)
                        .font(IR.mono(13))
                        .foregroundStyle(IR.onPlate)
                    Text(waiting ? "等待對方回傳" : "對方回傳了 · 看配對報告")
                        .font(IR.cjk(13, .medium))
                        .foregroundStyle(IR.onPlateVariant)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

                if waiting {
                    // The timeline only drives the refresh. Its dates snap to the
                    // minute, which can fall before `sentAt` and read 25 H.
                    TimelineView(.everyMinute) { _ in
                        Text("剩 \(entry.hoursLeft(at: .now)) H")
                            .font(IR.mono(11.5))
                            .tracking(1.5)
                            .foregroundStyle(IR.onPlateVariant)
                    }
                }

                PointerTriangle(direction: .right)
                    .fill(IR.onPlate)
                    .frame(width: 7, height: 9)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.leading, 3 + 11) // the marker, then the gap
            .padding(.trailing, 13)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(waiting ? IR.info : IR.success)
                    .frame(width: 3)
            }
            // The marker sits inside the white line, not under it.
            .padding(1.5)
            .background(IR.plateTranslucent)
            .overlay { Rectangle().strokeBorder(IR.outline, lineWidth: 1.5) }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .hudPress()
        .accessibilityHint(waiting ? "回到收據" : "開啟配對報告")
    }
}
