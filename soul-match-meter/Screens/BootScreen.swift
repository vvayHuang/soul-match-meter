import SwiftUI

/// 00 · BOOT — three beats in 2.4 s, or one tap to skip. Heat sources surface
/// at random, a full ramp sweeps up while the name types itself out, then the
/// ramp line under it collapses and the instrument hands over.
struct BootScreen: View {
    let model: MeterModel

    @State private var blobs: [HeatBlob] = []
    /// How many blobs have surfaced.
    @State private var shown = 0
    /// 1 heat sources · 2 ramp sweep and typing · 3 settled · 4 line collapsing.
    @State private var stage = 0
    /// Characters of the second title line typed so far.
    @State private var typed = 0
    @State private var tasks: [Task<Void, Never>] = []
    @State private var warmingCamera = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let secondLine = Array("METER · IR")

    var body: some View {
        GeometryReader { geo in
            ZStack {
                heatField(geo.size)

                Color(hex: 0x04060E, alpha: 0.45)

                // Keeps the status bar legible over the hottest blobs.
                LinearGradient(
                    colors: [Color(hex: 0x04060E, alpha: 0.7), Color(hex: 0x04060E, alpha: 0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 64)
                .frame(maxHeight: .infinity, alignment: .top)

                sweep(geo.size)

                ScanlineOverlay()

                if stage >= 2 {
                    nameplate
                        .padding(.horizontal, 18)
                        .padding(.top, 58)
                        .padding(.bottom, 30)
                }
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .contentShape(Rectangle())
        .onTapGesture { model.finishBoot() }
        .onAppear {
            // Bring the camera up behind the boot sequence, so home opens on
            // the live feed rather than its fallback still.
            warmingCamera = ThermalCamera.shared.warmUp()
            start()
        }
        .onDisappear {
            tasks.forEach { $0.cancel() }
            if warmingCamera { ThermalCamera.shared.stop() }
        }
    }

    // MARK: Beat 1 — heat sources

    private func heatField(_ size: CGSize) -> some View {
        // The field overhangs the screen by 40pt so edge blobs bleed off it.
        let width = size.width + 80
        let height = size.height + 80
        return ZStack {
            Color(hex: 0x0A1A6E)
            ForEach(Array(blobs.enumerated()), id: \.offset) { index, blob in
                let on = index < shown
                Circle()
                    .fill(RadialGradient(
                        stops: [
                            .init(color: blob.core, location: 0),
                            .init(color: blob.rim, location: 0.45),
                            .init(color: Color(hex: 0x0A1A6E, alpha: 0), location: 0.72),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: blob.size * 0.7071
                    ))
                    .frame(width: blob.size, height: blob.size)
                    .scaleEffect(on ? 1 : 0.4)
                    .animation(IR.hud(0.52), value: on)
                    .opacity(on ? 1 : 0)
                    .animation(IR.hud(0.42), value: on)
                    .position(x: width * blob.x, y: height * blob.y)
            }
        }
        .frame(width: width, height: height)
        .compositingGroup()
        .blur(radius: stage <= 1 ? 16 : (stage == 2 ? 12 : 10))
        .animation(IR.hud(0.6), value: stage)
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: Beat 2 — ramp sweep

    private func sweep(_ size: CGSize) -> some View {
        let bandHeight: CGFloat = 220
        // The band's top edge travels from 110% of the screen to -40%.
        let top = stage >= 2 ? -0.4 * size.height : 1.1 * size.height
        return LinearGradient(
            stops: [
                .init(color: Color(hex: 0x0A1A6E, alpha: 0), location: 0),
                .init(color: Color(hex: 0x1560B8), location: 0.18),
                .init(color: Color(hex: 0x2DD4D8), location: 0.32),
                .init(color: Color(hex: 0x7FD44E), location: 0.46),
                .init(color: Color(hex: 0xE8F06A), location: 0.58),
                .init(color: Color(hex: 0xF2F4F8), location: 0.68),
                .init(color: Color(hex: 0xE24A2B), location: 0.82),
                .init(color: Color(hex: 0xFFF2C8), location: 0.92),
                .init(color: Color(hex: 0xFFF2C8, alpha: 0), location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(width: size.width, height: bandHeight)
        .position(x: size.width / 2, y: top + bandHeight / 2)
        .animation(stage >= 2 ? IR.hud(0.8) : nil, value: stage >= 2)
        .opacity(stage == 2 ? 0.85 : 0)
        .animation(IR.hud(0.3), value: stage == 2)
        .blendMode(.screen)
        .allowsHitTesting(false)
    }

    // MARK: Beats 2–3 — the nameplate

    private var nameplate: some View {
        HudPlate(padX: 16, padY: 14) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: -3) {
                    Text("SOUL MATCH")
                    // Reserve the full line so the plate doesn't grow as it types.
                    ZStack(alignment: .leading) {
                        Text(String(Self.secondLine)).hidden()
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text(String(Self.secondLine.prefix(typed)))
                            if stage == 2 {
                                Rectangle()
                                    .fill(IR.primary)
                                    .frame(width: 11, height: 20)
                                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] - 2 }
                            }
                        }
                    }
                }
                .font(IR.mono(22, .semibold))
                .tracking(-0.5)
                .foregroundStyle(IR.primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("SOUL MATCH METER · IR")

                if stage >= 3 {
                    GeometryReader { geo in
                        LinearGradient(stops: IR.rampStops, startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.72, height: 2)
                            .scaleEffect(x: stage >= 4 ? 0 : 1, y: 1, anchor: .center)
                            .animation(IR.hud(0.38), value: stage >= 4)
                    }
                    .frame(height: 2)
                    .padding(.top, 12)
                    .accessibilityHidden(true)
                }

                Text("靈魂配對測量儀")
                    .font(IR.cjk(12.5, .bold))
                    .tracking(3.5)
                    .foregroundStyle(IR.onPlateVariant)
                    .opacity(stage >= 3 ? 1 : 0.35)
                    .animation(IR.hud(0.5), value: stage >= 3)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Timeline

    private func start() {
        blobs = (0..<40).map { _ in HeatBlob.random() }

        guard !reduceMotion else {
            // The finished frame, held, then on to 01 at 1.6 s.
            shown = blobs.count
            stage = 3
            typed = Self.secondLine.count
            model.armBoot(after: 1.6)
            return
        }

        stage = 1
        tasks = [
            // One heat source every 52 ms.
            Task {
                for count in 1...blobs.count {
                    try? await Task.sleep(for: .milliseconds(52))
                    guard !Task.isCancelled else { return }
                    shown = count
                }
            },
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                stage = 2
                // Type the second line, one character every 70 ms.
                for count in 1...Self.secondLine.count {
                    try? await Task.sleep(for: .milliseconds(70))
                    guard !Task.isCancelled else { return }
                    typed = count
                }
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                stage = 3
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                stage = 4
            },
        ]
    }
}

/// One radial heat source: a random spot, size and ramp colour, fading to a
/// colour two stops colder at its rim.
private struct HeatBlob {
    let x: Double
    let y: Double
    let size: CGFloat
    let core: Color
    let rim: Color

    private static let ramp: [UInt32] = [0x1560B8, 0x2DD4D8, 0x7FD44E, 0xE8F06A, 0xF2F4F8, 0xE24A2B, 0xFFF2C8]

    static func random() -> HeatBlob {
        let i = Int.random(in: 0..<ramp.count)
        return HeatBlob(
            x: Double(Int.random(in: 0...100)) / 100,
            y: Double(Int.random(in: 0...100)) / 100,
            size: CGFloat(Int.random(in: 120...340)),
            core: Color(hex: ramp[i]),
            rim: Color(hex: ramp[max(0, i - 2)])
        )
    }
}
