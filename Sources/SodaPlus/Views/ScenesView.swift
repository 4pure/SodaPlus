import SwiftUI

struct ScenesView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  private let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.spaceMD)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceLG) {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text("听歌模式")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(theme.text)
          Text("按场景选歌")
            .font(.subheadline)
            .foregroundStyle(theme.textMuted)
        }

        Text("常用模式")
          .font(.title3.weight(.semibold))
          .foregroundStyle(theme.text)

        if model.scenes.isEmpty {
          HStack {
            Spacer()
            if model.isBusy {
              ProgressView("正在读取听歌模式…")
            } else {
              Text(model.isLoggedIn ? "暂无模式" : "请先登录")
                .foregroundStyle(theme.textMuted)
            }
            Spacer()
          }
          .padding(.vertical, Theme.spaceXXL)
        } else {
          LazyVGrid(columns: columns, spacing: Theme.spaceMD) {
            ForEach(model.scenes) { scene in
              Button {
                Task { await model.playScene(scene) }
              } label: {
                HStack(spacing: Theme.spaceSM) {
                  sceneIcon(scene)
                  Text(scene.text)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.spaceMD)
                .frame(height: Theme.control + 12)
                .background(theme.surfaceElevated)
                .overlay(
                  RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
              }
              .buttonStyle(.plain)
              .disabled(model.isBusy)
            }
          }
        }
      }
      .padding(Theme.spaceXL)
    }
    .background(theme.surface)
    .task {
      if model.isLoggedIn, model.scenes.isEmpty {
        await model.loadScenes()
      }
    }
  }

  private func sceneIcon(_ scene: SceneItem) -> some View {
    Group {
      if let url = URL(string: scene.cover), !scene.cover.isEmpty {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image.resizable().scaledToFill()
          } else {
            Image(systemName: "waveform").foregroundStyle(theme.textMuted)
          }
        }
      } else {
        Image(systemName: "waveform").foregroundStyle(theme.textMuted)
      }
    }
    .frame(width: 28, height: 28)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}
