import SwiftUI

/// 对齐 SodaM 播放页：封面约 min(40vh,30vw)，歌词列逐字高亮。
struct NowPlayingView: View {
  @ObservedObject var model: AppModel

  private var track: SodaTrack? { model.player.current }
  private var position: Double { model.player.position }

  private var currentLyricIndex: Int {
    var idx = 0
    for (i, line) in model.lyricLines.enumerated() {
      if line.startSeconds <= position { idx = i } else { break }
    }
    return idx
  }

  var body: some View {
    GeometryReader { geo in
      let coverW = min(geo.size.height * 0.40, geo.size.width * 0.30)
      let lyricW = min(500, max(300, geo.size.width * 0.30))

      HStack(spacing: 50) {
        Spacer(minLength: 0)
        coverColumn(width: coverW)
        Group {
          if model.showQueue {
            embeddedQueue
          } else {
            lyricsColumn
          }
        }
        .frame(width: lyricW)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 50)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(model.theme.surface)
  }

  /// 对齐 SodaM：播放页内嵌队列替换歌词列，不走右侧抽屉。
  private var embeddedQueue: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("播放队列 · \(model.queue.tracks.count) 首")
          .font(.caption)
          .foregroundStyle(model.theme.textFaint)
        Spacer()
        Button {
          model.showQueue = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(model.theme.textMuted)
        }
        .buttonStyle(.plain)
      }
      .padding(.bottom, Theme.spaceMD)

      ScrollView {
        LazyVStack(alignment: .leading, spacing: Theme.spaceSM) {
          ForEach(Array(model.queue.tracks.enumerated()), id: \.element.id) { index, item in
            let playing = item.id == track?.id
            Button {
              model.playTrack(item, asQueue: model.queue.tracks)
            } label: {
              HStack {
                Text(item.title)
                  .foregroundStyle(playing ? model.theme.accent : model.theme.text)
                  .lineLimit(1)
                Spacer()
                Text(item.durationLabel)
                  .font(.caption)
                  .foregroundStyle(model.theme.textFaint)
              }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)
          }
        }
      }
    }
  }

  private func coverColumn(width: CGFloat) -> some View {
    VStack(spacing: Theme.spaceLG) {
      Group {
        if let url = track?.coverURL {
          AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
              image.resizable().scaledToFit()
            } else {
              placeholder
            }
          }
        } else {
          placeholder
        }
      }
      .frame(width: width, height: width)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .shadow(color: .black.opacity(0.4), radius: 28, y: 14)

      Text(track?.title ?? "未在播放")
        .font(.title2.weight(.bold))
        .foregroundStyle(model.theme.text)
        .multilineTextAlignment(.center)

      if let track {
        HStack(spacing: Theme.spaceSM) {
          if track.isVIP {
            Text("VIP")
              .font(.caption2.weight(.bold))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(model.theme.warning.opacity(0.2))
              .foregroundStyle(model.theme.warning)
              .clipShape(Capsule())
          }
          Button {
            model.toggleLike(track)
          } label: {
            Image(systemName: model.likedIDs.contains(track.id) ? "heart.fill" : "heart")
              .foregroundStyle(
                model.likedIDs.contains(track.id) ? model.theme.accent : model.theme.textMuted
              )
          }
          .buttonStyle(.plain)
        }
      }

      if let track, !track.artist.isEmpty {
        Button {
          model.openArtistFromTrack(track)
        } label: {
          Text(track.artist)
            .font(.title3)
            .foregroundStyle(model.theme.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(track.artistId.isEmpty)
      }
    }
    .frame(width: width + 20)
  }

  private var lyricsColumn: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 32) {
          if model.lyricLines.isEmpty {
            Text("暂无歌词")
              .foregroundStyle(model.theme.lyricDim)
              .padding(.top, 40)
          } else {
            ForEach(Array(model.lyricLines.enumerated()), id: \.element.id) { index, line in
              let nextStart =
                index + 1 < model.lyricLines.count
                ? model.lyricLines[index + 1].startSeconds
                : nil
              LyricRevealLine(
                line: line,
                position: position,
                nextStart: nextStart,
                accent: model.theme.accent,
                dim: model.theme.lyricDim
              )
              .id(index)
              .frame(maxWidth: .infinity, alignment: .leading)
              .frame(minHeight: 32, alignment: .leading)
            }
          }
        }
        .padding(.vertical, Theme.spaceXL)
      }
      .onChange(of: currentLyricIndex) { _, newValue in
        withAnimation(.easeInOut(duration: 0.25)) {
          proxy.scrollTo(newValue, anchor: .center)
        }
      }
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
      .fill(model.theme.surfaceElevated)
      .overlay {
        Image(systemName: "music.note")
          .font(.system(size: 48))
          .foregroundStyle(model.theme.textFaint)
      }
  }
}

/// 当前句：增强 LRC 用双层文字 + 宽度 mask 走字；普通 LRC 整句 accent。
private struct LyricRevealLine: View {
  let line: LyricLine
  let position: Double
  let nextStart: Double?
  let accent: Color
  let dim: Color

  var body: some View {
    let active = line.isActive(at: position, nextStart: nextStart)
    if active, line.hasWordTimeline {
      let fraction = line.highlightFraction(at: position)
      ZStack(alignment: .leading) {
        Text(line.text)
          .font(.title3)
          .foregroundStyle(dim)
        Text(line.text)
          .font(.title3.weight(.semibold))
          .foregroundStyle(accent)
          .mask(alignment: .leading) {
            GeometryReader { geo in
              Rectangle()
                .frame(width: max(0, geo.size.width * fraction))
            }
          }
      }
    } else {
      Text(line.text)
        .font(.title3)
        .fontWeight(active ? .semibold : .regular)
        .foregroundStyle(active ? accent : dim)
    }
  }
}
