import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeImage {
  /// 对齐 SodaM：用 `scan_url`（服务端 qrcode_index_url 原样）编码二维码，不要改写 URL。
  static func make(from string: String, dimension: CGFloat = 360) -> NSImage? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(trimmed.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }

    let scaleX = dimension / output.extent.width
    let scaleY = dimension / output.extent.height
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    image.addRepresentation(rep)
    return image
  }
}
