import CoreMotion
import Observation
import SwiftUI

/// Device tilt as a normalized -1...1 offset, shared by every parallax layer.
/// The rest pose drifts toward however the phone is being held, so the field
/// recentres itself instead of sticking at an edge.
@Observable
final class MotionParallax {
    static let shared = MotionParallax()

    /// Normalized tilt, +x = right edge dipped, +y = top edge tipped away.
    private(set) var tilt: CGSize = .zero

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var subscribers = 0
    @ObservationIgnored private var rest: CGSize?

    /// Gravity delta (in g) that maps to full deflection.
    private let fullTilt: Double = 0.22
    /// Per-sample smoothing of the output; lower is calmer.
    private let smoothing: Double = 0.14
    /// Per-sample pull of the rest pose toward the current pose.
    private let restDrift: Double = 0.006

    private init() {}

    func start() {
        subscribers += 1
        guard subscribers == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.ingest(x: gravity.x, y: gravity.y)
        }
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        manager.stopDeviceMotionUpdates()
        rest = nil
        tilt = .zero
    }

    private func ingest(x: Double, y: Double) {
        var base = rest ?? CGSize(width: x, height: y)
        base.width += (x - base.width) * restDrift
        base.height += (y - base.height) * restDrift
        rest = base

        let targetX = clamp((x - base.width) / fullTilt)
        let targetY = clamp((y - base.height) / fullTilt)
        tilt = CGSize(
            width: tilt.width + (targetX - tilt.width) * smoothing,
            height: tilt.height + (targetY - tilt.height) * smoothing
        )
    }

    private func clamp(_ value: Double) -> Double { min(1, max(-1, value)) }
}

/// Shifts a layer with device tilt. A positive range moves with the tilt,
/// a negative range against it; the background and HUD use opposite signs
/// so the instrument face appears to float above the thermal scene.
private struct ParallaxOffset: ViewModifier {
    let range: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let tilt = reduceMotion ? .zero : MotionParallax.shared.tilt
        content
            .offset(x: tilt.width * range, y: -tilt.height * range)
            .onAppear { MotionParallax.shared.start() }
            .onDisappear { MotionParallax.shared.stop() }
    }
}

extension View {
    func parallax(_ range: CGFloat) -> some View {
        modifier(ParallaxOffset(range: range))
    }
}
