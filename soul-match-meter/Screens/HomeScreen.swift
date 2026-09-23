import SwiftUI

/// 01 · HOME — the standby viewfinder. Two ways in: measure yourself, or enter a peer serial.
struct HomeScreen: View {
    let model: MeterModel

    var body: some View {
        HudScreen(preset: .home, scanlines: model.scanlines, gap: 10) {
            HStack(alignment: .top, spacing: 8) {
                ReadoutChip(text: "36.4 °C", size: 16)
                Spacer(minLength: 0)
                ReadoutChip(text: "16:25")
                Spacer(minLength: 0)
                ReadoutChip(text: "ε = \(model.epsLabel)")
            }

            HStack(spacing: 6) {
                HudChipButton(title: "設定 SETUP", size: 12) { model.go(.settings) }
                HudChipButton(title: "紀錄 LOG", size: 12) { model.go(.history) }
            }

            Spacer(minLength: 0)
            Crosshair()
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)

            HudButton(title: "我先開始測", role: .primary, size: 16.5) { model.startHost() }
            HudButton(title: "我有對方的序號", role: .secondary, size: 15) { model.startGuest() }

            HStack(alignment: .bottom, spacing: 1) {
                ReadoutChip(text: "MAX:36.4 °C", size: 12)
                ReadoutChip(text: "MIN:16.5 °C", size: 12)
                Spacer(minLength: 0)
            }
        }
        .overlay(alignment: .topTrailing) {
            PaletteScale(height: 212, position: 0.08, animated: false)
                .padding(.trailing, IR.screenInset)
                .padding(.top, 130)
        }
    }
}
