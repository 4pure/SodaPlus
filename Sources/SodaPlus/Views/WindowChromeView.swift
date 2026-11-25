import AppKit
import SwiftUI

/// 主窗 AppKit chrome：无分隔线；矢量自绘红绿灯（避免 CATransform 位图放大在外接屏发糊）。
struct WindowChromeView: NSViewRepresentable {
  /// 相对系统默认再往下挪的点数。
  var trafficLightDownOffset: CGFloat = 6
  /// 关闭按钮的目标 leading（越大离左边越远）。
  var trafficLightLeading: CGFloat = 16
  /// 相对系统默认尺寸（约 12pt）的倍率。
  var trafficLightScale: CGFloat = 1.2
  /// 与主区同色，减轻透明标题栏下的材质色差。
  var windowBackground: Color = Color(nsColor: .windowBackgroundColor)

  func makeNSView(context: Context) -> ChromeProbeView {
    let view = ChromeProbeView()
    view.trafficLightDownOffset = trafficLightDownOffset
    view.trafficLightLeading = trafficLightLeading
    view.trafficLightScale = trafficLightScale
    view.windowBackground = NSColor(windowBackground)
    return view
  }

  func updateNSView(_ nsView: ChromeProbeView, context: Context) {
    nsView.trafficLightDownOffset = trafficLightDownOffset
    nsView.trafficLightLeading = trafficLightLeading
    nsView.trafficLightScale = trafficLightScale
    nsView.windowBackground = NSColor(windowBackground)
    nsView.apply()
  }
}

final class ChromeProbeView: NSView {
  var trafficLightDownOffset: CGFloat = 6
  var trafficLightLeading: CGFloat = 16
  var trafficLightScale: CGFloat = 1.2
  var windowBackground: NSColor = .windowBackgroundColor

  private var screenObserver: NSObjectProtocol?
  private var customLightsHost: TrafficLightsHostView?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    installScreenObserver()
    apply()
    DispatchQueue.main.async { [weak self] in
      self?.apply()
    }
  }

  override func layout() {
    super.layout()
    apply()
  }

  deinit {
    if let screenObserver {
      NotificationCenter.default.removeObserver(screenObserver)
    }
  }

  func apply() {
    guard let window else { return }
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    if !window.styleMask.contains(.fullSizeContentView) {
      window.styleMask.insert(.fullSizeContentView)
    }
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = true
    window.backgroundColor = windowBackground
    hideTitlebarMaterial(in: window)
    installCustomTrafficLights(in: window)
  }

  private func installScreenObserver() {
    if screenObserver != nil { return }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didChangeScreenNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      guard let self, let window = self.window, note.object as? NSWindow === window else {
        return
      }
      self.apply()
    }
  }

  /// 隐藏标题栏一带的 NSVisualEffectView，让侧栏 bg / 主区 surface 自己顶满。
  private func hideTitlebarMaterial(in window: NSWindow) {
    guard let themeFrame = window.contentView?.superview else { return }
    func walk(_ view: NSView, depth: Int) {
      guard depth < 12 else { return }
      if let effect = view as? NSVisualEffectView, effect.frame.height > 0,
        effect.frame.height <= 80
      {
        effect.isHidden = true
        effect.alphaValue = 0
      }
      for child in view.subviews {
        walk(child, depth: depth + 1)
      }
    }
    walk(themeFrame, depth: 0)
  }

  /// 藏起系统红绿灯，改用矢量按钮；随屏幕 backingScale 重绘，外接屏不发糊。
  private func installCustomTrafficLights(in window: NSWindow) {
    let ordered: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    let systemButtons = ordered.compactMap { window.standardWindowButton($0) }
    guard let sample = systemButtons.first, let container = sample.superview else { return }

    for button in systemButtons {
      button.isHidden = true
      button.alphaValue = 0
      button.isEnabled = false
    }

    let host: TrafficLightsHostView
    if let existing = customLightsHost, existing.superview === container {
      host = existing
    } else {
      customLightsHost?.removeFromSuperview()
      let created = TrafficLightsHostView(frame: .zero)
      container.addSubview(created)
      customLightsHost = created
      host = created
    }

    host.scale = trafficLightScale
    host.leading = trafficLightLeading
    host.downOffset = trafficLightDownOffset
    host.targetWindow = window
    host.layoutLights(in: container)
  }
}

// MARK: - Vector traffic lights

