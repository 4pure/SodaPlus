import SwiftUI

/// 对齐 SodaM 右侧队列抽屉：320px，贴内容区右侧、通栏播放条之上。
struct QueueDrawerView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("播放队列 · \(model.queue.tracks.count) 首")
          .font(.caption)
          .foregroundStyle(theme.textFaint)
        Spacer()
        Button {
          model.showQueue = false
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.textMuted)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Theme.spaceLG)
      .frame(height: 40)
      .overlay(alignment: .bottom) {
        Rectangle().fill(theme.border).frame(height: 1)
      }

      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          if !model.queue.played.isEmpty {
            sectionHeader("已播放 · \(model.queue.played.count) 首")
            ForEach(model.queue.played) { track in
              row(track)
            }
          }
          if let current = model.queue.current {
            sectionHeader("正在播放")
            row(current, emphasize: true)
          }
          if !model.queue.upcoming.isEmpty {
            sectionHeader("接下来 · \(model.queue.upcoming.count) 首")
            ForEach(model.queue.upcoming) { track in
              row(track)
            }
          }
        }
      }
    }
    .frame(width: 320)
    .frame(maxHeight: .infinity)
    .background(theme.bg)
    .overlay(alignment: .leading) {
      Rectangle().fill(theme.border).frame(width: 1)
    }
  }

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.caption2)
      .foregroundStyle(theme.textFaint)
      .padding(.horizontal, Theme.spaceMD)
      .padding(.top, Theme.spaceMD)
      .padding(.bottom, Theme.spaceXS)
  }

  private func row(_ track: SodaTrack, emphasize: Bool = false) -> some View {
    Button {
      model.playTrack(track, asQueue: model.queue.tracks)
    } label: {
      HStack(spacing: Theme.spaceMD) {
        VStack(alignment: .leading, spacing: 2) {
          Text(track.title)
            .font(.body)
            .foregroundStyle(emphasize ? theme.accent : theme.text)
            .lineLimit(1)
          Text(track.artist)
            .font(.caption)
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
        }
        Spacer(minLength: 0)
        Text(track.durationLabel)
          .font(.caption)
          .foregroundStyle(theme.textFaint)
          .frame(width: 44, alignment: .trailing)
        Button {
          model.toggleLike(track)
        } label: {
          Image(systemName: model.likedIDs.contains(track.id) ? "heart.fill" : "heart")
            .font(.system(size: 12))
            .foregroundStyle(
              model.likedIDs.contains(track.id) ? theme.accent : theme.textFaint
            )
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, Theme.spaceMD)
      .frame(height: 52)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
