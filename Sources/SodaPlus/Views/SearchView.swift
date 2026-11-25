import SwiftUI

struct SearchView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.spaceXS) {
        Text("搜索")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(theme.text)
        Text(
          model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "在右上角输入关键词"
            : "关键词：\(model.searchQuery)"
        )
        .font(.subheadline)
        .foregroundStyle(theme.textMuted)
      }
      .padding(Theme.spaceXL)

      TrackListView(
        tracks: model.searchTracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        emptyText: model.searchQuery.isEmpty ? "在右上角搜索框输入后回车" : "无结果",
        onPlay: { model.playTrack($0, asQueue: model.searchTracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
    .background(theme.surface)
  }
}
