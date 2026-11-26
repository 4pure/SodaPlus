import AppKit
import SwiftUI

@main
struct SodaPlusApp: App {
  @StateObject private var model = AppModel()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("SodaPlus") {
      ContentView(model: model)
        .onAppear {
          appDelegate.model = model
          appDelegate.syncCloseWindowActionFromModel()
          AppDelegate.prepareMainWindowChrome()
          AppDelegate.showMainWindows()
        }
        .onChange(of: model.settings.closeWindowAction) { _, _ in
          appDelegate.syncCloseWindowActionFromModel()
        }
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 980, height: 640)
    .commands {
      CommandGroup(replacing: .newItem) {}
      CommandGroup(replacing: .appSettings) {
        Button("设置…") {
          AppDelegate.showMainWindows()
          model.selectNav(.settings)
        }
        .keyboardShortcut(",", modifiers: .command)
      }
      // 显式关窗：自绘红绿灯场景下系统 ⌘W 偶发灰掉，用主内容窗兜底。
      CommandGroup(replacing: .saveItem) {
        Button("关闭窗口") {
          AppDelegate.closeMainWindow()
        }
        .keyboardShortcut("w", modifiers: .command)
      }
      CommandMenu("播放") {
        Button(model.player.isPlaying ? "暂停" : "播放") {
          model.togglePlayPause()
        }
        .keyboardShortcut(.space, modifiers: [])
        Button("上一首") { model.playPrevious() }
          .keyboardShortcut(.leftArrow, modifiers: .command)
        Button("下一首") { model.playNext(userInitiated: true) }
          .keyboardShortcut(.rightArrow, modifiers: .command)
      }
    }

