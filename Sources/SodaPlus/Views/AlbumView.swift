import SwiftUI

/// 对齐 SodaM 专辑页：封面、元数据、全碟曲目。
struct AlbumView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      backBar
      if model.detailLoading && model.openAlbum == nil {
        loading
      } else if let error = nonEmpty(model.detailError), model.openAlbum == nil {
        errorState(error)
      } else if let detail = model.openAlbum {
        header(detail)
        TrackListView(
          tracks: detail.tracks,
          currentID: model.player.current?.id,
          likedIDs: model.likedIDs,
          emptyText: "暂无专辑歌曲",
          onPlay: { model.playTrack($0, asQueue: detail.tracks) },
          onNext: { model.playNextInQueue($0) },
          onLike: { model.toggleLike($0) },
          onArtist: { model.openArtistFromTrack($0) },
          onAlbum: { _ in }
        )
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

  private func header(_ detail: AlbumDetailPage) -> some View {
    HStack(alignment: .center, spacing: Theme.spaceLG) {
      cover(url: detail.album.coverURL, size: 120)
      VStack(alignment: .leading, spacing: Theme.spaceXS) {
        Text(detail.album.title)
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(model.theme.text)
        Text(subtitle(detail))
          .font(.subheadline)
          .foregroundStyle(model.theme.textMuted)
        if !detail.album.company.isEmpty {
          Text(detail.album.company)
            .font(.caption)
            .foregroundStyle(model.theme.textFaint)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.spaceXL)
    .padding(.bottom, Theme.spaceLG)
  }

  private func subtitle(_ detail: AlbumDetailPage) -> String {
    var parts: [String] = [
      "\(max(detail.album.trackCount, detail.tracks.count)) 首"
    ]
    if !detail.album.artist.isEmpty {
      parts.append(detail.album.artist)
    }
    let release = detail.album.releaseLabel
    if !release.isEmpty {
      parts.append(release)
    }
    return parts.joined(separator: " · ")
  }

  private var loading: some View {
    VStack {
      Spacer()
      ProgressView("正在读取专辑…")
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var empty: some View {
    VStack {
      Spacer()
      Text("还没有选择专辑")
        .foregroundStyle(model.theme.textMuted)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func errorState(_ message: String) -> some View {
    VStack {
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
        Image(systemName: "opticaldisc")
          .foregroundStyle(model.theme.textFaint)
      }
  }

  private func nonEmpty(_ s: String) -> String? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
  }
}
