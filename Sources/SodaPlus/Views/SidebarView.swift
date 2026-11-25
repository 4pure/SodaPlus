import SwiftUI

/// 对齐汽水侧栏：品牌 + 浏览 + 我的音乐 + 创建的歌单（含新建）。
struct SidebarView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore
  @State private var createName = ""
  @State private var showCreateSheet = false

  var body: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXS) {
      brand
        .padding(.bottom, Theme.spaceXL)

      navRow(.home)
      navRow(.scenes)

      sectionLabel("我的音乐")
      ForEach(NavDestination.myMusicItems) { item in
        navRow(item)
      }

      createdPlaylistsHeader
      ForEach(model.createdPlaylists) { item in
        playlistRow(item)
      }

      Spacer(minLength: 0)
    }
    // 顶距加在整栏上：留给红绿灯 + 与按钮的间隙，品牌不贴顶。
    .padding(.top, Theme.sidebarTopInset)
    .padding(.horizontal, Theme.spaceMD)
    .padding(.bottom, Theme.spaceMD)
    .frame(width: Theme.sidebarWidth, alignment: .topLeading)
    .frame(maxHeight: .infinity, alignment: .top)
    // 侧栏色顶满红绿灯一带；与主区靠色差分区，不要系统折叠钮。
    .background(theme.bg.ignoresSafeArea())
    .sheet(isPresented: $showCreateSheet) {
      createPlaylistSheet
    }
    .task {
      if model.isLoggedIn, model.playlists.isEmpty {
        await model.loadPlaylists()
      }
    }
  }

  private var brand: some View {
    // 与导航行同左缘；仅文案，不再塞品牌图标。
    HStack(spacing: Theme.spaceMD) {
      Text("SodaPlus")
        .font(.system(size: Theme.sidebarBrandFontSize, weight: .bold))
        .foregroundStyle(theme.text)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.spaceMD)
    .frame(height: Theme.sidebarBrandIcon, alignment: .center)
  }

  private var createdPlaylistsHeader: some View {
    HStack(spacing: Theme.spaceSM) {
      Text("创建的歌单")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.textFaint)
      Spacer(minLength: 0)
      Button {
        createName = ""
        showCreateSheet = true
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.textMuted)
          .frame(width: 20, height: 20)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!model.isLoggedIn || model.isBusy)
      .help("新建歌单")
    }
    .padding(.horizontal, Theme.spaceMD)
    .padding(.top, Theme.spaceLG)
    .padding(.bottom, Theme.spaceSM)
  }

  private var createPlaylistSheet: some View {
    VStack(alignment: .leading, spacing: Theme.spaceLG) {
      Text("新建歌单")
        .font(.headline)
      TextField("歌单名称", text: $createName)
        .textFieldStyle(.roundedBorder)
        .onSubmit { confirmCreate() }
      HStack {
        Spacer()
        Button("取消") { showCreateSheet = false }
          .buttonStyle(SodaSecondaryButtonStyle())
        Button("创建") { confirmCreate() }
          .buttonStyle(SodaPrimaryButtonStyle())
          .disabled(
            createName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isBusy)
      }
    }
    .padding(Theme.spaceXL)
    .frame(width: 360)
  }

  private func confirmCreate() {
    let name = createName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    showCreateSheet = false
    Task { await model.createPlaylist(name: name) }
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13, weight: .medium))
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
        Group {
          if let kind = SidebarIconKind(destination: item) {
            SidebarIcon(kind: kind)
          } else {
            Image(systemName: item.systemImage)
              .font(.system(size: Theme.icon, weight: .medium))
          }
        }
        .foregroundStyle(selected ? theme.accent : theme.textMuted)
        .frame(width: 18)
        Text(item.title)
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

  private func playlistRow(_ item: PlaylistItem) -> some View {
    let selected =
      model.nav == .library && model.playlistDetail?.id == item.id
    return Button {
      Task { await model.openPlaylist(item) }
    } label: {
      HStack(spacing: Theme.spaceMD) {
        SidebarIcon(kind: .playlist)
          .foregroundStyle(selected ? theme.accent : theme.textMuted)
          .frame(width: 18)
        Text(item.title)
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
}
