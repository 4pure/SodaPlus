import SwiftUI

/// 窗口内固定位置弹层：贴右侧、顶到标题栏下、底贴播放条，不挤压主布局。
struct QueuePopupView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore
  /// 由外层 GeometryReader 算出的可用高度。
  var maxHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      QueueListBody(model: model)
    }
    .frame(width: Theme.queueDrawerWidth, height: maxHeight, alignment: .top)
    .background(theme.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .stroke(theme.border, lineWidth: 1)
    )
    .shadow(color: .black.opacity(theme.mode == .dark ? 0.45 : 0.18), radius: 24, y: 8)
  }

  /// 对齐汽水：左侧收起 +「播放列表」+ 来源小字。
  private var header: some View {
    HStack(spacing: Theme.spaceMD) {
      Button {
        model.showQueue = false
      } label: {
        Image(systemName: "chevron.forward")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.textMuted)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("关闭播放列表")

      VStack(alignment: .leading, spacing: 2) {
        Text("播放列表")
          .font(.body.weight(.semibold))
          .foregroundStyle(theme.text)
        Text(headerSubtitle)
          .font(.caption2)
          .foregroundStyle(theme.textFaint)
      }
      Spacer(minLength: 0)
    }
    .padding(.leading, Theme.spaceMD)
    .padding(.trailing, Theme.spaceLG)
    .padding(.vertical, Theme.spaceMD)
    .overlay(alignment: .bottom) {
      Rectangle().fill(theme.border).frame(height: 1)
    }
  }

  private var headerSubtitle: String {
    if model.queueIsRecommendation {
      return "推荐 · \(model.queue.tracks.count) 首"
    }
    return "\(model.queue.tracks.count) 首"
  }
}

/// 当前曲置顶、不分组；用 queueIndex 作身份。
struct QueueListBody: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  private var entries: [(queueIndex: Int, track: SodaTrack)] {
    model.queue.displayEntries
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        // 队列通常几十首；VStack 比 LazyVStack 更不容易出现空白占位。
        VStack(alignment: .leading, spacing: 0) {
          ForEach(entries, id: \.queueIndex) { entry in
            let playing = entry.queueIndex == model.queue.index
            row(entry.track, emphasize: playing)
              .id(entry.queueIndex)
          }
        }
        .padding(.vertical, Theme.spaceXS)
      }
      .onAppear {
        proxy.scrollTo(model.queue.index, anchor: .top)
      }
      .onChange(of: model.queue.index) { _, newValue in
        withAnimation(.easeInOut(duration: 0.2)) {
          proxy.scrollTo(newValue, anchor: .top)
        }
      }
    }
  }

  private func row(_ track: SodaTrack, emphasize: Bool) -> some View {
    let dimmed = !track.playable
    return Button {
      model.playTrack(track, asQueue: model.queue.tracks)
    } label: {
      HStack(spacing: Theme.spaceMD) {
        ZStack {
          cover(for: track)
            .opacity(dimmed ? 0.45 : 1)
          if emphasize {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(.black.opacity(0.45))
            Image(systemName: "waveform")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(theme.accent)
          }
        }
        .frame(width: 40, height: 40)
        .clipped()

        VStack(alignment: .leading, spacing: 2) {
          Text(track.title)
            .font(.body)
            .foregroundStyle(
              emphasize ? theme.accent : (dimmed ? theme.textFaint : theme.text)
            )
            .lineLimit(1)
          Text(dimmed ? "不可播放" : track.artist)
            .font(.caption)
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Button {
          model.toggleLike(track)
        } label: {
          Image(systemName: model.likedIDs.contains(track.id) ? "heart.fill" : "heart")
            .font(.system(size: 12))
            .foregroundStyle(
              model.likedIDs.contains(track.id) ? theme.accent : theme.textFaint
            )
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Theme.spaceLG)
      .frame(height: 56)
      .background(emphasize ? theme.accentSoft : Color.clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
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
      .overlay {
        Image(systemName: "music.note")
          .font(.system(size: 12))
          .foregroundStyle(theme.textFaint)
      }
  }
}
