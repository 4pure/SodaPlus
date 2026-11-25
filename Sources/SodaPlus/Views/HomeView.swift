import SwiftUI

/// 对齐 SodaM / 官方汽水：推荐入口本身是装载态；成功后进入播放页，不展示曲目表。
struct HomeView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    VStack(spacing: Theme.spaceLG) {
      Spacer()
      if let error = model.homeError, !error.isEmpty {
        Image(systemName: "exclamationmark.triangle")
          .font(.system(size: 36))
          .foregroundStyle(theme.warning)
        Text(error)
          .font(.subheadline)
          .foregroundStyle(theme.textMuted)
          .multilineTextAlignment(.center)
          .padding(.horizontal, Theme.spaceXXL)
        Button("重试") {
          Task { await model.retryRecommendation() }
        }
        .buttonStyle(SodaSecondaryButtonStyle())
        .disabled(model.isBusy)
      } else {
        ProgressView()
          .controlSize(.regular)
          .tint(theme.accent)
        Text(model.isBusy ? "正在准备推荐队列…" : "推荐队列")
          .font(.subheadline)
          .foregroundStyle(theme.textMuted)
      }
      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.surface)
    .task {
      // 仅兜底：侧栏已走 activateRecommendation；此处防止直接落到 .home 时空转。
      if model.homeError != nil { return }
      if model.queueIsRecommendation, !model.queue.tracks.isEmpty {
        model.openNowPlaying()
        return
      }
      if !model.isBusy, model.homeTracks.isEmpty {
        await model.loadHome(reset: true, adoptQueue: true)
      } else if model.queue.current != nil || model.player.current != nil {
        model.openNowPlaying()
      }
    }
  }
}
