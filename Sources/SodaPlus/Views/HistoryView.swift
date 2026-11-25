import SwiftUI

struct HistoryView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.spaceMD) {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text("历史播放")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(theme.text)
          Text(
            model.historyTracks.isEmpty
              ? (model.isBusy
                ? "正在读取…"
                : (model.isLoggedIn ? "暂无记录" : "未登录"))
              : "\(model.historyTracks.count) 首"
          )
          .font(.subheadline)
          .foregroundStyle(theme.textMuted)
        }

        HStack(spacing: Theme.spaceMD) {
          PlayAllButton(count: model.historyTracks.count) {
            model.playAll(model.historyTracks)
          }
          Spacer(minLength: 0)
          Button("刷新") { Task { await model.loadHistory() } }
            .buttonStyle(SodaSecondaryButtonStyle())
            .disabled(!model.isLoggedIn)
        }
      }
      .padding(Theme.spaceXL)

      TrackListView(
        tracks: model.historyTracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        onPlay: { model.playTrack($0, asQueue: model.historyTracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
    .background(theme.surface)
    .task {
      if model.isLoggedIn { await model.loadHistory() }
    }
  }
}

struct DouyinLikedView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.spaceMD) {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text("抖音收藏的音乐")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(theme.text)
          Text(douyinLikedSubtitle)
            .font(.subheadline)
            .foregroundStyle(theme.textMuted)
        }

        HStack(spacing: Theme.spaceMD) {
          PlayAllButton(count: model.douyinLikedTracks.filter(\.playable).count) {
            model.playAll(model.douyinLikedTracks)
          }
          Spacer(minLength: 0)
          Button("刷新") { Task { await model.loadDouyinLiked() } }
            .buttonStyle(SodaSecondaryButtonStyle())
            .disabled(!model.isLoggedIn)
        }
      }
      .padding(Theme.spaceXL)

      TrackListView(
        tracks: model.douyinLikedTracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        onPlay: { model.playTrack($0, asQueue: model.douyinLikedTracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
    .background(theme.surface)
    .task {
      if model.isLoggedIn { await model.loadDouyinLiked() }
    }
  }

  private var douyinLikedSubtitle: String {
    if model.douyinLikedTracks.isEmpty {
      if model.isBusy { return "正在读取…" }
      return model.isLoggedIn ? "暂无歌曲" : "未登录"
    }
    let total = model.douyinLikedTracks.count
    let blocked = model.douyinLikedTracks.filter { !$0.playable }.count
    if blocked > 0 {
      return "\(total) 首 · \(blocked) 首不可播放"
    }
    return "\(total) 首"
  }
}
