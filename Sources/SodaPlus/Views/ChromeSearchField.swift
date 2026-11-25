import AppKit
import SwiftUI

/// 顶栏搜索输入：默认不抢 first responder，只有用户点进框才进入输入态，避免空格被当成打字而吃掉播放/暂停。
struct ChromeSearchField: NSViewRepresentable {
  @Binding var text: String
  var placeholder: String
  var textColor: Color
  var placeholderColor: Color
  /// 外部置为 `true` 时主动聚焦（例如点了放大镜区域）。
  @Binding var focusRequest: Bool
  var onSubmit: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> LazyFocusTextField {
    let field = LazyFocusTextField(string: text)
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.commit(_:))
    field.lineBreakMode = .byTruncatingTail
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.cell?.usesSingleLineMode = true
    applyAppearance(to: field)
    return field
  }

  func updateNSView(_ field: LazyFocusTextField, context: Context) {
    context.coordinator.parent = self
    if field.stringValue != text {
      field.stringValue = text
    }
    applyAppearance(to: field)

    if focusRequest {
      field.beginEditingIfNeeded()
      DispatchQueue.main.async {
        focusRequest = false
      }
    }
  }

  private func applyAppearance(to field: LazyFocusTextField) {
    field.textColor = NSColor(textColor)
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder,
      attributes: [
        .foregroundColor: NSColor(placeholderColor),
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
      ]
    )
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: ChromeSearchField

    init(_ parent: ChromeSearchField) {
      self.parent = parent
    }

    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSTextField else { return }
      parent.text = field.stringValue
    }

    func controlTextDidEndEditing(_ obj: Notification) {
      (obj.object as? LazyFocusTextField)?.endEditingSession()
    }

    @objc func commit(_ sender: NSTextField) {
      parent.onSubmit()
      sender.window?.makeFirstResponder(nil)
      (sender as? LazyFocusTextField)?.endEditingSession()
    }

    func control(
      _ control: NSControl,
      textView: NSTextView,
      doCommandBy commandSelector: Selector
    ) -> Bool {
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        control.window?.makeFirstResponder(nil)
        (control as? LazyFocusTextField)?.endEditingSession()
        return true
      }
      return false
    }
  }
}

/// 未点过之前 `acceptsFirstResponder == false`，窗口激活/视图刷新都不会自动落光标。
final class LazyFocusTextField: NSTextField {
  private var userRequestedFocus = false

  override var acceptsFirstResponder: Bool { userRequestedFocus }

  override func mouseDown(with event: NSEvent) {
    beginEditingIfNeeded()
    super.mouseDown(with: event)
  }

  func beginEditingIfNeeded() {
    userRequestedFocus = true
    window?.makeFirstResponder(self)
  }

  func endEditingSession() {
    userRequestedFocus = false
  }

  override func resignFirstResponder() -> Bool {
    let ok = super.resignFirstResponder()
    if ok {
      userRequestedFocus = false
    }
    return ok
  }
}