    MenuBarExtra {
      if let track = model.player.current {
        Text(track.title).font(.headline)
        Text(track.artist).foregroundStyle(.secondary)
        Divider()
      }
      Button(model.player.isPlaying ? "暂停" : "播放") {
        model.togglePlayPause()
      }
      Button("上一首") { model.playPrevious() }
      Button("下一首") { model.playNext(userInitiated: true) }
      Divider()
      Button("显示主窗口") {
        AppDelegate.showMainWindows()
      }
      Button("退出 SodaPlus") {
        NSApp.terminate(nil)
      }
    } label: {
      AppIcons.trayLabel
        .accessibilityLabel("SodaPlus")
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private(set) static weak var shared: AppDelegate?
  /// `orderOut` 后 `canBecomeMain` 可能变 false，需弱引用才能再显示。
  private static weak var retainedMainWindow: NSWindow?

  weak var model: AppModel?
  /// AppKit 回调里可读的关窗策略副本，避免跨 actor 读 `@MainActor` 的 settings。
  private(set) nonisolated(unsafe) var closeWindowAction: CloseWindowAction = .continueInBackground
  private var commandWMonitor: Any?

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.shared = self
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )
    // 兜底：系统 First Responder 的 performClose: 会拆掉 WindowGroup；后台续播应 orderOut。
    commandWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let isCommandW =
        event.modifierFlags.contains(.command)
        && !event.modifierFlags.contains(.shift)
        && !event.modifierFlags.contains(.option)
        && !event.modifierFlags.contains(.control)
        && (event.charactersIgnoringModifiers == "w" || event.charactersIgnoringModifiers == "W")
      guard isCommandW else { return event }
      AppDelegate.closeMainWindow()
      return nil
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let commandWMonitor {
      NSEvent.removeMonitor(commandWMonitor)
      self.commandWMonitor = nil
    }
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, Self.isMainContentWindow(window) else {
      return
    }
    Self.prepareMainWindowChrome()
  }

  nonisolated func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool
  {
    // 「退出应用」：红 X 关最后一窗即退出；「继续后台播放」：进程留下。
    closeWindowAction == .quit
  }

  nonisolated func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    DispatchQueue.main.async {
      AppDelegate.showMainWindows()
    }
    return true
  }

  @objc private nonisolated func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    // 「退出」路径交给 applicationShouldTerminateAfterLastWindowClosed，不再改 Dock。
    if closeWindowAction == .quit {
      return
    }
    DispatchQueue.main.async {
      guard Self.isMainContentWindow(window) else { return }
      // 排除正在关闭的窗，避免 willClose 当下仍算可见。
      AppDelegate.syncDockVisibility(excluding: window)
    }
  }

  func syncCloseWindowActionFromModel() {
    closeWindowAction = model?.settings.closeWindowAction ?? .continueInBackground
  }

  /// 隐藏标题栏 + 内容全出血；分隔线关闭、红绿灯放大由 `WindowChromeView` 持续施加。
  static func prepareMainWindowChrome() {
    for window in NSApp.windows where isMainContentWindow(window) {
      retainedMainWindow = window
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.styleMask.formUnion([
        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
      ])
      if !window.collectionBehavior.contains(.fullScreenPrimary) {
        window.collectionBehavior.insert(.fullScreenPrimary)
      }
      window.titlebarSeparatorStyle = .none
      window.isMovableByWindowBackground = true
      // 自绘红绿灯会藏系统按钮，但仍须保持可用以启用 ⌘W / 菜单「关闭」。
      for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
        if let button = window.standardWindowButton(type) {
          button.isEnabled = true
        }
      }
    }
  }

  /// 关闭 / 隐藏主内容窗（红灯、⌘W、菜单）。
  /// 「继续后台播放」用 `orderOut`，避免 SwiftUI WindowGroup 被拆掉后无法再显示。
  static func closeMainWindow() {
    prepareMainWindowChrome()
    if let window = NSApp.keyWindow, isMainContentWindow(window) {
      dismissMainWindow(window)
      return
    }
    for window in NSApp.windows where isMainContentWindow(window) && window.isVisible {
      dismissMainWindow(window)
      return
    }
    if let window = NSApp.keyWindow {
      dismissMainWindow(window)
    }
  }

  static func dismissMainWindow(_ window: NSWindow) {
    let action = shared?.closeWindowAction ?? .continueInBackground
    switch action {
    case .continueInBackground:
      // orderOut 保留 WindowGroup 实例；close 会拆场景导致无法再「显示主窗口」。
      retainedMainWindow = window
      window.orderOut(nil)
      syncDockVisibility()
    case .quit:
      window.close()
    }
  }

  /// 显示主窗口，并恢复 Dock 图标（从 accessory 切回 regular）。
  static func showMainWindows() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // 从 accessory 切回 regular 后，系统菜单栏偶发不刷新；轻推一次。
    NSMenu.setMenuBarVisible(false)
    NSMenu.setMenuBarVisible(true)

    prepareMainWindowChrome()

    var ordered = false
    if let retained = retainedMainWindow {
      retained.makeKeyAndOrderFront(nil)
      ordered = true
    }
    for window in NSApp.windows where isMainContentWindow(window) {
      window.makeKeyAndOrderFront(nil)
      retainedMainWindow = window
      ordered = true
    }
    if !ordered {
      // orderOut 后 canBecomeMain 可能为 false，按标题栏窗兜底找回。
      for window in NSApp.windows
      where !(window is NSPanel) && window.styleMask.contains(.titled) {
        let name = String(describing: type(of: window))
        if name.contains("StatusBar") || name.contains("MenuBarExtra") { continue }
        window.makeKeyAndOrderFront(nil)
        retainedMainWindow = window
        ordered = true
      }
    }
  }

  /// 无主窗口时隐藏 Dock；有主窗口时保持 regular。
  static func syncDockVisibility(excluding closing: NSWindow? = nil) {
    if hasVisibleMainWindow(excluding: closing) {
      if NSApp.activationPolicy() != .regular {
        NSApp.setActivationPolicy(.regular)
      }
    } else if NSApp.activationPolicy() != .accessory {
      NSApp.setActivationPolicy(.accessory)
    }
  }

  private static func hasVisibleMainWindow(excluding closing: NSWindow? = nil) -> Bool {
    NSApp.windows.contains { window in
      if let closing, window === closing { return false }
      return isMainContentWindow(window) && window.isVisible
    }
  }

  /// 主内容窗：排除菜单栏 Extra / StatusItem 弹出的面板。
  private static func isMainContentWindow(_ window: NSWindow) -> Bool {
    if window is NSPanel { return false }
    let name = String(describing: type(of: window))
    if name.contains("StatusBar") || name.contains("MenuBarExtra") { return false }
    return window.canBecomeMain && window.styleMask.contains(.titled)
  }
}
