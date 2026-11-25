import SwiftUI

/// 外观模式，存 `config.json` 的 `theme` 字符串（`light` / `dark`）。
enum AppearanceMode: String, CaseIterable, Identifiable, Hashable, Codable {
  case light
  case dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .light: return "浅色"
    case .dark: return "深色"
    }
  }

  var colorScheme: ColorScheme {
    switch self {
    case .light: return .light
    case .dark: return .dark
    }
  }

  static func from(stored: String) -> AppearanceMode {
    let value = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return AppearanceMode(rawValue: value) ?? .dark
  }
}

/// 对齐 SodaM `ui/theme.rs`：Light / Dark 色板 + 封面 ambient 染色。
@MainActor
final class ThemeStore: ObservableObject {
  @Published var mode: AppearanceMode = .dark
  @Published private(set) var ambient: AmbientColor.RGB?

  func setMode(_ mode: AppearanceMode) {
    guard self.mode != mode else { return }
    self.mode = mode
  }

  func setAmbient(_ rgb: AmbientColor.RGB?) {
    ambient = rgb
  }

  var preferredColorScheme: ColorScheme { mode.colorScheme }

  // MARK: Colors

  var bg: Color { wash(base: palette.bg) }
  var surface: Color { wash(base: palette.surface) }
  var surfaceElevated: Color { wash(base: palette.surfaceElevated) }
  var surfaceHover: Color { wash(base: palette.surfaceHover) }
  var surfaceSelected: Color { wash(base: palette.surfaceSelected) }
  var border: Color { wash(base: palette.border, amount: 0.40) }
  var text: Color { wash(base: palette.text, amount: 0.12) }
  var textMuted: Color { wash(base: palette.textMuted, amount: 0.12) }
  var textFaint: Color { wash(base: palette.textFaint, amount: 0.12) }

  var accent: Color {
    guard let ambient else { return palette.accent }
    return accentFrom(ambient, lightness: palette.accentLightness)
  }

  var accentForeground: Color {
    guard ambient != nil else { return palette.accentForeground }
    return mode == .dark ? Color(hex: 0x0A0A0A) : Color(hex: 0xFAFAFA)
  }

  var accentSoft: Color { accent.opacity(mode == .dark ? 0.16 : 0.12) }

  /// 歌词未点亮：同色相低饱和（对齐 lyric_dim）。
  var lyricDim: Color {
    guard let ambient else { return textMuted }
    let (h, s, l) = rgbToHSL(ambient.r, ambient.g, ambient.b)
    let sat = min(0.6, max(0, s) * 0.55) * 0.16
    let light: Double
    switch mode {
    case .dark:
      light = max(0.24, l * 0.62)
    case .light:
      light = min(0.55, max(0.38, l * 0.72))
    }
    return Color(hsl: h, saturation: sat, lightness: light)
  }

  var warning: Color { Color(hex: 0xF5A524) }
  var danger: Color { Color(hex: 0xF31260) }

  private var palette: Palette {
    mode == .dark ? .dark : .light
  }

  private func wash(base: Color, amount: Double = 0.50) -> Color {
    guard let ambient else { return base }
    let strength = mode == .dark ? amount * 0.35 : amount * 0.22
    return base.mixed(
      with: Color(red: ambient.r, green: ambient.g, blue: ambient.b), amount: strength)
      ?? base
  }

  private func accentFrom(_ rgb: AmbientColor.RGB, lightness: Double) -> Color {
    let (h, s, _) = rgbToHSL(rgb.r, rgb.g, rgb.b)
    let sat = min(0.85, max(0.60, s))
    return Color(hsl: h, saturation: sat, lightness: lightness)
  }

  private func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let maxv = max(r, max(g, b))
    let minv = min(r, min(g, b))
    let delta = maxv - minv
    let l = (maxv + minv) / 2
    let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
    let h: Double
    if delta == 0 {
      h = 0
    } else if maxv == r {
      h =
        (((g - b) / delta).truncatingRemainder(dividingBy: 6) + 6)
        .truncatingRemainder(dividingBy: 6) / 6
    } else if maxv == g {
      h = ((b - r) / delta + 2) / 6
    } else {
      h = ((r - g) / delta + 4) / 6
    }
    return (h, s, l)
  }
}

private struct Palette {
  let bg: Color
  let surface: Color
  let surfaceElevated: Color
  let surfaceHover: Color
  let surfaceSelected: Color
  let border: Color
  let text: Color
  let textMuted: Color
  let textFaint: Color
  let accent: Color
  let accentForeground: Color
  let accentLightness: Double

  static let dark = Palette(
    bg: Color(hex: 0x0A0A0A),
    surface: Color(hex: 0x101010),
    surfaceElevated: Color(hex: 0x171717),
    surfaceHover: Color(hex: 0x232323),
    surfaceSelected: Color(hex: 0x303030),
    border: Color(hex: 0x262626),
    text: Color(hex: 0xFAFAFA),
    textMuted: Color(hex: 0x737373),
    textFaint: Color(hex: 0x525252),
    accent: Color(hex: 0xFAFAFA),
    accentForeground: Color(hex: 0x171717),
    accentLightness: 0.72
  )

