import CoreGraphics
import Foundation

/// The heat grid: a frozen thermal frame boiled down to 96 × 128 readings,
/// one byte each, cold (0) to hot (255), carried as base64. It is what the
/// two sides of a pair swap through the relay, and what the log keeps, so a
/// report can show both people. Same format as `web/js/heat.js`, so the app
/// and the web version read each other's.
nonisolated enum HeatGrid {
    static let width = 96
    static let height = 128
    /// The first grids (web only) were 48 × 64. One arriving still opens.
    private static let sizes = [(width, height), (48, 64)]

    private static let gridCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    )
    private static let keyCharacters = CharacterSet(charactersIn: "0123456789abcdef")

    /// The width and height of the grid a text of this length holds.
    private static func size(of text: String) -> (Int, Int)? {
        sizes.first { text.utf8.count == $0.0 * $0.1 * 4 / 3 }
    }

    static func isGrid(_ text: String?) -> Bool {
        guard let text, size(of: text) != nil else { return false }
        return text.unicodeScalars.allSatisfy(gridCharacters.contains)
    }

    /// A key the relay hands a grid out for: 128 random bits, hex.
    static func isKey(_ text: String?) -> Bool {
        guard let text, text.utf8.count == 32 else { return false }
        return text.unicodeScalars.allSatisfy(keyCharacters.contains)
    }

    static func newKey() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
    }

    /// Averages a `width` × `height` heat map down to the grid's readings.
    /// `low` and `span` are the range on screen when it was frozen, so the
    /// grid reads as the frame did.
    static func cells(heat: [Float], width w: Int, height h: Int, low: Float, span: Float) -> [UInt8] {
        let stepX = w / width, stepY = h / height
        let norm = 1 / Float(stepX * stepY)
        var cells = [UInt8](repeating: 0, count: width * height)
        for gy in 0..<height {
            for gx in 0..<width {
                var sum: Float = 0
                for y in gy * stepY..<(gy + 1) * stepY {
                    for x in gx * stepX..<(gx + 1) * stepX { sum += heat[y * w + x] }
                }
                let t = min(1, max(0, (sum * norm - low) / span))
                cells[gy * width + gx] = UInt8((t * 255).rounded())
            }
        }
        return cells
    }

    static func pack(_ cells: [UInt8]) -> String {
        Data(cells).base64EncodedString()
    }

    /// The grid's readings and its size, or nil when the text isn't one.
    static func unpack(_ text: String) -> (cells: [UInt8], width: Int, height: Int)? {
        guard isGrid(text), let (w, h) = size(of: text), let data = Data(base64Encoded: text),
              data.count == w * h else { return nil }
        return ([UInt8](data), w, h)
    }

    // MARK: Painting

    /// Drawn at the sensor's resolution, like the frame the grid came from.
    private static let paintW = ThermalPipeline.gridW
    private static let paintH = ThermalPipeline.gridH

    /// The grid as an image in a palette's lookup (`ThermalPalette.lut`),
    /// stretched to sensor resolution by blending between readings.
    static func image(_ text: String, lut: [UInt8]) -> CGImage? {
        guard let (cells, gw, gh) = unpack(text), lut.count >= 256 * 4 else { return nil }
        let w = paintW, h = paintH
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let fy = min(Float(gh - 1), max(0, (Float(y) + 0.5) * Float(gh) / Float(h) - 0.5))
            let y0 = Int(fy), y1 = min(gh - 1, y0 + 1)
            let wy = fy - Float(y0)
            for x in 0..<w {
                let fx = min(Float(gw - 1), max(0, (Float(x) + 0.5) * Float(gw) / Float(w) - 0.5))
                let x0 = Int(fx), x1 = min(gw - 1, x0 + 1)
                let wx = fx - Float(x0)
                let top = Float(cells[y0 * gw + x0]) * (1 - wx) + Float(cells[y0 * gw + x1]) * wx
                let bottom = Float(cells[y1 * gw + x0]) * (1 - wx) + Float(cells[y1 * gw + x1]) * wx
                // The same sensor noise the live feed carries.
                let noise = (Float.random(in: 0..<1) - 0.5) * 0.035
                let t = min(1, max(0, (top * (1 - wy) + bottom * wy) / 255 + noise))
                let li = Int(t * 255) * 4
                let o = (y * w + x) * 4
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

/// Grids painted once and kept: a report shows the same two over and over.
@MainActor
enum HeatFrames {
    private static var images: [String: CGImage] = [:]

    static func image(_ grid: String?, palette: ThermalPalette) -> CGImage? {
        guard let grid else { return nil }
        let key = "\(palette.rawValue)|\(grid)"
        if let hit = images[key] { return hit }
        guard let image = HeatGrid.image(grid, lut: palette.lut) else { return nil }
        if images.count >= 16 { images.removeAll() }
        images[key] = image
        return image
    }
}
