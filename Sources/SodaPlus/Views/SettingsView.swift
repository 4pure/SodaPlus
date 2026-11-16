import SwiftUI

/// 对齐 SodaM 设置页：账户卡（去登录弹层）+ 音质 + 缓存 + 关于。
struct SettingsView: View {
  @ObservedObject var model: AppModel

  private let qualities = ["auto", "hires", "lossless", "highest", "medium", "low"]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.spaceXL) {
        pageHeader("设置", "账号与音质偏好")

        sectionTitle("账户")
        accountCard

        sectionTitle("音质")
        card {
          Picker(
            "音质意图",
            selection: Binding(
              get: { model.settings.quality },
              set: { model.setQuality($0) }
            )
          ) {
            ForEach(qualities, id: \.self) { q in
              Text(qualityLabel(q)).tag(q)
            }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          Text("「自动」不设上限；具体档位从下一首开始生效。")
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
        }

        sectionTitle("缓存")
        card {
          Text("音频缓存在本机 Caches/SodaPlus/audio。")
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
          Button("清空音频缓存", role: .destructive) {
            model.clearAudioCache()
          }
          .buttonStyle(SodaSecondaryButtonStyle())
        }

        sectionTitle("关于")
        card {
          Text("SodaPlus · 非官方 Swift 客户端")
            .foregroundStyle(Theme.text)
          Text("交互对齐开源 SodaM；音乐能力由 libresoda 提供。与字节 / 汽水官方无关。AGPL-3.0。")
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(Theme.spaceXL)
      .frame(maxWidth: 720, alignment: .leading)
    }
    .background(Theme.surface)
  }

  private var accountCard: some View {
    card {
      HStack(spacing: Theme.spaceLG) {
        Circle()
          .fill(Theme.surfaceHover)
          .frame(width: 64, height: 64)
          .overlay {
            if model.isLoggedIn, !model.account.nickname.isEmpty {
              Text(String(model.account.nickname.prefix(1)))
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.text)
            } else {
              Image(systemName: "person.fill")
                .foregroundStyle(Theme.textFaint)
            }
          }

        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text(
            model.isLoggedIn
              ? (model.account.nickname.isEmpty ? "已登录" : model.account.nickname)
              : "未登录"
          )
          .font(.title3.weight(.semibold))
          .foregroundStyle(Theme.text)

          Text(
            model.isLoggedIn
              ? "用户 \(model.account.userId.isEmpty ? "—" : model.account.userId) · \(model.account.vip ? "VIP" : "非 VIP")"
              : "登录后才能使用搜索、歌单与播放"
          )
          .font(.subheadline)
          .foregroundStyle(Theme.textMuted)

          if !model.isLoggedIn {
            Button {
              model.openLoginModal()
            } label: {
              Label("去登录", systemImage: "arrow.right.circle")
            }
            .buttonStyle(SodaPrimaryButtonStyle())
            .padding(.top, Theme.spaceSM)
          }
        }

        Spacer()

        if model.isLoggedIn {
          Button("退出登录", role: .destructive) { model.logout() }
            .buttonStyle(SodaSecondaryButtonStyle())
        }
      }

      if !model.isLoggedIn {
        DisclosureGroup("或粘贴 Cookie") {
          TextEditor(text: $model.cookieDraft)
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 80)
            .border(Theme.border)
          Button("保存 Cookie") { model.saveCookieFromDraft() }
            .buttonStyle(SodaSecondaryButtonStyle())
            .padding(.top, Theme.spaceSM)
        }
        .foregroundStyle(Theme.textMuted)
        .padding(.top, Theme.spaceMD)
      }
    }
  }

  private func pageHeader(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceXS) {
      Text(title)
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(Theme.text)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(Theme.textMuted)
    }
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.title3.weight(.semibold))
      .foregroundStyle(Theme.text)
  }

  private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceMD) {
      content()
    }
    .padding(Theme.spaceLG)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surfaceElevated)
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .stroke(Theme.border, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
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
