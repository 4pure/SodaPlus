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

    MenuBarExtra("SodaPlus", systemImage: "music.note") {
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
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?
  /// AppKit 回调里可读的关窗策略副本，避免跨 actor 读 `@MainActor` 的 settings。
  private(set) nonisolated(unsafe) var closeWindowAction: CloseWindowAction = .continueInBackground

  func applicationDidFinishLaunching(_ notification: Notification) {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowWillClose(_:)),
      name: NSWindow.willCloseNotification,
      object: nil
    )
  }

  func applicationWillTerminate(_ notification: Notification) {
    NotificationCenter.default.removeObserver(self)
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

  /// 显示主窗口，并恢复 Dock 图标（从 accessory 切回 regular）。
  static func showMainWindows() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    // 从 accessory 切回 regular 后，系统菜单栏偶发不刷新；轻推一次。
    NSMenu.setMenuBarVisible(false)
    NSMenu.setMenuBarVisible(true)

    var ordered = false
    for window in NSApp.windows where isMainContentWindow(window) {
      window.makeKeyAndOrderFront(nil)
      ordered = true
    }
    if !ordered {
      for window in NSApp.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(nil)
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
