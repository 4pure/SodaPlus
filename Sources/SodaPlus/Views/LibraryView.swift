import SwiftUI

struct LibraryView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    Group {
      if let detail = model.playlistDetail {
        playlistDetail(detail)
      } else {
        playlistGrid
      }
    }
    .background(Theme.surface)
    .task {
      if model.isLoggedIn, model.playlists.isEmpty {
        await model.loadPlaylists()
      }
    }
  }

  private var playlistGrid: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceLG) {
        HStack {
          VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("我的歌单")
              .font(.largeTitle.weight(.bold))
              .foregroundStyle(Theme.text)
            Text(
              model.playlists.isEmpty
                ? (model.isLoggedIn ? "正在读取…" : "未登录：先在设置里扫码")
                : "\(model.playlists.count) 个歌单"
            )
            .font(.subheadline)
            .foregroundStyle(Theme.textMuted)
          }
          Spacer()
          Button("刷新") { Task { await model.loadPlaylists() } }
            .buttonStyle(SodaSecondaryButtonStyle())
            .disabled(model.isBusy || !model.isLoggedIn)
        }

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 140), spacing: Theme.spaceLG)],
          spacing: Theme.spaceLG
        ) {
          ForEach(model.playlists) { item in
            Button {
              Task { await model.openPlaylist(item) }
            } label: {
              VStack(alignment: .leading, spacing: Theme.spaceSM) {
                Group {
                  if let url = item.coverURL {
                    AsyncImage(url: url) { phase in
                      if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                      } else {
                        placeholder
                      }
                    }
                  } else {
                    placeholder
                  }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(item.title)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(Theme.text)
                  .lineLimit(2)
                Text("\(item.trackCount) 首")
                  .font(.caption)
                  .foregroundStyle(Theme.textMuted)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(Theme.spaceXL)
    }
  }

  private func playlistDetail(_ item: PlaylistItem) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Theme.spaceMD) {
        Button {
          model.playlistDetail = nil
          model.playlistTracks = []
        } label: {
          Label("返回", systemImage: "chevron.left")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textMuted)

        VStack(alignment: .leading, spacing: 2) {
          Text(item.title)
            .font(.title2.weight(.bold))
            .foregroundStyle(Theme.text)
          Text("\(model.playlistTracks.count) 首")
            .font(.subheadline)
            .foregroundStyle(Theme.textMuted)
        }
        Spacer()
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

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Theme.surfaceHover)
      .overlay {
        Image(systemName: "music.note.list")
          .foregroundStyle(Theme.textFaint)
      }
  }
}
