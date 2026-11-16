import SwiftUI

/// 对齐 SodaM 音乐人页：头像、热歌、专辑入口。
struct ArtistView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      backBar
      if model.detailLoading && model.openArtist == nil {
        loading
      } else if let error = nonEmpty(model.detailError), model.openArtist == nil {
        errorState(error)
      } else if let detail = model.openArtist {
        header(detail)
        TrackListView(
          tracks: detail.tracks,
          currentID: model.player.current?.id,
          likedIDs: model.likedIDs,
          emptyText: "暂无热歌",
          onPlay: { model.playTrack($0, asQueue: detail.tracks) },
          onNext: { model.playNextInQueue($0) },
          onLike: { model.toggleLike($0) },
          onArtist: { model.openArtistFromTrack($0) },
          onAlbum: { model.openAlbumFromTrack($0) }
        )
        if !detail.albums.isEmpty {
          albumsSection(detail.albums)
            .frame(height: 160)
        }
      } else {
        empty
      }
    }
    .background(model.theme.surface)
  }

  private var backBar: some View {
    HStack {
      Button {
        model.backFromDetail()
      } label: {
        Label("返回", systemImage: "chevron.left")
          .foregroundStyle(model.theme.text)
      }
      .buttonStyle(.plain)
      Spacer()
    }
    .padding(.horizontal, Theme.spaceXL)
    .padding(.vertical, Theme.spaceMD)
  }

  private func header(_ detail: ArtistDetailPage) -> some View {
    HStack(alignment: .center, spacing: Theme.spaceLG) {
      cover(url: detail.artist.avatarURL, size: 96)
      VStack(alignment: .leading, spacing: Theme.spaceXS) {
        Text(detail.artist.name)
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(model.theme.text)
        Text(
          "\(compact(detail.artist.followerCount))人关注 · \(compact(max(detail.artist.trackCount, detail.tracks.count)))首歌"
        )
        .font(.subheadline)
        .foregroundStyle(model.theme.textMuted)
        if !detail.description.isEmpty {
          Text(detail.description)
            .font(.caption)
            .foregroundStyle(model.theme.textFaint)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.spaceXL)
    .padding(.bottom, Theme.spaceLG)
  }

  private func albumsSection(_ albums: [AlbumItem]) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceSM) {
      Text("专辑")
        .font(.headline)
        .foregroundStyle(model.theme.text)
        .padding(.horizontal, Theme.spaceXL)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Theme.spaceMD) {
          ForEach(albums) { album in
            Button {
              model.openAlbumPage(id: album.id, titleHint: album.title)
            } label: {
              VStack(alignment: .leading, spacing: Theme.spaceXS) {
                cover(url: album.coverURL, size: 88)
                Text(album.title)
                  .font(.caption)
                  .foregroundStyle(model.theme.text)
                  .lineLimit(1)
                  .frame(width: 88, alignment: .leading)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, Theme.spaceXL)
      }
    }
    .padding(.bottom, Theme.spaceMD)
    .background(model.theme.surface)
  }

  private var loading: some View {
    VStack {
      Spacer()
      ProgressView("正在读取音乐人…")
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var empty: some View {
    VStack {
      Spacer()
      Text("还没有选择音乐人")
        .foregroundStyle(model.theme.textMuted)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorState(_ message: String) -> some View {
    VStack(spacing: Theme.spaceMD) {
      Spacer()
      Text(message)
        .foregroundStyle(model.theme.textMuted)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.spaceXL)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func cover(url: URL?, size: CGFloat) -> some View {
    Group {
      if let url {
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
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
      .fill(model.theme.surfaceElevated)
      .overlay {
        Image(systemName: "person.fill")
          .foregroundStyle(model.theme.textFaint)
      }
  }

  private func compact(_ value: Int) -> String {
    if value >= 10_000 {
      return String(format: "%.1f万", Double(value) / 10_000)
    }
    return "\(value)"
  }

  private func nonEmpty(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }
}
