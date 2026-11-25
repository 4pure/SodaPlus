import SwiftUI

/// 对齐 SodaM `views/login.rs`：居中扫码卡片 + 遮罩；二次验证切到内嵌 WebView。
struct LoginModalView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  private var showingVerify: Bool {
    !model.qrVerifyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    ZStack {
      Color.black.opacity(theme.mode == .dark ? 0.55 : 0.35)
        .ignoresSafeArea()
        .onTapGesture { model.closeLoginModal() }

      VStack(spacing: Theme.spaceLG) {
        Text(showingVerify ? "二次验证" : "扫码登录")
          .font(.title2.weight(.bold))
          .foregroundStyle(theme.text)

        if showingVerify, let page = URL(string: model.qrVerifyURL) {
          VerifyWebView(url: page)
            .frame(width: 420, height: 520)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
            )
        } else {
          Group {
            if let image = model.qrNSImage {
              Image(nsImage: image)
                .resizable()
                .interpolation(.none)
                .frame(width: 220, height: 220)
                .padding(Theme.spaceSM)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            } else {
              ProgressView()
                .controlSize(.large)
                .frame(width: 220, height: 220)
                .background(theme.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
            }
          }
        }

        VStack(spacing: Theme.spaceXS) {
          Text(
            showingVerify
              ? "按页面提示完成验证，完成后会自动登录"
              : "请使用汽水音乐 App 扫码登录"
          )
          .font(.subheadline)
          .foregroundStyle(theme.text)
          Text(model.qrMessage.isEmpty ? "等待扫码…" : model.qrMessage)
            .font(.caption)
            .foregroundStyle(theme.textMuted)
            .multilineTextAlignment(.center)
          if !model.qrToken.isEmpty {
            Text("会话 \(String(model.qrToken.prefix(10)))…")
              .font(.caption2)
              .foregroundStyle(theme.textFaint)
          }
        }

        HStack(spacing: Theme.spaceMD) {
          Button("重新获取") { model.startQRLogin() }
            .buttonStyle(SodaSecondaryButtonStyle())
          Button("关闭") { model.closeLoginModal() }
            .buttonStyle(SodaSecondaryButtonStyle())
        }
      }
      .padding(Theme.spaceXL)
      .frame(width: showingVerify ? 460 : 360)
      .background(theme.surfaceElevated)
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .stroke(theme.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .shadow(color: .black.opacity(theme.mode == .dark ? 0.45 : 0.18), radius: 28, y: 12)
    }
  }
}

struct SodaPrimaryButtonStyle: ButtonStyle {
  @EnvironmentObject private var theme: ThemeStore

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.medium))
      .foregroundStyle(theme.accentForeground)
      .padding(.horizontal, Theme.spaceLG)
      .frame(height: Theme.control)
      .background(theme.accent.opacity(configuration.isPressed ? 0.85 : 1))
      .clipShape(Capsule())
  }
}

struct SodaSecondaryButtonStyle: ButtonStyle {
  @EnvironmentObject private var theme: ThemeStore

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline)
      .foregroundStyle(theme.textMuted)
      .padding(.horizontal, Theme.spaceLG)
      .frame(height: Theme.control)
      .background(theme.surfaceHover.opacity(configuration.isPressed ? 0.8 : 1))
      .clipShape(Capsule())
  }
}

/// 对齐汽水歌单头：「播放全部 N」。
struct PlayAllButton: View {
  let count: Int
  var disabled: Bool = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label {
        Text(count > 0 ? "播放全部 \(count)" : "播放全部")
      } icon: {
        Image(systemName: "play.fill")
          .font(.system(size: 11, weight: .bold))
      }
    }
    .buttonStyle(SodaPrimaryButtonStyle())
    .disabled(disabled || count <= 0)
  }
}
