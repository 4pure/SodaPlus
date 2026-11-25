import AppKit
import SwiftUI

/// 侧栏导航图标：路径取自汽水桌面端 Sidebar SVG。
enum SidebarIconKind: Hashable {
  case home
  case scenes
  case liked
  case douyinLiked
  case history
  case playlist

  init?(destination: NavDestination) {
    switch destination {
    case .home: self = .home
    case .scenes: self = .scenes
    case .liked: self = .liked
    case .douyinLiked: self = .douyinLiked
    case .history: self = .history
    case .library: self = .playlist
    default: return nil
    }
  }
}

struct SidebarIcon: View {
  let kind: SidebarIconKind
  var size: CGFloat = Theme.icon

  var body: some View {
    if let image = Self.image(for: kind, pointSize: size) {
      Image(nsImage: image)
        .renderingMode(.template)
        .resizable()
        .interpolation(.high)
        .frame(width: size, height: size)
    } else {
      Image(systemName: "circle")
        .font(.system(size: size, weight: .medium))
        .frame(width: size, height: size)
    }
  }

  private static var cache: [String: NSImage] = [:]

  private static func image(for kind: SidebarIconKind, pointSize: CGFloat) -> NSImage? {
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let key = "\(kind)-\(Int(pointSize * 10))-\(scale)"
    if let cached = cache[key] { return cached }

    let spec = Self.spec(for: kind)
    let pixel = max(1, Int((pointSize * scale).rounded()))
    let svg = """
      <svg xmlns="http://www.w3.org/2000/svg" width="\(pixel)" height="\(pixel)" \
      viewBox="\(spec.viewBox)" fill="none">\
      <path \(spec.pathAttributes) d="\(spec.path)"/>\
      </svg>
      """
    guard let data = svg.data(using: .utf8),
      let image = NSImage(data: data)
    else { return nil }
    image.size = NSSize(width: pointSize, height: pointSize)
    // 模板着色：黑图 + SwiftUI foregroundStyle。
    image.isTemplate = true
    cache[key] = image
    return image
  }

  private struct Spec {
    let viewBox: String
    let path: String
    let pathAttributes: String
  }

  private static func spec(for kind: SidebarIconKind) -> Spec {
    switch kind {
    case .home:
      // PlayButtonSvg：播放三角
      return Spec(
        viewBox: "0 0 48 48",
        path:
          "M11 40.407V9.24c0-3.147 3.465-5.061 6.129-3.387L40.844 20.76c2.436 1.531 2.507 5.058.133 6.685L17.262 43.706c-2.654 1.82-6.262-.08-6.262-3.299Z",
        pathAttributes: #"fill="black""#
      )
    case .scenes:
      // SceneModeSvg：指南针
      return Spec(
        viewBox: "0 0 16 16",
        path:
          "M1.906 8a6 6 0 1 1 12 0 6 6 0 0 1-12 0Zm6-7.334a7.333 7.333 0 1 0 0 14.667 7.333 7.333 0 0 0 0-14.667ZM7.62 6.943l2.35-1.008-1.007 2.35c-.136.319-.167.38-.202.427a.667.667 0 0 1-.143.143c-.047.034-.108.065-.426.201l-2.35 1.007 1.007-2.35c.137-.318.167-.379.202-.426a.667.667 0 0 1 .143-.143c.047-.035.108-.065.426-.201Zm3.29-2.595c-.279-.089-.537-.01-.659.03a6.342 6.342 0 0 0-.477.19l-.023.01-2.657 1.14-.049.02c-.241.103-.454.194-.64.331a2 2 0 0 0-.43.429c-.136.187-.227.4-.33.64l-.021.05-1.139 2.657-.01.023c-.073.17-.145.338-.19.476-.04.122-.119.38-.03.658a1 1 0 0 0 .648.649c.278.088.536.01.658-.03.139-.046.306-.117.477-.19l.023-.01 2.657-1.14.049-.02c.241-.104.454-.194.64-.331a2 2 0 0 0 .43-.43c.136-.186.227-.399.33-.64l.021-.049 1.139-2.657.01-.023c.073-.171.145-.338.19-.477.04-.121.12-.38.03-.658a1 1 0 0 0-.648-.648Z",
        pathAttributes: #"fill="black" fill-rule="evenodd" clip-rule="evenodd""#
      )
    case .liked:
      // CollectSvg：心形描边
      return Spec(
        viewBox: "0 0 48 48",
        path:
          "M32 7c-4 0-6.5 2.5-8 4-1.5-1.5-4-4-8-4-5 0-8 2-10 5s-3.19 9.296 1 16c5 8 13 13 17 15 4-2 12-7 17-15 4.559-7.295 3-13 1-16s-5-5-10-5Z",
        pathAttributes: #"fill="none" stroke="black" stroke-width="4" stroke-linejoin="round""#
      )
    case .douyinLiked:
      // DouyinSvg：音符
      return Spec(
        viewBox: "0 0 20 20",
        path:
          "M12.581 2.32a1.125 1.125 0 0 0-2.248.059v11.043a2.637 2.637 0 1 1-2.637-2.637 1.125 1.125 0 0 0 0-2.25 4.887 4.887 0 1 0 4.887 4.887V7.029a5.895 5.895 0 0 0 3.67 1.274 1.125 1.125 0 1 0 0-2.25A3.67 3.67 0 0 1 12.58 2.32Z",
        pathAttributes: #"fill="black""#
      )
    case .history:
      // HistorySvg：时钟
      return Spec(
        viewBox: "0 0 20 20",
        path:
          "M17.5 10a7.5 7.5 0 1 1-15 0 7.5 7.5 0 0 1 15 0Zm1.667 0A9.167 9.167 0 1 1 .833 10a9.167 9.167 0 0 1 18.334 0ZM10 6.25a.833.833 0 0 0-1.667 0v4.583c0 .46.373.834.834.834h4.583a.833.833 0 0 0 0-1.667H10V6.25Z",
        pathAttributes: #"fill="black" fill-rule="evenodd" clip-rule="evenodd""#
      )
    case .playlist:
      // PlaylistSvg：圆点+横条列表
      return Spec(
        viewBox: "0 0 20 20",
        path:
          "M2.917 2.5a1.25 1.25 0 1 0 0 2.5 1.25 1.25 0 0 0 0-2.5Zm4.166.417a.833.833 0 1 0 0 1.666h10a.833.833 0 1 0 0-1.666h-10ZM1.667 10a1.25 1.25 0 1 1 2.5 0 1.25 1.25 0 0 1-2.5 0Zm1.25 5a1.25 1.25 0 1 0 0 2.5 1.25 1.25 0 0 0 0-2.5Zm3.333-5c0-.46.373-.833.833-.833h10a.833.833 0 1 1 0 1.666h-10A.833.833 0 0 1 6.25 10Zm.833 5.417a.833.833 0 1 0 0 1.666h10a.833.833 0 1 0 0-1.666h-10Z",
        pathAttributes: #"fill="black" fill-rule="evenodd" clip-rule="evenodd""#
      )
    }
  }
}
