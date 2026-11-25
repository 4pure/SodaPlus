import SwiftUI

struct LibraryView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    Group {
      if let detail = model.playlistDetail {
        playlistDetail(detail)
      } else {
        emptyHint
      }
    }
    .background(theme.surface)
    .task {
      if model.isLoggedIn, model.playlists.isEmpty {
        await model.loadPlaylists()
      }
    }
  }

  private var emptyHint: some View {
    VStack(spacing: Theme.spaceMD) {
      Image(systemName: "music.note.list")
        .font(.system(size: 36))
        .foregroundStyle(theme.textFaint)
      Text("从左侧「创建的歌单」打开，或点 + 新建")
        .font(.subheadline)
        .foregroundStyle(theme.textMuted)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func playlistDetail(_ item: PlaylistItem) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: Theme.spaceMD) {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(theme.text)
          Text("\(model.playlistTracks.count) 首")
            .font(.subheadline)
            .foregroundStyle(theme.textMuted)
        }

        HStack(spacing: Theme.spaceMD) {
          PlayAllButton(count: model.playlistTracks.count) {
            model.playAll(model.playlistTracks)
          }
          Spacer(minLength: 0)
          Button("刷新") {
            Task { await model.openPlaylist(item) }
          }
          .buttonStyle(SodaSecondaryButtonStyle())
          .disabled(model.isBusy)
        }
      }
      .padding(Theme.spaceXL)

      TrackListView(
        tracks: model.playlistTracks,
        currentID: model.player.current?.id,
        likedIDs: model.likedIDs,
        onPlay: { model.playTrack($0, asQueue: model.playlistTracks) },
        onNext: { model.playNextInQueue($0) },
        onLike: { model.toggleLike($0) },
        onArtist: { model.openArtistFromTrack($0) },
        onAlbum: { model.openAlbumFromTrack($0) }
      )
    }
  }
}
