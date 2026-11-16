import SwiftUI

/// 对齐 SodaM `ui/sidebar.rs`：品牌 + 浏览三项 +「我的音乐」+ 底部设置。
struct SidebarView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXS) {
      brand
        .padding(.bottom, Theme.spaceSM)

      navRow(.home)
      navRow(.scenes)
      navRow(.search)

      sectionLabel("我的音乐")
      navRow(.liked)
      navRow(.library)

      Spacer(minLength: 0)

      navRow(.settings)
    }
    .padding(.horizontal, Theme.spaceMD)
    .padding(.bottom, Theme.spaceMD)
    .padding(.top, Theme.spaceMD)
    .frame(width: Theme.sidebarWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(theme.bg)
    .overlay(alignment: .trailing) {
      Rectangle()
        .fill(theme.border)
        .frame(width: 1)
    }
  }

  private var brand: some View {
    HStack(spacing: Theme.spaceMD) {
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .fill(
          LinearGradient(
            colors: [theme.text, theme.textMuted],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: 28, height: 28)
        .overlay {
          Text("S")
            .font(.caption.weight(.bold))
            .foregroundStyle(theme.accentForeground)
        }
      Text("SodaPlus")
        .font(.title3.weight(.bold))
        .foregroundStyle(theme.text)
    }
    .padding(.horizontal, Theme.spaceMD)
    .padding(.vertical, Theme.spaceMD)
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.caption2)
      .foregroundStyle(theme.textFaint)
      .padding(.horizontal, Theme.spaceMD)
      .padding(.top, Theme.spaceLG)
      .padding(.bottom, Theme.spaceSM)
  }

  private func navRow(_ item: NavDestination) -> some View {
    let selected = isSelected(item)
    return Button {
      model.selectNav(item)
    } label: {
      HStack(spacing: Theme.spaceMD) {
        Image(systemName: item.systemImage)
          .font(.system(size: Theme.icon, weight: .medium))
          .foregroundStyle(selected ? theme.accent : theme.textMuted)
          .frame(width: 18)
        Text(sidebarTitle(item))
          .font(.body)
          .foregroundStyle(selected ? theme.text : theme.textMuted)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, Theme.spaceMD)
      .frame(height: Theme.navRow)
      .background(selected ? theme.surfaceSelected : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func isSelected(_ item: NavDestination) -> Bool {
    if item == .home {
      return model.nav == .home || model.nav == .nowPlaying
    }
    return model.nav == item
  }

  private func sidebarTitle(_ item: NavDestination) -> String {
    switch item {
    case .home: return "推荐"
    case .scenes: return "听歌模式"
    case .search: return "搜索"
    case .liked: return "我喜欢的音乐"
    case .library: return "我的歌单"
    case .settings: return "设置"
    case .nowPlaying: return "正在播放"
    case .artist: return "音乐人"
    case .album: return "专辑"
    }
  }
}
