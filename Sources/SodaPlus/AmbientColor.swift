import AppKit
import Foundation

/// 对齐 SodaM `sodam-core/color.rs`：封面主色提取（HSL 色相桶）。
enum AmbientColor {
  typealias RGB = (r: Double, g: Double, b: Double)

  private static let binCount = 24
  private static let samples = 6000
  private static let minAlpha: UInt8 = 128
  private static let minSaturation: Float = 0.14
  private static let minLightness: Float = 0.20
  private static let maxLightness: Float = 0.94
  private static let minShare: Float = 0.015

  static func dominant(from image: NSImage) -> RGB? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return nil }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard
      let ctx = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return nil
    }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

    let pixelCount = width * height
    let stride = max(1, pixelCount / samples)
    var bins = Array(repeating: Bin(), count: binCount)
    var sampled: Float = 0

    var i = 0
    while i < pixelCount {
      let offset = i * 4
      let r = pixels[offset]
      let g = pixels[offset + 1]
      let b = pixels[offset + 2]
      let a = pixels[offset + 3]
      if a >= minAlpha {
        sampled += 1
        let hsl = rgbToHSL(r, g, b)
        if hsl.s >= minSaturation, hsl.l >= minLightness, hsl.l <= maxLightness {
          let index = min(Int(hsl.h * Float(binCount)), binCount - 1)
          let weight = hsl.s * (1 - abs(hsl.l - 0.5))
          bins[index].add(hsl, weight: weight)
        }
      }
      i += stride
    }

    guard let peak = (0..<binCount).max(by: { score(bins, $0) < score(bins, $1) }) else {
      return nil
    }
    if score(bins, peak) < sampled * minShare {
      return nil
    }
    var cluster = bins[peak]
    cluster.merge(bins[(peak + binCount - 1) % binCount])
    cluster.merge(bins[(peak + 1) % binCount])
    guard let colour = cluster.colour() else { return nil }
    return hslToRGB(colour.h, colour.s, colour.l)
  }

  static func dominant(fromURL url: URL) async -> RGB? {
    await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        guard let image = NSImage(contentsOf: url) else {
          continuation.resume(returning: nil)
          return
        }
        continuation.resume(returning: dominant(from: image))
      }
    }
  }

  private struct HSL {
    var h: Float
    var s: Float
    var l: Float
  }

  private struct Bin {
    var weight: Float = 0
    var x: Float = 0
    var y: Float = 0
    var saturation: Float = 0
    var lightness: Float = 0

    mutating func add(_ color: HSL, weight: Float) {
      let angle = color.h * Float.pi * 2
      self.weight += weight
      x += cos(angle) * weight
      y += sin(angle) * weight
      saturation += color.s * weight
      lightness += color.l * weight
    }

    mutating func merge(_ other: Bin) {
      weight += other.weight
      x += other.x
      y += other.y
      saturation += other.saturation
      lightness += other.lightness
    }

    func colour() -> HSL? {
      guard weight > 0 else { return nil }
      let h = atan2(y, x).truncatingRemainder(dividingBy: Float.pi * 2)
      let hue = ((h < 0 ? h + Float.pi * 2 : h) / (Float.pi * 2))
      return HSL(
        h: hue,
        s: (saturation / weight).clamped(to: 0...1),
        l: (lightness / weight).clamped(to: 0...1)
      )
    }
  }

  private static func score(_ bins: [Bin], _ index: Int) -> Float {
    bins[index].weight
      + (bins[(index + bins.count - 1) % bins.count].weight
        + bins[(index + 1) % bins.count].weight) * 0.5
  }

  private static func rgbToHSL(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> HSL {
    let rf = Float(r) / 255
    let gf = Float(g) / 255
    let bf = Float(b) / 255
    let maxv = max(rf, max(gf, bf))
    let minv = min(rf, min(gf, bf))
    let delta = maxv - minv
    let lightness = (maxv + minv) / 2
    let saturation: Float = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
    let hue: Float
    if delta == 0 {
      hue = 0
    } else if maxv == rf {
      hue =
        (((gf - bf) / delta).truncatingRemainder(dividingBy: 6) + 6)
        .truncatingRemainder(dividingBy: 6) / 6
    } else if maxv == gf {
      hue = ((bf - rf) / delta + 2) / 6
    } else {
      hue = ((rf - gf) / delta + 4) / 6
    }
    return HSL(h: hue, s: saturation, l: lightness)
  }

  private static func hslToRGB(_ h: Float, _ s: Float, _ l: Float) -> RGB {
    let chroma = (1 - abs(2 * l - 1)) * s
    let hue = (h * 6).truncatingRemainder(dividingBy: 6)
    let x = chroma * (1 - abs(hue.truncatingRemainder(dividingBy: 2) - 1))
    let (r1, g1, b1): (Float, Float, Float)
    switch Int(hue) {
    case 0: (r1, g1, b1) = (chroma, x, 0)
    case 1: (r1, g1, b1) = (x, chroma, 0)
    case 2: (r1, g1, b1) = (0, chroma, x)
    case 3: (r1, g1, b1) = (0, x, chroma)
    case 4: (r1, g1, b1) = (x, 0, chroma)
    default: (r1, g1, b1) = (chroma, 0, x)
    }
    let m = l - chroma / 2
    return (Double(r1 + m), Double(g1 + m), Double(b1 + m))
  }
}

extension Comparable {
  fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}
