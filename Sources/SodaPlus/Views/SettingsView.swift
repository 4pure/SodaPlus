import SwiftUI

/// 对齐汽水音乐设置页：左侧分类 + 右侧分区卡片行；能力侧对齐 SodaM 可落地项。
struct SettingsView: View {
  @ObservedObject var model: AppModel
  @EnvironmentObject private var theme: ThemeStore

  var body: some View {
    HStack(spacing: 0) {
      categorySidebar
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.surface)

      Rectangle()
        .fill(theme.border.opacity(0.7))
        .frame(width: 1)

      ScrollView {
        VStack(alignment: .leading, spacing: Theme.spaceXL) {
          content(for: model.settingsCategory)
        }
        .padding(.horizontal, Theme.spaceXL)
        .padding(.vertical, Theme.spaceLG)
        .frame(maxWidth: 720, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(theme.surface)
    }
    .background(theme.surface)
    .onAppear {
      model.refreshAudioCacheUsage()
      model.refreshLaunchAtLoginStatus()
    }
  }

  // MARK: - Sidebar

  private var categorySidebar: some View {
    VStack(alignment: .leading, spacing: Theme.spaceXS) {
      ForEach(SettingsCategory.allCases) { category in
        Button {
          model.settingsCategory = category
        } label: {
          HStack(spacing: Theme.spaceSM) {
            Circle()
              .fill(model.settingsCategory == category ? theme.text : Color.clear)
              .frame(width: 5, height: 5)
            Text(category.title)
              .font(.body.weight(model.settingsCategory == category ? .semibold : .regular))
              .foregroundStyle(
                model.settingsCategory == category ? theme.text : theme.textMuted
              )
            Spacer(minLength: 0)
          }
          .padding(.horizontal, Theme.spaceLG)
          .frame(height: 40)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      Spacer(minLength: 0)
    }
    .padding(.top, Theme.spaceLG)
  }

  // MARK: - Content

  @ViewBuilder
  private func content(for category: SettingsCategory) -> some View {
    switch category {
    case .playback:
      sectionHeader("播放相关")
      settingsCard {
        SettingsPickerRow(
          title: "在线播放音质",
          value: model.settings.qualityPreference.title,
          options: QualityPreference.allCases,
          titleFor: { $0.title },
          isSelected: { $0 == model.settings.qualityPreference },
          onSelect: { model.setQuality($0) }
        )
        Text(model.settings.qualityPreference.hint)
          .font(.caption)
          .foregroundStyle(theme.textFaint)
          .padding(.horizontal, Theme.spaceLG)
          .padding(.bottom, Theme.spaceMD)
        Text("已缓存歌曲保持原档位；切换从下一首生效。")
          .font(.caption)
          .foregroundStyle(theme.textFaint)
          .padding(.horizontal, Theme.spaceLG)
          .padding(.bottom, Theme.spaceMD)
      }

    case .shortcuts:
      sectionHeader("快捷键")
      settingsCard {
        shortcutHeader
        shortcutRow("打开设置", inApp: "⌘ ,", global: "—")
        divider
        shortcutRow("播放 / 暂停", inApp: "空格", global: "—")
        divider
        shortcutRow("上一首", inApp: "⌘ ←", global: "—")
        divider
        shortcutRow("下一首", inApp: "⌘ →", global: "—")
        divider
        tipRow(
          "全局快捷键",
          "系统媒体键与菜单栏可在后台控制；自定义全局快捷键尚未接入"
        )
      }

    case .usage:
      sectionHeader("使用相关")
      settingsCard {
        SettingsPickerRow(
          title: "外观",
          value: model.settings.appearanceMode.title,
          options: AppearanceMode.allCases,
          titleFor: { $0.title },
          isSelected: { $0 == model.settings.appearanceMode },
          onSelect: { model.setAppearanceMode($0) }
        )
        divider
        toggleRow(
          title: "开机自动启动",
          subtitle: "若无效，请到「系统设置 → 通用 → 登录项」确认",
          isOn: Binding(
            get: { model.launchAtLoginEnabled },
            set: { model.setLaunchAtLogin($0) }
          )
        )
        divider
        SettingsPickerRow(
          title: "关闭主窗口",
          value: model.settings.closeWindowAction.title,
          options: CloseWindowAction.allCases,
          titleFor: { $0.title },
          subtitleFor: { $0.subtitle },
          isSelected: { $0 == model.settings.closeWindowAction },
          onSelect: { model.setCloseWindowAction($0) }
        )
        Text(model.settings.closeWindowAction.subtitle)
          .font(.caption)
          .foregroundStyle(theme.textFaint)
          .padding(.horizontal, Theme.spaceLG)
          .padding(.bottom, Theme.spaceMD)
      }

      sectionHeader("缓存")
      settingsCard {
        actionRow(
          title: "清除缓存",
          subtitle: model.isMeasuringCache
            ? "计算大小中…"
            : "\(AppModel.humanBytes(model.audioCacheBytes)) · \(model.audioCacheFileCount) 个文件",
          chevron: true
        ) {
          model.clearAudioCache()
        }
        divider
        VStack(alignment: .leading, spacing: Theme.spaceSM) {
          HStack {
            Text("音频缓存上限")
              .foregroundStyle(theme.text)
            Spacer()
            Text(AppModel.humanBytes(model.settings.audioCacheLimitBytes))
              .foregroundStyle(theme.textMuted)
          }
          .padding(.horizontal, Theme.spaceLG)
          .padding(.top, Theme.spaceMD)

          cacheLimitChips
            .padding(.horizontal, Theme.spaceLG)

          Text("自动清理较早使用的歌曲；正在播放的文件暂时保留。")
            .font(.caption)
            .foregroundStyle(theme.textFaint)
            .padding(.horizontal, Theme.spaceLG)
            .padding(.bottom, Theme.spaceMD)
        }
        divider
        actionRow(title: "打开缓存目录", subtitle: nil, chevron: true) {
          model.openAudioCacheFolder()
        }
      }

    case .account:
      sectionHeader("账户")
      accountCard
      if !model.isLoggedIn {
        settingsCard {
          CookiePasteSection(cookieDraft: $model.cookieDraft) {
            model.saveCookieFromDraft()
          }
        }
      }

    case .advanced:
      sectionHeader("高级")
      settingsCard {
        VStack(alignment: .leading, spacing: Theme.spaceSM) {
          Text("签名服务")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(theme.text)
          Text("VIP 整曲鉴权用；默认与开源 SodaM 公共地址一致，可换成自建服务。")
            .font(.caption)
            .foregroundStyle(theme.textFaint)

          labeledField("URL", text: $model.signerURLDraft)
          labeledField("Token", text: $model.signerTokenDraft)

          HStack(spacing: Theme.spaceSM) {
            Button("保存") { model.saveSignerFromDraft() }
              .buttonStyle(SodaPrimaryButtonStyle())
            Button("恢复默认") { model.resetSignerToDefault() }
              .buttonStyle(SodaSecondaryButtonStyle())
          }
          .padding(.top, Theme.spaceXS)
        }
        .padding(Theme.spaceLG)
      }

    case .about:
      sectionHeader("关于")
      settingsCard {
        HStack {
          Text("关于 SodaPlus")
            .foregroundStyle(theme.text)
          Spacer()
          Text(model.appVersionLabel)
            .foregroundStyle(theme.textMuted)
        }
        .padding(.horizontal, Theme.spaceLG)
        .frame(minHeight: 48)
        divider
        actionRow(title: "打开配置文件", subtitle: nil, chevron: true) {
          model.openConfigFile()
        }
        divider
        VStack(alignment: .leading, spacing: Theme.spaceSM) {
          Text("非官方 Swift 客户端。交互对齐开源 SodaM；音乐能力由 libresoda 提供。与字节 / 汽水官方无关。AGPL-3.0。")
            .font(.caption)
            .foregroundStyle(theme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.spaceLG)
      }
    }
  }

  // MARK: - Shared pieces

  private func sectionHeader(_ title: String) -> some View {
    Text(title)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(theme.textMuted)
  }

  private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.surfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }

  private var divider: some View {
    Rectangle()
      .fill(theme.border.opacity(0.7))
      .frame(height: 1)
      .padding(.leading, Theme.spaceLG)
  }

  private func toggleRow(title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
    HStack(alignment: .center, spacing: Theme.spaceLG) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .foregroundStyle(theme.text)
        if let subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(theme.textFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Theme.spaceMD)
      Toggle("", isOn: isOn)
        .labelsHidden()
        .toggleStyle(.switch)
        .tint(Color(hex: 0x3DDB7A))
    }
    .padding(.horizontal, Theme.spaceLG)
    .padding(.vertical, Theme.spaceMD)
  }

  private func actionRow(
    title: String,
    subtitle: String?,
    chevron: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Text(title)
          .foregroundStyle(theme.text)
        Spacer()
        if let subtitle {
          Text(subtitle)
            .foregroundStyle(theme.textMuted)
        }
        if chevron {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textFaint)
        }
      }
      .padding(.horizontal, Theme.spaceLG)
      .frame(minHeight: 48)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func tipRow(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .foregroundStyle(theme.text)
      Text(subtitle)
        .font(.caption)
        .foregroundStyle(theme.textFaint)
    }
    .padding(.horizontal, Theme.spaceLG)
    .padding(.vertical, Theme.spaceMD)
  }

