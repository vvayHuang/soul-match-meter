import AVFoundation
import CoreImage
import Observation
import os
import QuartzCore
import SwiftUI
import Vision

/// Front camera → simulated thermal frames. There is no heat sensor on the
/// phone, so heat is inferred from what the subject *is*: background cold,
/// body warm, face hot, inner eye corners hottest, nose tip and hair cool.
/// The frame is then degraded the way a real microbolometer would be —
/// low resolution, diffusion blur, sensor noise, auto-ranging, and the odd
/// NUC freeze.
@Observable
final class ThermalCamera {
    static let shared = ThermalCamera()

    enum Status { case idle, running, unavailable }

    private(set) var frame: CGImage?
    private(set) var status: Status = .idle
    /// Bumps on every non-uniformity correction, for the shutter click.
    private(set) var nucTick = 0
    /// Reading under the spot point, in °C. Nil until the sensor has a frame.
    private(set) var spotTemperature: Double?
    /// The frame frozen when a measurement locks, for the receipt.
    /// Nil when the camera never produced one, so the receipt falls back to its still.
    private(set) var snapshot: CGImage?

    /// Where the thermal image is drawn, in global coordinates.
    @ObservationIgnored var imageRect: CGRect = .zero { didSet { updateSpot() } }
    /// The point to read (the crosshair centre), in global coordinates.
    @ObservationIgnored var spotPoint: CGPoint? { didSet { updateSpot() } }

    @ObservationIgnored private let pipeline: ThermalPipeline
    /// Screens currently showing the feed. Screens cross-fade, so the next one
    /// subscribes before the last lets go and the camera never drops out.
    @ObservationIgnored private var subscribers = 0

    private init() {
        pipeline = ThermalPipeline(lut: Self.makeLUT())
        pipeline.onFrame = { [weak self] image in
            Task { @MainActor in
                guard let self, self.subscribers > 0 else { return }
                self.frame = image
            }
        }
        pipeline.onNUC = { [weak self] in
            Task { @MainActor in self?.nucTick += 1 }
        }
        pipeline.onSpot = { [weak self] celsius in
            Task { @MainActor in
                guard let self, self.subscribers > 0 else { return }
                self.spotTemperature = celsius
            }
        }
    }

    private func updateSpot() {
        guard let spotPoint, imageRect.width > 0, imageRect.height > 0 else {
            return pipeline.setSpot(nil)
        }
        pipeline.setSpot(SIMD2(
            Float((spotPoint.x - imageRect.minX) / imageRect.width),
            Float((spotPoint.y - imageRect.minY) / imageRect.height)
        ))
    }

    func start() {
        subscribers += 1
        guard subscribers == 1 else { return }
        begin()
    }

    private func begin() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            pipeline.start { ok in
                Task { @MainActor in self.status = ok ? .running : .unavailable }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        if self.subscribers > 0 { self.begin() }
                    } else {
                        self.status = .unavailable
                    }
                }
            }
        default:
            status = .unavailable
        }
    }

    func takeSnapshot() {
        snapshot = frame
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        pipeline.stop()
        // Don't flash the last session's frame or reading on the next visit.
        frame = nil
        spotTemperature = nil
    }

    /// 256-entry RGBA lookup built from the design system's thermal ramp.
    private static func makeLUT() -> [UInt8] {
        let env = EnvironmentValues()
        let stops = IR.rampStops.map { stop -> (Double, Color.Resolved) in
            (stop.location, stop.color.resolve(in: env))
        }
        var lut = [UInt8](repeating: 255, count: 256 * 4)
        for i in 0..<256 {
            let t = Double(i) / 255
            var upper = stops.firstIndex { $0.0 >= t } ?? stops.count - 1
            upper = max(upper, 1)
            let (l0, c0) = stops[upper - 1]
            let (l1, c1) = stops[upper]
            let f = Float(l1 > l0 ? min(1, max(0, (t - l0) / (l1 - l0))) : 0)
            lut[i * 4 + 0] = UInt8(max(0, min(255, (c0.red + (c1.red - c0.red) * f) * 255)))
            lut[i * 4 + 1] = UInt8(max(0, min(255, (c0.green + (c1.green - c0.green) * f) * 255)))
            lut[i * 4 + 2] = UInt8(max(0, min(255, (c0.blue + (c1.blue - c0.blue) * f) * 255)))
        }
        return lut
    }
}

// MARK: - Pipeline