  static let light = Palette(
    bg: Color(hex: 0xF4F4F5),
    surface: Color(hex: 0xFAFAFA),
    surfaceElevated: Color(hex: 0xFFFFFF),
    surfaceHover: Color(hex: 0xE4E4E7),
    surfaceSelected: Color(hex: 0xD4D4D8),
    border: Color(hex: 0xE4E4E7),
    text: Color(hex: 0x18181B),
    textMuted: Color(hex: 0x71717A),
    textFaint: Color(hex: 0xA1A1AA),
    accent: Color(hex: 0x18181B),
    accentForeground: Color(hex: 0xFAFAFA),
    accentLightness: 0.38
  )
}

/// UI-SPEC 尺寸；静态色仅作无 ThemeStore 时的深色回退。
enum Theme {
  static let sidebarWidth: CGFloat = 216
  static let queueDrawerWidth: CGFloat = 360
  /// 对齐汽水底栏视觉体量（封面 + 控件 + 顶缘细进度条）。
  static let playerHeight: CGFloat = 88
  static let playerThumb: CGFloat = 56
  static let playerPlayButton: CGFloat = 48
  /// 顶栏大致高度（消息浮层 / 队列避让）：主区顶距 + 控件 + 底垫。
  static var titleChromeHeight: CGFloat { chromeTopInset + chromeControlSize + spaceSM }
  /// 主区顶栏相对窗顶内边距（搜索/头像与红绿灯带对齐）。
  static let chromeTopInset: CGFloat = 22
  /// 侧栏内容顶距：红绿灯整带之下再留空，避免品牌贴按钮。
  static let sidebarTopInset: CGFloat = 64
  /// 侧栏品牌图标边长；「SodaPlus」字号略小于此。
  static let sidebarBrandIcon: CGFloat = 36
  static let sidebarBrandFontSize: CGFloat = 22
  /// 顶栏搜索 / 头像同径。
  static let chromeControlSize: CGFloat = 32
  static let windowMinWidth: CGFloat = 900
  static let windowMinHeight: CGFloat = 560
  static let spaceXS: CGFloat = 4
  static let spaceSM: CGFloat = 8
  static let spaceMD: CGFloat = 12
  static let spaceLG: CGFloat = 16
  static let spaceXL: CGFloat = 24
  static let spaceXXL: CGFloat = 32
  static let radiusRow: CGFloat = 6
  static let radiusCard: CGFloat = 12
  static let radiusPill: CGFloat = 999
  static let icon: CGFloat = 16
  static let navRow: CGFloat = 36
  static let control: CGFloat = 36

  static let bg = Color(hex: 0x0A0A0A)
  static let surface = Color(hex: 0x101010)
  static let surfaceElevated = Color(hex: 0x171717)
  static let surfaceHover = Color(hex: 0x232323)
  static let surfaceSelected = Color(hex: 0x303030)
  static let border = Color(hex: 0x262626)
  static let text = Color(hex: 0xFAFAFA)
  static let textMuted = Color(hex: 0x737373)
  static let textFaint = Color(hex: 0x525252)
  static let accent = Color(hex: 0xFAFAFA)
  static let accentForeground = Color(hex: 0x171717)
  static let accentSoft = Color(hex: 0xFAFAFA).opacity(0.16)
  static let warning = Color(hex: 0xF5A524)
  static let danger = Color(hex: 0xF31260)
}

extension Color {
  init(hex: UInt32, alpha: Double = 1) {
    let r = Double((hex >> 16) & 0xFF) / 255
    let g = Double((hex >> 8) & 0xFF) / 255
    let b = Double(hex & 0xFF) / 255
    self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
  }

  init(hsl h: Double, saturation s: Double, lightness l: Double, opacity: Double = 1) {
    let c = (1 - abs(2 * l - 1)) * s
    let h6 = (h * 6).truncatingRemainder(dividingBy: 6)
    let x = c * (1 - abs(h6.truncatingRemainder(dividingBy: 2) - 1))
    let (r1, g1, b1): (Double, Double, Double)
    switch Int(h6) {
    case 0: (r1, g1, b1) = (c, x, 0)
    case 1: (r1, g1, b1) = (x, c, 0)
    case 2: (r1, g1, b1) = (0, c, x)
    case 3: (r1, g1, b1) = (0, x, c)
    case 4: (r1, g1, b1) = (x, 0, c)
    default: (r1, g1, b1) = (c, 0, x)
    }
    let m = l - c / 2
    self.init(.sRGB, red: r1 + m, green: g1 + m, blue: b1 + m, opacity: opacity)
  }

  func mixed(with other: Color, amount: Double) -> Color? {
    let t = min(max(amount, 0), 1)
    #if os(macOS)
      guard let a = NSColor(self).usingColorSpace(.sRGB),
        let b = NSColor(other).usingColorSpace(.sRGB)
      else { return nil }
      return Color(
        .sRGB,
        red: Double(a.redComponent) * (1 - t) + Double(b.redComponent) * t,
        green: Double(a.greenComponent) * (1 - t) + Double(b.greenComponent) * t,
        blue: Double(a.blueComponent) * (1 - t) + Double(b.blueComponent) * t,
        opacity: Double(a.alphaComponent) * (1 - t) + Double(b.alphaComponent) * t
      )
    #else
      return self
    #endif
  }

  func blended(with other: Color) -> Color? {
    mixed(with: other, amount: 0.5)
  }
}
