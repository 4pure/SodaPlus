import SwiftUI

struct LikedView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.spaceMD) {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text("我喜欢的音乐")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(theme.text)
          Text(
            model.likedTracks.isEmpty
              ? (model.isLoggedIn ? "正在读取…" : "未登录：先在设置里扫码")
              : "\(model.likedTracks.count) 首"
          )
          .font(.subheadline)
          .foregroundStyle(theme.textMuted)
        }

        HStack(spacing: Theme.spaceMD) {
          PlayAllButton(count: model.likedTracks.count) {
            model.playAll(model.likedTracks)
          }
          Spacer(minLength: 0)
          Button("刷新") { Task { await model.loadLiked() } }
            .buttonStyle(SodaSecondaryButtonStyle())
            .disabled(!model.isLoggedIn)
        }
      }
      .padding(Theme.spaceXL)

      TrackListView(
        tracks: model.likedTracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        emptyText: model.isLoggedIn ? "还没有喜欢的歌" : "请先登录",
        onPlay: { model.playTrack($0, asQueue: model.likedTracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
    .background(theme.surface)
    .task {
      if model.isLoggedIn { await model.loadLiked() }
    }
  }
}