  private var shortcutHeader: some View {
    HStack {
      Text("功能")
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("应用内")
        .frame(width: 88, alignment: .trailing)
      Text("全局")
        .frame(width: 88, alignment: .trailing)
    }
    .font(.caption.weight(.medium))
    .foregroundStyle(theme.textFaint)
    .padding(.horizontal, Theme.spaceLG)
    .padding(.vertical, Theme.spaceSM)
  }

  private func shortcutRow(_ title: String, inApp: String, global: String) -> some View {
    HStack {
      Text(title)
        .foregroundStyle(theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
      keyCap(inApp)
        .frame(width: 88, alignment: .trailing)
      keyCap(global)
        .frame(width: 88, alignment: .trailing)
    }
    .padding(.horizontal, Theme.spaceLG)
    .frame(minHeight: 44)
  }

  private func keyCap(_ text: String) -> some View {
    Text(text)
      .font(.caption.monospaced())
      .foregroundStyle(theme.textMuted)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(theme.surfaceHover)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private var cacheLimitChips: some View {
    let current = model.settings.audioCacheLimitMB
    let chips: [(String, UInt64)] = [
      ("−1 GiB", max(current, 2048) - 1024),
      ("5 GiB", 5 * 1024),
      ("10 GiB", 10 * 1024),
      ("20 GiB", 20 * 1024),
      ("50 GiB", 50 * 1024),
      ("+1 GiB", min(current + 1024, 1024 * 1024)),
    ]
    return HStack(spacing: Theme.spaceSM) {
      ForEach(Array(chips.enumerated()), id: \.offset) { _, item in
        Button(item.0) {
          model.setAudioCacheLimitMB(item.1)
        }
        .buttonStyle(CacheChipButtonStyle(selected: current == item.1))
      }
    }
  }

  private func labeledField(_ title: String, text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: Theme.spaceXS) {
      Text(title)
        .font(.caption)
        .foregroundStyle(theme.textFaint)
      TextField(title, text: text)
        .textFieldStyle(.plain)
        .font(.system(.caption, design: .monospaced))
        .padding(.horizontal, Theme.spaceMD)
        .frame(height: Theme.control)
        .background(theme.bg)
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
            .stroke(theme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    }
  }

  private var accountCard: some View {
    settingsCard {
      HStack(spacing: Theme.spaceLG) {
        avatarView
          .frame(width: 64, height: 64)

        VStack(alignment: .leading, spacing: Theme.spaceXS) {
          Text(
            model.isLoggedIn
              ? (model.account.nickname.isEmpty ? "已登录" : model.account.nickname)
              : "未登录"
          )
          .font(.title3.weight(.semibold))
          .foregroundStyle(theme.text)

          Text(
            model.isLoggedIn
              ? "用户 \(model.account.userId.isEmpty ? "—" : model.account.userId) · \(model.account.vip ? "VIP" : "非 VIP")"
              : "登录后才能使用搜索、歌单与播放"
          )
          .font(.subheadline)
          .foregroundStyle(theme.textMuted)

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
      .padding(Theme.spaceLG)
    }
  }

  @ViewBuilder
  private var avatarView: some View {
    if model.isLoggedIn, let url = model.account.avatarURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFill()
        default:
          avatarPlaceholder
        }
      }
      .clipShape(Circle())
    } else {
      avatarPlaceholder
    }
  }

  private var avatarPlaceholder: some View {
    Circle()
      .fill(theme.surfaceHover)
      .overlay {
        if model.isLoggedIn, !model.account.nickname.isEmpty {
          Text(String(model.account.nickname.prefix(1)))
            .font(.title2.weight(.bold))
            .foregroundStyle(theme.text)
        } else {
          Image(systemName: "person.fill")
            .foregroundStyle(theme.textFaint)
        }
      }
  }
}

// MARK: - Helpers

/// 设置页选择行：右侧仅一枚箭头；弹出层用主题色卡片，避免系统 Menu 双边箭头与风格割裂。
private struct SettingsPickerRow<Option: Identifiable & Hashable>: View {
  let title: String
  let value: String
  let options: [Option]
  let titleFor: (Option) -> String
  var subtitleFor: ((Option) -> String?)? = nil
  let isSelected: (Option) -> Bool
  let onSelect: (Option) -> Void

