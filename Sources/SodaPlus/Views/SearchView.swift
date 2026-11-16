import SwiftUI

struct SearchView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.spaceMD) {
        Text("搜索")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(Theme.text)
        HStack(spacing: Theme.spaceMD) {
          TextField("搜索歌名 / 歌手", text: $model.searchQuery)
            .textFieldStyle(.plain)
            .padding(.horizontal, Theme.spaceMD)
            .frame(height: Theme.control)
            .background(Theme.surfaceElevated)
            .overlay(
              RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
                .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
            .onSubmit { Task { await model.search() } }
          Button("搜索") { Task { await model.search() } }
            .buttonStyle(SodaPrimaryButtonStyle())
            .disabled(
              model.isBusy || model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
      .padding(Theme.spaceXL)

      TrackListView(
        tracks: model.searchTracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        emptyText: model.searchQuery.isEmpty ? "输入关键词开始搜索" : "无结果",
        onPlay: { model.playTrack($0, asQueue: model.searchTracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
    .background(Theme.surface)
  }
}
