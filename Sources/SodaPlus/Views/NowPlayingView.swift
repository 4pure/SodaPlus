import SwiftUI

/// 对齐汽水播放页：左区大封面+信息居中，右列歌词逐字高亮。
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
      // 歌词列略宽；左区吃剩余宽度，封面+信息在左区内居中（对齐汽水）。
      let lyricW = min(540, max(320, geo.size.width * 0.34))
      let hPad: CGFloat = 32
      let gap: CGFloat = 36
      let leftW = max(0, geo.size.width - lyricW - gap - hPad * 2)
      // 预留歌名/VIP/艺人高度；封面约满额的 75%。
      let infoReserve: CGFloat = 128
      let coverW =
        min(
          max(200, geo.size.height - infoReserve),
          leftW * 0.86,
          geo.size.height * 0.72
        ) * 0.75

      HStack(alignment: .center, spacing: gap) {
        coverColumn(width: coverW)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        lyricsColumn
          .frame(width: lyricW)
          .frame(maxHeight: .infinity)
      }
      .padding(.horizontal, hPad)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(model.theme.surface)
  }

  private func coverColumn(width: CGFloat) -> some View {
    let radius = max(Theme.radiusCard, width * 0.045)
    return VStack(alignment: .leading, spacing: Theme.spaceLG) {
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
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
      .shadow(color: .black.opacity(0.32), radius: 36, y: 18)

      // 对齐汽水：曲名行左标题/VIP、右爱心（可视上缘对齐曲名），下行艺人。
      VStack(alignment: .leading, spacing: Theme.spaceSM) {
        HStack(alignment: .top, spacing: Theme.spaceSM) {
          Text(track?.title ?? "未在播放")
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(model.theme.text)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .layoutPriority(1)

          if let track, track.isVIP {
            Text("VIP")
              .font(.caption.weight(.bold))
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(model.theme.warning.opacity(0.2))
              .foregroundStyle(model.theme.warning)
              .clipShape(Capsule())
              .padding(.top, 4)
          }

          Spacer(minLength: Theme.spaceSM)

          if let track {
            Button {
              model.toggleLike(track)
            } label: {
              Image(systemName: model.likedIDs.contains(track.id) ? "heart.fill" : "heart")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(
                  model.likedIDs.contains(track.id) ? model.theme.accent : model.theme.text
                )
                // SF Symbol 顶部略有留白；微上提，避免高过曲名。
                .offset(y: 1)
            }
            .buttonStyle(.plain)
            .help(model.likedIDs.contains(track.id) ? "取消喜欢" : "喜欢")
          }
        }

        if let track, !track.artist.isEmpty {
          Button {
            model.openArtistFromTrack(track)
          } label: {
            Text(track.artist)
              .font(.system(size: 16, weight: .medium))
              .foregroundStyle(model.theme.textMuted)
          }
          .buttonStyle(.plain)
          .disabled(track.artistId.isEmpty)
        }
      }
      .frame(width: width, alignment: .leading)
    }
  }

  private var lyricsColumn: some View {
    ScrollViewReader { proxy in
      ScrollView(showsIndicators: false) {
        // 歌词行数有限；用 VStack 保证目标行已布局，避免 LazyVStack 下 scrollTo 静默失败。
        VStack(alignment: .leading, spacing: 32) {
          if model.lyricLines.isEmpty {
            Text("暂无歌词")
              .foregroundStyle(model.theme.lyricDim)
              .padding(.top, 40)
          } else {
            ForEach(Array(model.lyricLines.enumerated()), id: \.offset) { index, line in
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
      .onAppear {
        scrollLyrics(proxy: proxy, to: currentLyricIndex, animated: false)
      }
      .onChange(of: currentLyricIndex) { _, newValue in
        scrollLyrics(proxy: proxy, to: newValue, animated: true)
      }
      .onChange(of: model.lyricLines.count) { _, _ in
        scrollLyrics(proxy: proxy, to: currentLyricIndex, animated: false)
      }
    }
  }

  private func scrollLyrics(proxy: ScrollViewProxy, to index: Int, animated: Bool) {
    guard !model.lyricLines.isEmpty else { return }
    let clamped = min(max(0, index), model.lyricLines.count - 1)
    // 等当前帧布局完成后再滚，避免歌词刚加载或首屏时 scrollTo 打空。
    DispatchQueue.main.async {
      if animated {
        withAnimation(.easeInOut(duration: 0.25)) {
          proxy.scrollTo(clamped, anchor: .center)
        }
      } else {
        proxy.scrollTo(clamped, anchor: .center)
      }
    }
  }

  private var placeholder: some View {
    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
      .fill(model.theme.surfaceElevated)
      .overlay {
        Image(systemName: "music.note")
          .font(.system(size: 52))
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

  private static let revealTick: Double = 1.0 / 30.0

  var body: some View {
    let active = line.isActive(at: position, nextStart: nextStart)
    if active, line.hasWordTimeline {
      let fraction = line.highlightFraction(at: position)
      // 双层同字重，避免字重变化导致字形宽度跳变、mask 发颤。
      ZStack(alignment: .leading) {
        Text(line.text)
          .font(.title3.weight(.semibold))
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
      .animation(.linear(duration: Self.revealTick), value: fraction)
    } else {
      Text(line.text)
        .font(.title3.weight(active ? .semibold : .regular))
        .foregroundStyle(active ? accent : dim)
        .animation(.easeInOut(duration: 0.18), value: active)
    }
  }
}
