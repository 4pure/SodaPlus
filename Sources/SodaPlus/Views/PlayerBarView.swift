import SwiftUI

/// 对齐 SodaM `ui/player_bar.rs`：
/// 左封面+歌名/喜欢+歌手/音质 · 中 prev/play/next+进度 · 右音量/模式/队列。
struct PlayerBarView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore
  private var track: SodaTrack? { model.player.current ?? model.queue.current }

  private let qualities = ["auto", "hires", "lossless", "highest", "medium", "low"]

  var body: some View {
    HStack(spacing: Theme.spaceLG) {
      leftInfo
      centerTransport
      rightControls
    }
    .padding(.horizontal, Theme.spaceLG)
    .frame(height: Theme.playerHeight)
    .frame(maxWidth: .infinity)
    .background(theme.bg)
    .overlay(alignment: .top) {
      Rectangle().fill(theme.border).frame(height: 1)
    }
  }

  // MARK: - Left

  private var leftInfo: some View {
    HStack(spacing: Theme.spaceMD) {
      Button {
        model.nav = .nowPlaying
      } label: {
        coverThumb
      }
      .buttonStyle(.plain)
      .help("正在播放")

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: Theme.spaceSM) {
          Button {
            if let track { model.openAlbumFromTrack(track) }
          } label: {
            Text(track?.title ?? "未在播放")
              .font(.body.weight(.medium))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                  model.likedIDs.contains(track.id) ? theme.accent : theme.textMuted
                )
                .frame(width: 24, height: 24)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(model.likedIDs.contains(track.id) ? "取消喜欢" : "喜欢")
          }
        }

        HStack(spacing: Theme.spaceSM) {
          if let track, !track.artist.isEmpty {
            Button {
              model.openArtistFromTrack(track)
            } label: {
              Text(track.artist)
                .font(.caption)
                .foregroundStyle(theme.textMuted)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .disabled(track.artistId.isEmpty)
          } else {
            Text("选择一首歌开始播放吧")
              .font(.caption)
              .foregroundStyle(theme.textMuted)
              .lineLimit(1)
          }

          qualityBadge
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 280, alignment: .leading)
    .frame(minWidth: 200)
    .layoutPriority(0)
  }

  private var qualityBadge: some View {
    Menu {
      Text("音质：从下一首生效")
        .font(.caption2)
      ForEach(qualities, id: \.self) { q in
        Button {
          model.setQuality(q)
        } label: {
          HStack {
            Text(qualityLabel(q))
            if model.settings.quality == q {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      Text(qualityLabel(model.settings.quality))
        .font(.caption2)
        .foregroundStyle(theme.accent)
        .padding(.horizontal, Theme.spaceSM)
        .padding(.vertical, 1)
        .background(theme.surfaceElevated)
        .clipShape(Capsule())
        .overlay(
          Capsule().stroke(theme.surfaceElevated, lineWidth: 1)
        )
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
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
  }

  private var placeholderCover: some View {
    RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
      .fill(theme.surfaceHover)
      .overlay {
        Image(systemName: "music.note").foregroundStyle(theme.textFaint)
      }
  }

  // MARK: - Center

  private var centerTransport: some View {
    VStack(spacing: Theme.spaceXS) {
      HStack(spacing: Theme.spaceLG) {
        Button {
          model.playPrevious()
        } label: {
          Image(systemName: "backward.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(track == nil)

        Button {
          model.togglePlayPause()
        } label: {
          ZStack {
            Circle()
              .fill(theme.accent)
              .frame(width: 40, height: 40)
            if model.isBuffering {
              ProgressView()
                .controlSize(.small)
                .tint(theme.accentForeground)
            } else {
              Image(systemName: model.player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
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
          Image(systemName: "forward.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.textMuted)
        }
        .buttonStyle(.plain)
        .disabled(track == nil)
      }

      HStack(spacing: Theme.spaceSM) {
        Text(formatTime(model.player.position))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(theme.textFaint)
          .frame(width: 36, alignment: .trailing)
        Slider(
          value: Binding(
            get: { model.player.position },
            set: { model.player.seek(to: $0) }
          ),
          in: 0...max(model.player.duration, 0.1)
        )
        .controlSize(.mini)
        .tint(theme.accent)
        .disabled(track == nil)
        Text(formatTime(model.player.duration))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(theme.textFaint)
          .frame(width: 36, alignment: .leading)
      }
      .frame(maxWidth: 420)
    }
    .frame(maxWidth: .infinity)
  }

  // MARK: - Right

  private var rightControls: some View {
    HStack(spacing: Theme.spaceSM) {
      Button {
        model.toggleMute()
      } label: {
        Image(systemName: model.player.volume < 0.01 ? "speaker.slash" : "speaker.wave.2")
          .foregroundStyle(theme.textMuted)
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
      .controlSize(.mini)
      .frame(width: 96)
      .tint(theme.accent)

      Button {
        model.cyclePlayMode()
      } label: {
        Image(systemName: model.queue.mode.systemImage)
          .foregroundStyle(theme.textMuted)
      }
      .buttonStyle(.plain)
      .help(model.queue.mode.label)

      Button {
        model.showQueue.toggle()
      } label: {
        Image(systemName: "list.bullet")
          .foregroundStyle(model.showQueue ? theme.accent : theme.textMuted)
      }
      .buttonStyle(.plain)
      .help("播放队列")
    }
    .frame(width: 240, alignment: .trailing)
    .frame(minWidth: 180)
  }

  private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    return String(format: "%d:%02d", total / 60, total % 60)
  }

  private func qualityLabel(_ q: String) -> String {
    switch q {
    case "auto": return "自动"
    case "hires": return "Hi-Res"
    case "lossless": return "无损"
    case "highest": return "极高"
    case "medium": return "标准"
    case "low": return "较低"
    default: return q
    }
  }
}
