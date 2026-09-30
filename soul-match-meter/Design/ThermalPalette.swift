import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The false-colour palettes the instrument can render with. None of them
/// changes a result: they repaint the thermal image and the data ramps
/// (palette scale, receipt band, history thumbnails), nothing else.
enum ThermalPalette: String, CaseIterable, Identifiable {
    case iron = "鐵紅"
    case white = "白熱"
    case black = "黑熱"
    case rainbow = "彩虹"

    var id: Self { self }

    /// Cold (0) to hot (1).
    var stops: [Gradient.Stop] {
        switch self {
        case .iron:
            IR.rampStops
        case .white:
            [
                .init(color: Color(hex: 0x050608), location: 0),
                .init(color: Color(hex: 0xF5F6F8), location: 1),
            ]
        case .black:
            [
                .init(color: Color(hex: 0x8A8E96), location: 0),
                .init(color: Color(hex: 0x050608), location: 1),
            ]
        case .rainbow:
            [
                .init(color: Color(hex: 0x3B0A8C), location: 0),
                .init(color: Color(hex: 0x1E5BFF), location: 0.2),
                .init(color: Color(hex: 0x12C9A4), location: 0.4),
                .init(color: Color(hex: 0xE8E23A), location: 0.6),
                .init(color: Color(hex: 0xFF7A1A), location: 0.8),
                .init(color: Color(hex: 0xFF1F4B), location: 1),
            ]
        }
    }

    /// Cold at the bottom — the palette scale, history thumbnails.
    var vertical: LinearGradient {
        LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }

    /// Cold on the left — the receipt band.
    var horizontal: LinearGradient {
        LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    /// 256 RGBA entries, cold to hot, for colouring a heat map.
    var lut: [UInt8] {
        let env = EnvironmentValues()
        let resolved = stops.map { stop -> (Double, Color.Resolved) in
            (stop.location, stop.color.resolve(in: env))
        }
        var lut = [UInt8](repeating: 255, count: 256 * 4)
        for i in 0..<256 {
            let t = Double(i) / 255
            var upper = resolved.firstIndex { $0.0 >= t } ?? resolved.count - 1
            upper = max(upper, 1)
            let (l0, c0) = resolved[upper - 1]
            let (l1, c1) = resolved[upper]
            let f = Float(l1 > l0 ? min(1, max(0, (t - l0) / (l1 - l0))) : 0)
            lut[i * 4 + 0] = UInt8(max(0, min(255, (c0.red + (c1.red - c0.red) * f) * 255)))
            lut[i * 4 + 1] = UInt8(max(0, min(255, (c0.green + (c1.green - c0.green) * f) * 255)))
            lut[i * 4 + 2] = UInt8(max(0, min(255, (c0.blue + (c1.blue - c0.blue) * f) * 255)))
        }
        return lut
    }
}

extension EnvironmentValues {
    /// The palette the thermal image and data ramps are drawn in.
    @Entry var thermalPalette: ThermalPalette = .iron
}

/// A bundled scene still in the current palette. The stills are rendered in
/// iron; other palettes read each pixel's heat back off the iron ramp and
/// repaint it, so the scene always agrees with the palette scale.
struct SceneImage: View {
    let name: String

    @Environment(\.thermalPalette) private var palette

    var body: some View {
        if palette != .iron, let image = SceneRecolor.image(named: name, palette: palette) {
            Image(decorative: image, scale: 3)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
    }
}

/// Repaints iron-palette stills with a colour cube, cached per scene and palette.
private enum SceneRecolor {
    private static let cubeSize = 32
    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let context = CIContext()
    private static var images: [String: CGImage] = [:]
    private static var cubes: [ThermalPalette: Data] = [:]

    static func image(named name: String, palette: ThermalPalette) -> CGImage? {
        let key = "\(name)|\(palette.rawValue)"
        if let hit = images[key] { return hit }
        guard let source = UIImage(named: name)?.cgImage else { return nil }
        let input = CIImage(cgImage: source)
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = input
        filter.cubeDimension = Float(cubeSize)
        filter.cubeData = cube(for: palette)
        filter.colorSpace = sRGB
        guard let output = filter.outputImage,
              let image = context.createCGImage(output, from: input.extent) else { return nil }
        images[key] = image
        return image
    }

    /// For every colour in the cube: the nearest point on the iron ramp gives
    /// its heat, and the target palette gives the colour for that heat.
    private static func cube(for palette: ThermalPalette) -> Data {
        if let hit = cubes[palette] { return hit }
        let iron = ThermalPalette.iron.lut
        let target = palette.lut
        // Every 4th ramp entry is plenty to place a colour on the ramp.
        let samples = Array(stride(from: 0, to: 256, by: 4))
        let n = cubeSize
        let step = 255 / Float(n - 1)
        var values = [Float](repeating: 1, count: n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rv = Float(r) * step, gv = Float(g) * step, bv = Float(b) * step
                    var nearest = 0
                    var best = Float.greatestFiniteMagnitude
                    for i in samples {
                        let dr = rv - Float(iron[i * 4])
                        let dg = gv - Float(iron[i * 4 + 1])
                        let db = bv - Float(iron[i * 4 + 2])
                        let d = dr * dr + dg * dg + db * db
                        if d < best {
                            best = d
                            nearest = i
                        }
                    }
                    let o = ((b * n + g) * n + r) * 4
                    values[o] = Float(target[nearest * 4]) / 255
                    values[o + 1] = Float(target[nearest * 4 + 1]) / 255
                    values[o + 2] = Float(target[nearest * 4 + 2]) / 255
                }
            }
        }
        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        cubes[palette] = data
        return data
    }
}
