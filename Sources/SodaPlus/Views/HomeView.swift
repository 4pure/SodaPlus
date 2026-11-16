import SwiftUI

struct HomeView: View {
  @ObservedObject var model: AppModel

  private var tracks: [SodaTrack] {
    model.homeTracks.isEmpty ? model.queue.tracks : model.homeTracks
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      pageHeader
      TrackListView(
        tracks: tracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        emptyText: model.isBusy ? "正在准备推荐队列…" : "暂无推荐，登录后自动加载",
        onPlay: { model.playTrack($0, asQueue: tracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
    .background(Theme.surface)
    .task {
      if model.isLoggedIn, model.homeTracks.isEmpty {
        await model.loadHome(reset: true)
      }
    }
  }

  private var pageHeader: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: Theme.spaceXS) {
        Text("来自汽水的推荐")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(Theme.text)
        Text(model.isLoggedIn ? "推荐队列" : "未登录：先在设置里扫码")
          .font(.subheadline)
          .foregroundStyle(Theme.textMuted)
      }
      Spacer()
      if model.isLoggedIn {
        Button("刷新") { Task { await model.loadHome(reset: true) } }
          .buttonStyle(SodaSecondaryButtonStyle())
          .disabled(model.isBusy)
        Button("加载更多") { Task { await model.loadHome(reset: false) } }
          .buttonStyle(SodaSecondaryButtonStyle())
          .disabled(model.isBusy)
      }
    }
    .padding(.horizontal, Theme.spaceXL)
    .padding(.top, Theme.spaceXL)
    .padding(.bottom, Theme.spaceLG)
    .background(Theme.surface)
  }
}