/// Capture and per-frame processing. Everything below runs on `videoQueue`
/// except session start/stop, which run on `sessionQueue`.
nonisolated final class ThermalPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// Sensor resolution, matching a 256×192 handheld core held in portrait.
    static let gridW = 192
    static let gridH = 256

    var onFrame: ((CGImage) -> Void)?
    var onNUC: (() -> Void)?
    var onSpot: ((Double) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "thermal.session")
    private let videoQueue = DispatchQueue(label: "thermal.video", qos: .userInitiated)
    private var configured = false

    private let ciContext = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()
    private let faceRequest = VNDetectFaceLandmarksRequest()

    private let lut: [UInt8]
    private var luma: [UInt8]
    private var mask: [UInt8]
    private var heat: [Float]
    private var scratch: [Float]
    /// Local average of the luma, for pulling facial structure out of the camera image.
    private var lumaMean: [Float]
    /// Column-wise fixed-pattern offsets, the faint vertical banding of a bolometer.
    private let fixedPattern: [Float]

    private var rangeLo: Float = 0.15
    private var rangeHi: Float = 0.9
    private var face = FaceHeat()
    private var rng = XorShift(seed: 0x9E37_79B9_7F4A_7C15)
    private var nextNUC: CFTimeInterval = 0
    private var frozenUntil: CFTimeInterval = 0
    /// Normalized read point, written from the main thread.
    private let spotLock = OSAllocatedUnfairLock<SIMD2<Float>?>(initialState: nil)
    private var spotCelsius: Float?

    init(lut: [UInt8]) {
        self.lut = lut
        let count = Self.gridW * Self.gridH
        luma = [UInt8](repeating: 0, count: count)
        mask = [UInt8](repeating: 0, count: count)
        heat = [Float](repeating: 0, count: count)
        scratch = [Float](repeating: 0, count: count)
        lumaMean = [Float](repeating: 0, count: count)
        var seed = XorShift(seed: 0xD1B5_4A32_D192_ED03)
        fixedPattern = (0..<Self.gridW).map { _ in (seed.unit() - 0.5) * 0.02 }
        super.init()
    }

    func start(_ completion: @escaping @Sendable (Bool) -> Void) {
        sessionQueue.async {
            if !self.configured {
                self.configured = self.configure()
            }
            guard self.configured else { return completion(false) }
            if !self.session.isRunning { self.session.startRunning() }
            completion(self.session.isRunning)
        }
    }

    func setSpot(_ point: SIMD2<Float>?) {
        spotLock.withLock { $0 = point }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() -> Bool {
        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            // Portrait, mirrored like a selfie so the subject moves the way they expect.
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        session.commitConfiguration()

        // Handheld thermal cores run at 9–15 Hz; the stutter is part of the look.
        if (try? device.lockForConfiguration()) != nil {
            let fps = CMTime(value: 1, timescale: 15)
            device.activeVideoMinFrameDuration = fps
            device.activeVideoMaxFrameDuration = fps
            device.unlockForConfiguration()
        }
        return true
    }

    // MARK: Frame

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // NUC: the shutter drops, the image holds still for a beat, then resumes.
        let now = CACurrentMediaTime()
        if nextNUC == 0 { nextNUC = now + Double.random(in: 6...10) }
        if now < frozenUntil { return }
        if now >= nextNUC {
            frozenUntil = now + 0.35
            nextNUC = now + Double.random(in: 9...16)
            onNUC?()
            return
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        try? handler.perform([segmentation, faceRequest])

        let frame = CIImage(cvPixelBuffer: pixelBuffer)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
        renderToGrid(frame, into: &luma)

        if let maskBuffer = segmentation.results?.first?.pixelBuffer {
            renderToGrid(CIImage(cvPixelBuffer: maskBuffer), into: &mask)
        }

        let largest = faceRequest.results?.max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
        face.update(with: largest, gridW: Float(Self.gridW), gridH: Float(Self.gridH))

        for i in 0..<lumaMean.count { lumaMean[i] = Float(luma[i]) / 255 }
        boxBlur(&lumaMean, radius: 4, passes: 2)

        buildHeat()
        boxBlur(&heat, radius: 1, passes: 2)
        readSpot()
        if let image = colorize() { onFrame?(image) }
    }

    /// Averages a 5×5 patch under the spot point, before sensor noise, and
    /// damps it so the digits settle like a meter instead of flickering.
    private func readSpot() {
        guard let p = spotLock.withLock({ $0 }), (0...1).contains(p.x), (0...1).contains(p.y) else { return }
        let w = Self.gridW, h = Self.gridH
        let cx = min(w - 1, Int(p.x * Float(w)))
        let cy = min(h - 1, Int(p.y * Float(h)))
        var sum: Float = 0
        var count: Float = 0
        for y in max(0, cy - 2)...min(h - 1, cy + 2) {
            for x in max(0, cx - 2)...min(w - 1, cx + 2) {
                sum += heat[y * w + x]
                count += 1
            }
        }
        let reading = Self.celsius(sum / count)
        let smoothed = spotCelsius.map { $0 + (reading - $0) * 0.25 } ?? reading
        spotCelsius = smoothed
        onSpot?(Double(smoothed))
    }

    /// Maps model heat onto a plausible room-and-skin scale: ~21 °C background,
    /// ~29 °C clothing, ~35 °C face, easing off toward ~37 °C at the eyes.
    private static func celsius(_ heat: Float) -> Float {
        let c = 17 + 23 * heat
        return c > 36 ? 36 + (c - 36) * 0.3 : c
    }

    /// Downsamples to sensor resolution and writes an 8-bit single channel, top row first.
    private func renderToGrid(_ image: CIImage, into buffer: inout [UInt8]) {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return }
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(
                scaleX: CGFloat(Self.gridW) / extent.width,
                y: CGFloat(Self.gridH) / extent.height
            ))
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            ciContext.render(
                scaled,
                toBitmap: base,
                rowBytes: Self.gridW,
                bounds: CGRect(x: 0, y: 0, width: Self.gridW, height: Self.gridH),
                format: .L8,
                colorSpace: nil
            )
        }
    }

    // MARK: Heat model

    private func buildHeat() {
        let w = Self.gridW, h = Self.gridH
        let f = face
        let a = f.alpha

        for y in 0..<h {
            let py = Float(y) + 0.5
            for x in 0..<w {
                let px = Float(x) + 0.5
                let i = y * w + x
                let l = Float(luma[i]) / 255
                let m = Float(mask[i]) / 255

                // Background sits cold; lamps and windows read a touch warmer.
                var t: Float = 0.12 + 0.10 * l
                // Clothed body: warm, with a little texture from the fabric.
                t += m * (0.34 + 0.05 * l)

                // High-pass of the camera image: brows, lash lines, nostrils and
                // the lip seam are darker than the skin around them and read cooler.
                let detail = l - lumaMean[i]
                t += m * 0.12 * detail

                if a > 0.001 {
                    // Face: flat-topped ellipse so cheeks read evenly hot.
                    let fx = (px - f.cx) / (f.w * 0.5)
                    let fy = (py - (f.cy + f.h * 0.04)) / (f.h * 0.62)
                    let fd = fx * fx + fy * fy
                    let faceWeight = a * m * expf(-fd * fd)
                    t += faceWeight * 0.26
                    // Features get extra contrast inside the face so it stays legible.
                    t += faceWeight * 0.55 * detail

                    // Lips run warm.
                    t += a * 0.07 * gauss(px, py, f.mouth, f.w * 0.2, f.h * 0.07)

                    // Neck and throat run as hot as the face.
                    let nx = (px - f.cx) / (f.w * 0.3)
                    let ny = (py - (f.cy + f.h * 0.78)) / (f.h * 0.35)
                    t += a * m * 0.18 * expf(-(nx * nx + ny * ny))

                    // Forehead glow.
                    let hx = (px - f.cx) / (f.w * 0.38)
                    let hy = (py - (f.cy - f.h * 0.3)) / (f.h * 0.16)
                    t += a * 0.06 * expf(-(hx * hx + hy * hy))

                    // Inner canthi are the hottest point on a face.
                    let er = f.w * 0.085
                    t += a * 0.22 * gauss(px, py, f.eyeL, er, er)
                    t += a * 0.22 * gauss(px, py, f.eyeR, er, er)

                    // Nose tip runs cool.
                    t -= a * 0.15 * gauss(px, py, f.nose, f.w * 0.11, f.h * 0.12)

                    // Hair insulates: cool cap above the hairline.
                    let hairline = f.cy - f.h * 0.52
                    if py < hairline {
                        let rise = min(1, (hairline - py) / (f.h * 0.2))
                        let side = (px - f.cx) / (f.w * 0.7)
                        t -= a * m * 0.24 * rise * expf(-side * side * side * side)
                    }
                }

                heat[i] = t
            }
        }
    }

    private func gauss(_ px: Float, _ py: Float, _ c: SIMD2<Float>, _ rx: Float, _ ry: Float) -> Float {
        let dx = (px - c.x) / rx
        let dy = (py - c.y) / ry
        return expf(-(dx * dx + dy * dy))
    }

    /// Separable box blur. Two passes approximate a Gaussian — heat diffuses.
    private func boxBlur(_ buffer: inout [Float], radius r: Int, passes: Int) {
        let w = Self.gridW, h = Self.gridH
        let norm = 1 / Float(2 * r + 1)
        for _ in 0..<passes {
            for y in 0..<h {
                let row = y * w
                for x in 0..<w {
                    var sum: Float = 0
                    for k in -r...r { sum += buffer[row + min(w - 1, max(0, x + k))] }
                    scratch[row + x] = sum * norm
                }
            }
            for y in 0..<h {
                for x in 0..<w {
                    var sum: Float = 0
                    for k in -r...r { sum += scratch[min(h - 1, max(0, y + k)) * w + x] }
                    buffer[y * w + x] = sum * norm
                }
            }
        }
    }

    /// Auto-range, add sensor noise, and map through the palette.
    private func colorize() -> CGImage? {
        let w = Self.gridW, h = Self.gridH

        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in heat {
            lo = min(lo, v)
            hi = max(hi, v)
        }
        // The span drifts toward the scene rather than snapping, like AGC.
        rangeLo += (lo - rangeLo) * 0.08
        rangeHi += (hi - rangeHi) * 0.08
        let span = max(rangeHi - rangeLo, 0.35)

        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let noise = (rng.unit() - 0.5) * 0.035 + fixedPattern[x]
                let t = min(1, max(0, (heat[i] - rangeLo) / span + noise))
                let li = Int(t * 255) * 4
                let o = i * 4
                rgba[o] = lut[li]
                rgba[o + 1] = lut[li + 1]
                rgba[o + 2] = lut[li + 2]
            }
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

