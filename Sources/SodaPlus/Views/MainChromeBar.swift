import AppKit
import SwiftUI

/// 主区顶栏：右对齐搜索 + 头像；背景跟主区 `surface`，无底部分隔线（对齐汽水）。
struct MainChromeBar: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore
  /// 点放大镜区域时请求聚焦；平时不占 first responder，避免空格被搜索框吃掉。
  @State private var searchFocusRequest = false
  /// Menu label 内 AsyncImage / 模板化 Image 在 macOS 常不显示；预载 NSImage 叠在 Menu 外。
  @State private var avatarImage: NSImage?

  private var controlSize: CGFloat { Theme.chromeControlSize }

  var body: some View {
    HStack(alignment: .center, spacing: Theme.spaceMD) {
      Spacer(minLength: 0)

      searchField
        .frame(width: 260)

      avatarMenu
    }
    .padding(.horizontal, Theme.spaceLG)
    .padding(.top, Theme.chromeTopInset)
    .padding(.bottom, Theme.spaceSM)
    .frame(maxWidth: .infinity, alignment: .trailing)
    // 背景由主列统一铺 `surface`，此处透明以免和内容接缝处色差/假分隔线。
    .task(id: model.account.avatar) {
      await loadAvatar()
    }
    .onChange(of: model.nav) { _, newNav in
      // 离开搜索结果页时收起输入态，空格回到播放快捷键。
      if newNav != .search {
        resignSearchFocus()
      }
    }
  }

  private var searchField: some View {
    HStack(spacing: Theme.spaceSM) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(theme.textFaint)
        .contentShape(Rectangle())
        .onTapGesture { searchFocusRequest = true }

      ChromeSearchField(
        text: $model.searchQuery,
        placeholder: "歌手、歌曲或专辑名",
        textColor: theme.text,
        placeholderColor: theme.textFaint,
        focusRequest: $searchFocusRequest,
        onSubmit: submitSearch
      )
    }
    .padding(.horizontal, Theme.spaceMD)
    .frame(height: controlSize)
    .background(theme.surfaceElevated)
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusPill, style: .continuous)
        .stroke(theme.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusPill, style: .continuous))
  }

  /// 可见头像在 Menu 外绘制；透明 Menu 只负责点击弹出，避免 label 被系统模板化吃掉。
  private var avatarMenu: some View {
    ZStack {
      avatarVisual

      Menu {
        if model.isLoggedIn {
          Text(model.account.nickname.isEmpty ? "已登录" : model.account.nickname)
          if model.account.vip {
            Text("VIP")
          }
          Divider()
          Button("设置") { model.selectNav(.settings) }
          Button("退出登录", role: .destructive) { model.logout() }
        } else {
          Button("登录") { model.openLoginModal() }
          Button("设置") { model.selectNav(.settings) }
        }
      } label: {
        Color.clear
          .frame(width: controlSize, height: controlSize)
          .contentShape(Circle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
    }
    .frame(width: controlSize, height: controlSize)
    .help(
      model.isLoggedIn ? (model.account.nickname.isEmpty ? "账号" : model.account.nickname) : "未登录")
  }

  @ViewBuilder
  private var avatarVisual: some View {
    if let avatarImage {
      Image(nsImage: avatarImage)
        .resizable()
        .renderingMode(.original)
        .scaledToFill()
        .frame(width: controlSize, height: controlSize)
        .clipShape(Circle())
    } else {
      placeholderAvatar
    }
  }

  private var placeholderAvatar: some View {
    Circle()
      .fill(theme.surfaceElevated)
      .overlay {
        if model.isLoggedIn, !model.account.nickname.isEmpty {
          Text(String(model.account.nickname.prefix(1)))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(theme.text)
        } else {
          Image(systemName: "person.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.textMuted)
        }
      }
      .overlay {
        Circle().stroke(theme.border, lineWidth: 1)
      }
      .frame(width: controlSize, height: controlSize)
  }

  private func loadAvatar() async {
    avatarImage = nil
    guard model.isLoggedIn, let url = model.account.avatarURL else { return }
    do {
      let (data, response) = try await URLSession.shared.data(from: url)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        print("[MainChromeBar] avatar HTTP \(http.statusCode) url=\(url.absoluteString)")
        return
      }
      guard let image = NSImage(data: data) else {
        print("[MainChromeBar] avatar decode failed url=\(url.absoluteString)")
        return
      }
      avatarImage = image
    } catch {
      print("[MainChromeBar] avatar load failed: \(error) url=\(url.absoluteString)")
    }
  }

  private func submitSearch() {
    let q = model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    model.selectNav(.search)
    resignSearchFocus()
    Task { await model.search() }
  }

  private func resignSearchFocus() {
    searchFocusRequest = false
    NSApp.keyWindow?.makeFirstResponder(nil)
  }
}
