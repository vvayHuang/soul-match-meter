import SwiftUI
import UIKit

/// 05 · RECEIPT — the snapshot. The only paper surface in the system.
struct ReceiptScreen: View {
    let model: MeterModel

    var body: some View {
        HudScreen(preset: .receipt) {
            HStack(alignment: .center, spacing: 6) {
                IconButton(glyph: .back, label: "返回") { model.go(.home) }
                Spacer(minLength: 0)
                HStack(spacing: 1) {
                    ReadoutChip(text: "SNAPSHOT SAVED", size: .s)
                    ReadoutChip(text: model.imageNumber, size: .s)
                }
            }

            ReceiptCard(serial: model.myCode, rows: model.receiptRows, footnote: "撕下，貼給對方。")

            Spacer(minLength: 0)

            if model.mode == .host && handedOff {
                HudToast(tone: .info, message: "等待對方回傳。對方大概在洗澡。", blink: true)
            }

            if !model.toast.isEmpty {
                HudToast(message: model.toast)
            }

            // Copy stays as the backup path throughout. Before handing off,
            // sending takes the white-hot button; after, the next step does.
            copyButton

            if handedOff {
                HudButton(title: nextTitle, role: .primary) {
                    if model.mode == .host {
                        model.enterPeerCode()
                    } else {
                        model.go(.report)
                    }
                }
            } else {
                HudButton(title: "傳送給對方", role: .primary) {
                    SharePresenter.share([model.shareMessage]) { completed in
                        if completed { model.markSent() }
                    }
                }
            }
        }
        // Drawn in the palette it was measured in, not today's setting.
        .environment(\.thermalPalette, model.snapshotPalette)
    }

    /// The serial has left this phone, by share sheet or clipboard.
    private var handedOff: Bool { model.sent || model.copied }

    private var nextTitle: String {
        model.mode == .host ? "對方回傳了 · 輸入他的序號" : "看配對報告"
    }

    private var copyButton: some View {
        HudButton(title: model.copied ? "已複製 · 去貼給他" : "複製序號") {
            model.copyCode()
        }
    }
}

/// Paper, not a button: no press state, never scales. A ramp band on top,
/// the serial, dotted rows, and a footnote.
private struct ReceiptCard: View {
    let serial: String
    let rows: [ReceiptRow]
    let footnote: String

    @Environment(\.thermalPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            palette.horizontal
                .frame(height: 6)
                .padding(.bottom, 12)

            Text(serial)
                .font(IR.mono(26, .medium))
                .tracking(2)
                .foregroundStyle(IR.onInverse)

            VStack(spacing: 6) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(row.key)
                            .foregroundStyle(IR.onInverseVariant)
                        Spacer(minLength: 0)
                        Text(row.value)
                            .foregroundStyle(IR.onInverse)
                    }
                    .font(IR.mono(11.5))
                    .tracking(1)
                    .padding(.bottom, 4)
                    .overlay(alignment: .bottom) {
                        DottedRule()
                            .stroke(IR.onInverseMuted, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
                            .frame(height: 1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 12)

            Text(footnote)
                .font(IR.cjk(12.5))
                .lineSpacing(6)
                .foregroundStyle(IR.onInverseMuted)
                .padding(.top, 12)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IR.inverseSurface)
    }
}

/// A 1pt dotted rule under each receipt row.
private struct DottedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// Presents the system share sheet and reports whether something was
/// actually sent (false on cancel), which `ShareLink` can't tell us.
enum SharePresenter {
    static func share(_ items: [Any], completion: @escaping (Bool) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else {
            completion(false)
            return
        }
        while let presented = top.presentedViewController { top = presented }

        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        // iPad shows the sheet as a popover and needs an anchor.
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 120, width: 0, height: 0)
        }
        top.present(sheet, animated: true)
    }
}