// MARK: - Face tracking

/// Face geometry in sensor pixels (top-left origin), smoothed across frames
/// so the hot spots glide instead of jittering, and fade out when the face is lost.
nonisolated private struct FaceHeat {
    var alpha: Float = 0
    var cx: Float = 0, cy: Float = 0, w: Float = 1, h: Float = 1
    var eyeL = SIMD2<Float>(0, 0)
    var eyeR = SIMD2<Float>(0, 0)
    var nose = SIMD2<Float>(0, 0)
    var mouth = SIMD2<Float>(0, 0)

    mutating func update(with observation: VNFaceObservation?, gridW: Float, gridH: Float) {
        guard let observation else {
            alpha = max(0, alpha - 0.12)
            return
        }

        let box = observation.boundingBox
        func toGrid(_ p: CGPoint) -> SIMD2<Float> {
            // Landmark points are normalized to the box, origin bottom-left.
            let nx = Float(box.minX + p.x * box.width)
            let ny = Float(box.minY + p.y * box.height)
            return SIMD2(nx * gridW, (1 - ny) * gridH)
        }

        let tcx = Float(box.midX) * gridW
        let tcy = (1 - Float(box.midY)) * gridH
        let tw = Float(box.width) * gridW
        let th = Float(box.height) * gridH

        // Inner eye corner = the eye point closest to the face's midline.
        func innerCorner(_ region: VNFaceLandmarkRegion2D?, fallback: SIMD2<Float>) -> SIMD2<Float> {
            guard let points = region?.normalizedPoints, !points.isEmpty else { return fallback }
            return points.map(toGrid).min { abs($0.x - tcx) < abs($1.x - tcx) } ?? fallback
        }
        let landmarks = observation.landmarks
        let teyeL = innerCorner(landmarks?.leftEye, fallback: SIMD2(tcx - tw * 0.12, tcy - th * 0.08))
        let teyeR = innerCorner(landmarks?.rightEye, fallback: SIMD2(tcx + tw * 0.12, tcy - th * 0.08))
        var tnose = SIMD2(tcx, tcy + th * 0.12)
        if let points = landmarks?.nose?.normalizedPoints, !points.isEmpty {
            let grid = points.map(toGrid)
            tnose = grid.reduce(SIMD2<Float>(0, 0), +) / Float(grid.count)
        }
        var tmouth = SIMD2(tcx, tcy + th * 0.32)
        if let points = landmarks?.outerLips?.normalizedPoints, !points.isEmpty {
            let grid = points.map(toGrid)
            tmouth = grid.reduce(SIMD2<Float>(0, 0), +) / Float(grid.count)
        }

        let k: Float = alpha < 0.01 ? 1 : 0.4
        cx += (tcx - cx) * k
        cy += (tcy - cy) * k
        w += (tw - w) * k
        h += (th - h) * k
        eyeL += (teyeL - eyeL) * k
        eyeR += (teyeR - eyeR) * k
        nose += (tnose - nose) * k
        mouth += (tmouth - mouth) * k
        alpha = min(1, alpha + 0.2)
    }
}

nonisolated private struct XorShift {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    /// Uniform in 0..<1.
    mutating func unit() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)
    }
}
