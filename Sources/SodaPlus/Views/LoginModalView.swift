import SwiftUI

/// 对齐 SodaM `views/login.rs`：居中扫码卡片 + 遮罩。
struct LoginModalView: View {
  @ObservedObject var model: AppModel

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
        .ignoresSafeArea()
        .onTapGesture { model.closeLoginModal() }

      VStack(spacing: Theme.spaceLG) {
        Text("扫码登录")
          .font(.title2.weight(.bold))
          .foregroundStyle(Theme.text)

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
              .background(Theme.surfaceHover)
              .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
          }
        }

        VStack(spacing: Theme.spaceXS) {
          Text("请使用汽水音乐 App 扫码登录")
            .font(.subheadline)
            .foregroundStyle(Theme.text)
          Text(model.qrMessage.isEmpty ? "等待扫码…" : model.qrMessage)
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
            .multilineTextAlignment(.center)
          if !model.qrToken.isEmpty {
            Text("会话 \(String(model.qrToken.prefix(10)))…")
              .font(.caption2)
              .foregroundStyle(Theme.textFaint)
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
      .frame(width: 360)
      .background(Theme.surfaceElevated)
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .stroke(Theme.border, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
      .shadow(color: .black.opacity(0.45), radius: 28, y: 12)
    }
  }
}

struct SodaPrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline.weight(.medium))
      .foregroundStyle(Theme.accentForeground)
      .padding(.horizontal, Theme.spaceLG)
      .frame(height: Theme.control)
      .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1))
      .clipShape(Capsule())
  }
}

struct SodaSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline)
      .foregroundStyle(Theme.textMuted)
      .padding(.horizontal, Theme.spaceLG)
      .frame(height: Theme.control)
      .background(Theme.surfaceHover.opacity(configuration.isPressed ? 0.8 : 1))
      .clipShape(Capsule())
  }
}
