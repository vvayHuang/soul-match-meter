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

            Spacer(minLength: 0)

            HudButton(title: "我先開始測", role: .primary) { model.startHost() }
            HudButton(title: "我有對方的序號") { model.startGuest() }
        }
    }
}
