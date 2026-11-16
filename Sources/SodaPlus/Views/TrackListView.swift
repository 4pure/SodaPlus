import SwiftUI

/// 对齐 SodaM 曲目表：表头列宽共享，正在播放高亮；歌手/专辑可跳转。
struct TrackListView: View {
  @EnvironmentObject private var theme: ThemeStore

  let tracks: [SodaTrack]
  let currentID: String?
  let likedIDs: Set<String>
  var emptyText: String = "暂无歌曲"
  var onPlay: (SodaTrack) -> Void
  var onNext: (SodaTrack) -> Void
  var onLike: (SodaTrack) -> Void
  var onArtist: ((SodaTrack) -> Void)? = nil
  var onAlbum: ((SodaTrack) -> Void)? = nil

  var body: some View {
    VStack(spacing: 0) {
      header
      if tracks.isEmpty {
        emptyState
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
              row(index: index, track: track)
            }
          }
        }
      }
    }
    .background(theme.surface)
  }

  private var header: some View {
    HStack(spacing: 0) {
      Text("#")
        .frame(width: 44, alignment: .trailing)
      Text("歌曲")
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Theme.spaceMD)
      Text("歌手")
        .frame(width: 160, alignment: .leading)
      Text("专辑")
        .frame(width: 160, alignment: .leading)
      Text("时长")
        .frame(width: 56, alignment: .trailing)
        .padding(.trailing, Theme.spaceLG)
    }
    .font(.caption)
    .foregroundStyle(theme.textFaint)
    .padding(.vertical, Theme.spaceSM)
    .padding(.horizontal, Theme.spaceMD)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.border).frame(height: 1)
    }
  }

  private func row(index: Int, track: SodaTrack) -> some View {
    let playing = track.id == currentID
    return HStack(spacing: 0) {
      Group {
        if playing {
          Image(systemName: "speaker.wave.2.fill")
            .font(.caption2)
            .foregroundStyle(theme.accent)
        } else {
          Text("\(index + 1)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(theme.textFaint)
        }
      }
      .frame(width: 44, alignment: .trailing)

      HStack(spacing: Theme.spaceMD) {
        cover(for: track)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: Theme.spaceSM) {
            Text(track.title)
              .foregroundStyle(playing ? theme.accent : theme.text)
              .lineLimit(1)
            if track.isVIP {
              Text("VIP")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(theme.warning.opacity(0.2))
                .foregroundStyle(theme.warning)
                .clipShape(Capsule())
            }
          }
        }
        Spacer(minLength: 0)
        Button {
          onLike(track)
        } label: {
          Image(systemName: likedIDs.contains(track.id) ? "heart.fill" : "heart")
            .foregroundStyle(likedIDs.contains(track.id) ? theme.accent : theme.textFaint)
        }
        .buttonStyle(.plain)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.leading, Theme.spaceMD)

      linkOrText(
        track.artist.isEmpty ? "—" : track.artist,
        enabled: onArtist != nil && !track.artistId.isEmpty
      ) {
        onArtist?(track)
      }
      .frame(width: 160, alignment: .leading)

      linkOrText(
        track.album.isEmpty ? "—" : track.album,
        enabled: onAlbum != nil && !track.albumId.isEmpty
      ) {
        onAlbum?(track)
      }
      .frame(width: 160, alignment: .leading)

      Text(track.durationLabel)
        .font(.caption.monospacedDigit())
        .foregroundStyle(theme.textFaint)
        .frame(width: 56, alignment: .trailing)
        .padding(.trailing, Theme.spaceLG)
    }
    .font(.subheadline)
    .padding(.vertical, 8)
    .padding(.horizontal, Theme.spaceMD)
    .background(playing ? theme.surfaceSelected : Color.clear)
    .contentShape(Rectangle())
    .onTapGesture { onPlay(track) }
    .contextMenu {
      Button("播放") { onPlay(track) }
      Button("下一首播放") { onNext(track) }
      Button(likedIDs.contains(track.id) ? "取消喜欢" : "喜欢") { onLike(track) }
      if onArtist != nil, !track.artistId.isEmpty {
        Button("查看音乐人") { onArtist?(track) }
      }
      if onAlbum != nil, !track.albumId.isEmpty {
        Button("查看专辑") { onAlbum?(track) }
      }
    }
  }

  @ViewBuilder
  private func linkOrText(
    _ text: String,
    enabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    if enabled {
      Button(action: action) {
        Text(text)
          .foregroundStyle(theme.textMuted)
          .lineLimit(1)
      }
      .buttonStyle(.plain)
    } else {
      Text(text)
        .foregroundStyle(theme.textMuted)
        .lineLimit(1)
    }
  }

  private func cover(for track: SodaTrack) -> some View {
    Group {
      if let url = track.coverURL {
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
    .frame(width: 40, height: 40)
    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: 4, style: .continuous)
      .fill(theme.surfaceHover)
  }

  private var emptyState: some View {
    VStack(spacing: Theme.spaceMD) {
      Spacer()
      Image(systemName: "music.note")
        .font(.system(size: 36))
        .foregroundStyle(theme.textFaint)
      Text(emptyText)
        .font(.subheadline)
        .foregroundStyle(theme.textMuted)
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