  @EnvironmentObject private var theme: ThemeStore
  @State private var isPresented = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.16)) {
          isPresented.toggle()
        }
      } label: {
        HStack(spacing: Theme.spaceSM) {
          Text(title)
            .foregroundStyle(theme.text)
          Spacer(minLength: Theme.spaceMD)
          Text(value)
            .foregroundStyle(theme.textMuted)
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.textFaint)
            .rotationEffect(.degrees(isPresented ? 180 : 0))
        }
        .padding(.horizontal, Theme.spaceLG)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isPresented {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(options) { option in
            pickerOptionButton(option)
          }
        }
        .padding(.horizontal, Theme.spaceMD)
        .padding(.bottom, Theme.spaceMD)
      }
    }
  }

  private func pickerOptionButton(_ option: Option) -> some View {
    let selected = isSelected(option)
    let subtitle = subtitleFor?(option)
    return Button {
      onSelect(option)
      isPresented = false
    } label: {
      HStack(alignment: .center, spacing: Theme.spaceMD) {
        VStack(alignment: .leading, spacing: 2) {
          Text(titleFor(option))
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(theme.text)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(theme.textFaint)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: Theme.spaceSM)
        if selected {
          Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(theme.accent)
        }
      }
      .padding(.horizontal, Theme.spaceMD)
      .padding(.vertical, Theme.spaceSM)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(selected ? theme.accentSoft : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct CookiePasteSection: View {
  @Binding var cookieDraft: String
  let onSave: () -> Void

  @EnvironmentObject private var theme: ThemeStore
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: Theme.spaceSM) {
          Text("或粘贴 Cookie")
            .foregroundStyle(theme.text)
          Spacer(minLength: 0)
          Image(systemName: "chevron.down")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(theme.textFaint)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.horizontal, Theme.spaceLG)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        VStack(alignment: .leading, spacing: Theme.spaceSM) {
          TextEditor(text: $cookieDraft)
            .font(.system(.caption, design: .monospaced))
            .frame(minHeight: 80)
            .scrollContentBackground(.hidden)
            .padding(Theme.spaceSM)
            .background(theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
          Button("保存 Cookie", action: onSave)
            .buttonStyle(SodaSecondaryButtonStyle())
        }
        .padding(.horizontal, Theme.spaceLG)
        .padding(.bottom, Theme.spaceLG)
      }
    }
  }
}

private struct CacheChipButtonStyle: ButtonStyle {
  let selected: Bool
  @EnvironmentObject private var theme: ThemeStore

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.caption)
      .foregroundStyle(selected ? theme.accentForeground : theme.textMuted)
      .padding(.horizontal, Theme.spaceMD)
      .frame(height: 28)
      .background(selected ? theme.accent : theme.surfaceHover)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .opacity(configuration.isPressed ? 0.85 : 1)
  }
}