private final class TrafficLightsHostView: NSView {
  var scale: CGFloat = 1.2
  var leading: CGFloat = 16
  var downOffset: CGFloat = 6
  weak var targetWindow: NSWindow?

  private let closeButton = TrafficLightButton(kind: .close)
  private let miniaturizeButton = TrafficLightButton(kind: .miniaturize)
  private let zoomButton = TrafficLightButton(kind: .zoom)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    for button in [closeButton, miniaturizeButton, zoomButton] {
      addSubview(button)
      button.target = self
      button.action = #selector(trafficAction(_:))
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func layoutLights(in container: NSView) {
    // 系统默认约 12pt；间距约 8pt（origin 间距约 20）。
    let diameter = 12 * scale
    let gap = 8 * scale
    let totalWidth = diameter * 3 + gap * 2
    let containerH = container.bounds.height
    let y = max(0, (containerH - diameter) / 2 - downOffset)

    frame = NSRect(x: leading, y: y, width: totalWidth, height: diameter)

    closeButton.frame = NSRect(x: 0, y: 0, width: diameter, height: diameter)
    miniaturizeButton.frame = NSRect(
      x: diameter + gap, y: 0, width: diameter, height: diameter)
    zoomButton.frame = NSRect(
      x: (diameter + gap) * 2, y: 0, width: diameter, height: diameter)

    for button in [closeButton, miniaturizeButton, zoomButton] {
      button.needsDisplay = true
    }
  }

  @objc private func trafficAction(_ sender: TrafficLightButton) {
    guard let window = targetWindow ?? self.window else { return }
    switch sender.kind {
    case .close:
      window.performClose(nil)
    case .miniaturize:
      window.performMiniaturize(nil)
    case .zoom:
      window.performZoom(nil)
    }
  }
}

private final class TrafficLightButton: NSButton {
  enum Kind {
    case close
    case miniaturize
    case zoom
  }

  let kind: Kind
  private var hover = false

  init(kind: Kind) {
    self.kind = kind
    super.init(frame: .zero)
    isBordered = false
    title = ""
    image = nil
    wantsLayer = true
    // 矢量重绘，跟屏走 scale。
    layerContentsRedrawPolicy = .onSetNeedsDisplay
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    needsDisplay = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: bounds,
        options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
        owner: self,
        userInfo: nil
      )
    )
  }

  override func mouseEntered(with event: NSEvent) {
    hover = true
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    hover = false
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    let diameter = min(bounds.width, bounds.height)
    let inset = (max(bounds.width, bounds.height) - diameter) / 2
    let circle = NSRect(x: inset, y: inset, width: diameter, height: diameter)

    let fill: NSColor
    switch kind {
    case .close:
      fill = NSColor(srgbRed: 1, green: 0.38, blue: 0.35, alpha: 1)
    case .miniaturize:
      fill = NSColor(srgbRed: 1, green: 0.74, blue: 0.17, alpha: 1)
    case .zoom:
      fill = NSColor(srgbRed: 0.15, green: 0.78, blue: 0.35, alpha: 1)
    }

    fill.setFill()
    NSBezierPath(ovalIn: circle).fill()

    // 符号只在 hover 时画，接近系统行为；矢量路径随直径缩放。
    guard hover else { return }
    let symbol = NSColor.black.withAlphaComponent(0.55)
    symbol.setStroke()
    let line = max(1.0, diameter * 0.08)
    let pad = diameter * 0.28
    let path = NSBezierPath()
    path.lineWidth = line
    path.lineCapStyle = .round

    switch kind {
    case .close:
      path.move(to: CGPoint(x: circle.minX + pad, y: circle.minY + pad))
      path.line(to: CGPoint(x: circle.maxX - pad, y: circle.maxY - pad))
      path.move(to: CGPoint(x: circle.maxX - pad, y: circle.minY + pad))
      path.line(to: CGPoint(x: circle.minX + pad, y: circle.maxY - pad))
    case .miniaturize:
      let y = circle.midY
      path.move(to: CGPoint(x: circle.minX + pad, y: y))
      path.line(to: CGPoint(x: circle.maxX - pad, y: y))
    case .zoom:
      let mid = CGPoint(x: circle.midX, y: circle.midY)
      path.move(to: CGPoint(x: mid.x, y: circle.minY + pad))
      path.line(to: CGPoint(x: mid.x, y: circle.maxY - pad))
      path.move(to: CGPoint(x: circle.minX + pad, y: mid.y))
      path.line(to: CGPoint(x: circle.maxX - pad, y: mid.y))
    }
    path.stroke()
  }
}
