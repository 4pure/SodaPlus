import SwiftUI

struct ScenesView: View {
  @ObservedObject var model: AppModel

  private let columns = [GridItem(.adaptive(minimum: 160), spacing: Theme.spaceMD)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceLG) {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text("听歌模式")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(Theme.text)
          Text("按场景选歌")
            .font(.subheadline)
            .foregroundStyle(Theme.textMuted)
        }

        Text("常用模式")
          .font(.title3.weight(.semibold))
          .foregroundStyle(Theme.text)

        if model.scenes.isEmpty {
          HStack {
            Spacer()
            if model.isBusy {
              ProgressView("正在读取听歌模式…")
            } else {
              Text(model.isLoggedIn ? "暂无模式" : "请先登录")
                .foregroundStyle(Theme.textMuted)
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
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.spaceMD)
                .frame(height: Theme.control + 12)
                .background(Theme.surfaceElevated)
                .overlay(
                  RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1)
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
    .background(Theme.surface)
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
            Image(systemName: "waveform").foregroundStyle(Theme.textMuted)
          }
        }
      } else {
        Image(systemName: "waveform").foregroundStyle(Theme.textMuted)
      }
    }
    .frame(width: 28, height: 28)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}
