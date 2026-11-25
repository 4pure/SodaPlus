import AppKit
import SwiftUI

/// 菜单栏黑色镂空模板托盘图。
enum AppIcons {
  /// 菜单栏用：黑色镂空模板（系统随外观着色）。
  static var trayNSImage: NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    var added = false
    for (name, points) in [("TrayIcon-16", 18.0), ("TrayIcon-32", 18.0)] {
      guard let url = resourceURL(name: name, ext: "png"),
        let base = NSImage(contentsOf: url),
        let rep = base.representations.first as? NSBitmapImageRep
      else { continue }
      rep.size = NSSize(width: points, height: points)
      image.addRepresentation(rep)
      added = true
    }
    if added {
      image.isTemplate = true
      return image
    }
    let fallback = NSImage(
      systemSymbolName: "plus",
      accessibilityDescription: "SodaPlus"
    )
    fallback?.isTemplate = true
    return fallback ?? NSImage(size: NSSize(width: 18, height: 18))
  }

  @ViewBuilder
  static var trayLabel: some View {
    Image(nsImage: trayNSImage)
      .renderingMode(.template)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(width: 18, height: 18)
  }

  private static func resourceURL(name: String, ext: String) -> URL? {
    if let url = Bundle.module.url(forResource: name, withExtension: ext) {
      return url
    }
    if let root = Bundle.module.resourceURL {
      let url = root.appendingPathComponent("\(name).\(ext)")
      if FileManager.default.fileExists(atPath: url.path) {
        return url
      }
    }
    return Bundle.main.url(forResource: name, withExtension: ext)
  }
}
