import SwiftUI

/// 主壳：对齐汽水——固定侧栏(bg) + 主区(surface，顶栏同色无分隔) + 通栏底栏。
struct ContentView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          SidebarView(model: model)

          ZStack(alignment: .top) {
            // 整列一块底，含红绿灯高度；顶栏控件叠在上面（对齐汽水无横分隔）。
            model.theme.surface.ignoresSafeArea()
            VStack(spacing: 0) {
              MainChromeBar(model: model)
              mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // tip 会向上溢出到主区，抬高 zIndex 以免被主区盖住。
        PlayerBarView(model: model)
          .zIndex(6)
      }

      TopMessageView(text: model.message)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, Theme.titleChromeHeight + Theme.spaceMD)
        .padding(.horizontal, Theme.spaceLG)
        .allowsHitTesting(false)
        .zIndex(5)

      if model.showQueue {
        // App 内点弹层外关闭；底栏可点。切到其它 macOS App 不关。
        Color.clear
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .contentShape(Rectangle())
          .padding(.bottom, Theme.playerHeight)
          .onTapGesture { model.showQueue = false }
          .zIndex(8)

        GeometryReader { geo in
          let topPad = Theme.titleChromeHeight + Theme.spaceSM
          let bottomPad = Theme.playerHeight + Theme.spaceSM
          let height = max(280, geo.size.height - topPad - bottomPad)
          QueuePopupView(model: model, maxHeight: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, Theme.spaceLG)
            .padding(.bottom, bottomPad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(
          .asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal: .opacity
          )
        )
        .zIndex(9)
      }

      if model.loginModalOpen {
        LoginModalView(model: model)
          .transition(.opacity)
          .zIndex(10)
      }
    }
    .environmentObject(model.theme)
    .background(model.theme.bg.ignoresSafeArea())
    .preferredColorScheme(model.theme.preferredColorScheme)
    .frame(minWidth: Theme.windowMinWidth, minHeight: Theme.windowMinHeight)
    // 内容伸进标题栏区：侧栏顶对齐红绿灯，主区顶栏与内容一体。
    .ignoresSafeArea(.container, edges: .top)
    .background(WindowChromeView(windowBackground: model.theme.surface))
    .animation(.easeInOut(duration: 0.2), value: model.loginModalOpen)
    .animation(.easeInOut(duration: 0.18), value: model.showQueue)
    // App 内切页关闭；不监听 NSApp resignActive，外切 App 保持打开。
    .onChange(of: model.nav) { _, _ in
      if model.showQueue { model.showQueue = false }
    }
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
    case .douyinLiked:
      DouyinLikedView(model: model)
    case .history:
      HistoryView(model: model)
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

/// 窗口顶部居中短时 message，不推挤布局；宽高随文案自适应，仅设上限。
struct TopMessageView: View {
  @EnvironmentObject private var theme: ThemeStore
  let text: String

  private static let maxBubbleWidth: CGFloat = 520

  var body: some View {
    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      ViewThatFits(in: .horizontal) {
        bubble(fixedHorizontally: true)
        bubble(fixedHorizontally: false)
          .frame(maxWidth: Self.maxBubbleWidth)
      }
      .frame(maxWidth: .infinity, alignment: .center)
      .transition(.opacity)
    }
  }

  @ViewBuilder
  private func bubble(fixedHorizontally: Bool) -> some View {
    Text(text)
      .font(.subheadline)
      .foregroundStyle(theme.text)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: fixedHorizontally, vertical: true)
      .padding(.horizontal, Theme.spaceMD)
      .padding(.vertical, Theme.spaceSM)
      .background(theme.surfaceElevated)
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .stroke(theme.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .shadow(color: .black.opacity(theme.mode == .dark ? 0.35 : 0.12), radius: 12, y: 4)
  }
}
