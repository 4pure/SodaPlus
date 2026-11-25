import AppKit
import SwiftUI

/// 对齐汽水底栏：顶缘细进度条 + 更大封面/播放钮；左信息 · 中运输 · 右音质/音量/模式/队列。
struct PlayerBarView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore
  private var track: SodaTrack? { model.player.current ?? model.queue.current }

  private let qualities = QualityPreference.allCases

  /// 对齐汽水 Slider：悬停/拖动时加粗轨道并显示圆点与时间 tip。
  @State private var progressHovered = false
  @State private var progressDragging = false
  @State private var progressHoverX: CGFloat = 0

  var body: some View {
    ZStack(alignment: .top) {
      HStack(spacing: 0) {
        leftInfo
          .frame(maxWidth: .infinity, alignment: .leading)
        centerTransport
          .frame(width: 320)
        rightControls
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.horizontal, Theme.spaceLG)
      .padding(.top, Theme.spaceSM)
      .padding(.bottom, Theme.spaceSM)
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      // 汽水：进度条贴底栏顶缘（细线），不占一整行厚条。
      progressEdge
    }
    .frame(height: Theme.playerHeight)
    .frame(maxWidth: .infinity)
    .background(theme.bg)
    // 顶缘细进度条兼作分隔，不再叠一条 border 以免视觉变厚。
  }

  // MARK: - Progress（贴顶缘细条；悬停对齐汽水 Slider）

  private var progressEdge: some View {
    let duration = max(model.player.duration, 0.1)
    let progress = track == nil ? 0 : min(max(model.player.position / duration, 0), 1)
    let active = progressHovered || progressDragging
    // 汽水：默认 2px，悬停/拖动 6px；thumb 10px；命中区约 20px。
    let trackHeight: CGFloat = active ? 6 : 2
    let thumbSize: CGFloat = 10
    let hitHeight: CGFloat = 20

    return GeometryReader { geo in
      let width = max(geo.size.width, 1)
      let fillWidth = max(0, width * progress)
      let hoverRatio = min(max(progressHoverX / width, 0), 1)
      let tipX = min(max(progressHoverX, 28), width - 28)

      ZStack(alignment: .topLeading) {
        // 轨道贴顶缘；thumb 相对轨道垂直居中，可向上溢出。
        ZStack(alignment: .topLeading) {
          Capsule()
            .fill(theme.border)
            .frame(maxWidth: .infinity)
            .frame(height: trackHeight)
          if active, track != nil {
            Capsule()
              .fill(Color.white.opacity(0.10))
              .frame(width: max(0, width * hoverRatio), height: trackHeight)
          }
          Capsule()
            .fill(theme.accent)
            .frame(width: fillWidth, height: trackHeight)
          if active, track != nil {
            Circle()
              .fill(Color.white)
              .frame(width: thumbSize, height: thumbSize)
              .scaleEffect(progressDragging ? 1.2 : 1)
              .offset(
                x: fillWidth - thumbSize / 2,
                y: (trackHeight - thumbSize) / 2
              )
          }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.12), value: active)

        if active, track != nil {
          Text(formatTime(hoverRatio * duration))
            .font(.system(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Color(hex: 0x252525))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(alignment: .bottom) {
              ProgressTipArrow()
                .fill(Color(hex: 0x252525))
                .frame(width: 10, height: 5)
                .offset(y: 5)
            }
            // 汽水 tip：top:-40、高 32 → 中心约在 -24。
            .position(x: tipX, y: -24)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
      }
      .zIndex(20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .contentShape(Rectangle())
      .onHover { hovering in
        guard track != nil else {
          setProgressHovered(false)
          return
        }
        setProgressHovered(hovering)
        if hovering {
          NSCursor.pointingHand.push()
        } else {
          NSCursor.pop()
        }
      }
      .onContinuousHover { phase in
        guard track != nil else { return }
        switch phase {
        case .active(let location):
          progressHoverX = location.x
          setProgressHovered(true)
        case .ended:
          if !progressDragging {
            setProgressHovered(false)
          }
        }
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard track != nil else { return }
            if !progressDragging {
              withAnimation(.easeInOut(duration: 0.12)) { progressDragging = true }
            }
            progressHoverX = value.location.x
            let ratio = min(max(value.location.x / width, 0), 1)
            model.player.seek(to: ratio * duration)
          }
          .onEnded { _ in
            withAnimation(.easeInOut(duration: 0.12)) {
              progressDragging = false
            }
          }
      )
    }
    .frame(height: hitHeight)
    .allowsHitTesting(track != nil)
  }

  private func setProgressHovered(_ hovering: Bool) {
    guard progressHovered != hovering else { return }
    withAnimation(.easeInOut(duration: 0.12)) {
      progressHovered = hovering
    }
  }

  // MARK: - Left

  private var leftInfo: some View {
    HStack(alignment: .center, spacing: Theme.spaceMD) {
      Button {
        model.toggleNowPlaying()
      } label: {
        coverThumb
      }
      .buttonStyle(.plain)
      .help(model.nav == .nowPlaying ? "收起歌曲详情" : "展开歌曲详情")

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: Theme.spaceSM) {
          Button {
            if let track { model.openAlbumFromTrack(track) }
          } label: {
            Text(track?.title ?? "未在播放")
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(theme.text)
              .lineLimit(1)
          }
          .buttonStyle(.plain)
          .disabled(track?.albumId.isEmpty ?? true)

          if let track {
            Button {
              model.toggleLike(track)
            } label: {
              Image(systemName: model.likedIDs.contains(track.id) ? "heart.fill" : "heart")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                  model.likedIDs.contains(track.id) ? theme.accent : theme.textMuted
                )
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
              .font(.system(size: 13, weight: .regular))
              .foregroundStyle(theme.textMuted)
              .lineLimit(1)
          }
          .buttonStyle(.plain)
          .disabled(track.artistId.isEmpty)
        } else {
          Text("选择一首歌开始播放吧")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minWidth: 200, maxWidth: 360, alignment: .center)
  }

  private var qualityBadge: some View {
    Menu {
      Text("音质：从下一首生效")
        .font(.caption2)
      ForEach(qualities) { q in
        Button {
          model.setQuality(q)
        } label: {
          HStack {
            Text(q.title)
            if model.settings.qualityPreference == q {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Text(qualityBadgeLabel)
        .font(.caption)
        .foregroundStyle(theme.accent)
        .padding(.horizontal, Theme.spaceSM)
        .padding(.vertical, 2)
        .background(theme.surfaceElevated)
        .clipShape(Capsule())
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  private var coverThumb: some View {
    Group {
      if let url = track?.coverURL {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            placeholderCover
          }
        }
      } else {
        placeholderCover
      }
    }
    .frame(width: Theme.playerThumb, height: Theme.playerThumb)
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  private var placeholderCover: some View {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(theme.surfaceHover)
      .overlay {
        Image(systemName: "music.note")
          .font(.system(size: 18))
          .foregroundStyle(theme.textFaint)
      }
  }

  // MARK: - Center

  private var centerTransport: some View {
    HStack(spacing: Theme.spaceMD) {
      Text(formatTime(model.player.position))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(theme.textFaint)
        .frame(width: 36, alignment: .trailing)

      HStack(spacing: Theme.spaceXL) {
        Button {
          model.playPrevious()
        } label: {
          Image(systemName: "backward.end.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.textMuted)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(track == nil)

        Button {
          model.togglePlayPause()
        } label: {
          ZStack {
            Circle()
              .fill(theme.accent)
              .frame(width: Theme.playerPlayButton, height: Theme.playerPlayButton)
            if model.isBuffering {
              ProgressView()
                .controlSize(.small)
                .tint(theme.accentForeground)
            } else {
              Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.accentForeground)
                .offset(x: model.player.isPlaying ? 0 : 1)
            }
          }
        }
        .buttonStyle(.plain)
        .disabled(track == nil)

        Button {
          model.playNext(userInitiated: true)
        } label: {
          Image(systemName: "forward.end.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(theme.textMuted)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(track == nil)
      }

      Text(formatTime(model.player.duration))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(theme.textFaint)
        .frame(width: 36, alignment: .leading)
    }
    .frame(height: Theme.playerThumb)
  }

  // MARK: - Right

  private var qualityBadgeLabel: String {
    let preference = model.settings.qualityPreference
    return preference == .auto ? "音质" : preference.title
  }

  private var rightControls: some View {
    HStack(spacing: Theme.spaceMD) {
      qualityBadge

      Button {
        model.toggleMute()
      } label: {
        Image(systemName: model.player.volume < 0.01 ? "speaker.slash" : "speaker.wave.2")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(theme.textMuted)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(model.player.volume < 0.01 ? "取消静音" : "静音")

      Slider(
        value: Binding(
          get: { Double(model.player.volume) },
          set: { model.updateVolume(Float($0)) }
        ),
        in: 0...1
      )
      .controlSize(.small)
      .frame(width: 110)
      .tint(theme.accent)

      Button {
        model.cyclePlayMode()
      } label: {
        Image(systemName: model.queue.mode.systemImage)
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(theme.textMuted)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(model.queue.mode.label)

      Button {
        model.showQueue.toggle()
      } label: {
        Image(systemName: "list.bullet")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(model.showQueue ? theme.accent : theme.textMuted)
          .frame(width: 28, height: 28)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("播放队列")
    }
    .frame(minWidth: 220, maxWidth: 360, alignment: .trailing)
  }

  private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

/// 汽水 slider-tip 底部小三角。
private struct ProgressTipArrow: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.15, y: rect.maxY * 0.72))
    path.addQuadCurve(
      to: CGPoint(x: rect.midX - rect.width * 0.15, y: rect.maxY * 0.72),
      control: CGPoint(x: rect.midX, y: rect.maxY)
    )
    path.closeSubpath()
    return path
  }
}
