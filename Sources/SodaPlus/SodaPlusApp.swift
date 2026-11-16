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
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
          window.makeKeyAndOrderFront(nil)
        }
      }
      Button("退出 SodaPlus") {
        NSApp.terminate(nil)
      }
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  weak var model: AppModel?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(nil)
      }
    }
    return true
  }
}
