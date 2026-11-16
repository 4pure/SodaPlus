import SwiftUI

/// 对齐 SodaM `Root::render` 主壳：
/// ```
/// VStack
///   HStack { Sidebar | Main | Queue? }
///   PlayerBar（通栏全宽）
/// + 状态行绝对定位在播放条上方
/// ```
struct ContentView: View {
  @ObservedObject var model: AppModel

  private let trafficLightInset: CGFloat = 28

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          SidebarView(model: model)
            .padding(.top, trafficLightInset)

          mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, trafficLightInset)

          if model.showQueue && model.nav != .nowPlaying {
            QueueDrawerView(model: model)
              .padding(.top, trafficLightInset)
              .transition(.move(edge: .trailing))
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        PlayerBarView(model: model)
      }

      StatusLineView(text: model.statusLine)
        .padding(.leading, Theme.sidebarWidth + Theme.spaceLG)
        .padding(.bottom, Theme.playerHeight + Theme.spaceSM)
        .allowsHitTesting(false)
        .zIndex(5)

      if model.loginModalOpen {
        LoginModalView(model: model)
          .transition(.opacity)
          .zIndex(10)
      }
    }
    .environmentObject(model.theme)
    .background(model.theme.bg)
    .preferredColorScheme(.dark)
    .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
    .animation(.easeInOut(duration: 0.2), value: model.loginModalOpen)
    .animation(.easeInOut(duration: 0.2), value: model.showQueue)
  }

  @ViewBuilder
  private var mainContent: some View {
    switch model.nav {
    case .home:
      HomeView(model: model)
    case .scenes:
      ScenesView(model: model)
    case .search:
      SearchView(model: model)
    case .liked:
      LikedView(model: model)
    case .library:
      LibraryView(model: model)
    case .settings:
      SettingsView(model: model)
    case .nowPlaying:
      NowPlayingView(model: model)
    case .artist:
      ArtistView(model: model)
    case .album:
      AlbumView(model: model)
    }
  }
}

/// 对齐 SodaM `ui/status_line`：播放栏上方左侧浮层，不推挤布局。
struct StatusLineView: View {
  @EnvironmentObject private var theme: ThemeStore
  let text: String

  var body: some View {
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      Text(text)
        .font(.subheadline)
        .foregroundStyle(theme.text)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, Theme.spaceMD)
        .padding(.vertical, Theme.spaceSM)
        .frame(maxWidth: 520, alignment: .leading)
        .background(theme.surfaceElevated)
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
            .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .transition(.opacity)
    }
  }
}
