import Foundation

enum NavDestination: String, CaseIterable, Identifiable, Hashable {
  case home
  case scenes
  case search
  case liked
  case library
  case settings
  case nowPlaying
  case artist
  case album

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: return "推荐"
    case .scenes: return "听歌模式"
    case .search: return "搜索"
    case .liked: return "我喜欢的音乐"
    case .library: return "我的歌单"
    case .settings: return "设置"
    case .nowPlaying: return "正在播放"
    case .artist: return "音乐人"
    case .album: return "专辑"
    }
  }

  var systemImage: String {
    switch self {
    case .home: return "house"
    case .scenes: return "radio"
    case .search: return "magnifyingglass"
    case .liked: return "heart"
    case .library: return "list.bullet"
    case .settings: return "gearshape"
    case .nowPlaying: return "music.note"
    case .artist: return "person"
    case .album: return "opticaldisc"
    }
  }

  /// 侧栏可见项（不含播放页 / 详情页）。
  static var sidebarItems: [NavDestination] {
    [.home, .scenes, .search, .liked, .library, .settings]
  }
}

enum PlayMode: String, CaseIterable, Codable, Hashable {
  case listLoop
  case repeatOne
  case shuffle

  var label: String {
    switch self {
    case .listLoop: return "列表循环"
    case .repeatOne: return "单曲循环"
    case .shuffle: return "随机播放"
    }
  }

  var systemImage: String {
    switch self {
    case .listLoop: return "repeat"
    case .repeatOne: return "repeat.1"
    case .shuffle: return "shuffle"
    }
  }

  func next() -> PlayMode {
    switch self {
    case .listLoop: return .repeatOne
    case .repeatOne: return .shuffle
    case .shuffle: return .listLoop
    }
  }
}

struct AccountInfo: Codable, Hashable {
  var nickname: String
  var userId: String
  var avatar: String
  var vip: Bool

  static let empty = AccountInfo(nickname: "", userId: "", avatar: "", vip: false)

  enum CodingKeys: String, CodingKey {
    case nickname
    case userId = "user_id"
    case avatar = "avatar_url"
    case vip
  }

  init(nickname: String, userId: String, avatar: String, vip: Bool) {
    self.nickname = nickname
    self.userId = userId
    self.avatar = avatar
    self.vip = vip
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
    userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
    avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    vip = try c.decodeIfPresent(Bool.self, forKey: .vip) ?? false
  }
}

struct SodaTrack: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var artist: String
  var album: String
  var artistId: String
  var albumId: String
  var cover: String
  var durationMs: Int
  var isVIP: Bool

  enum CodingKeys: String, CodingKey {
    case id, title, artist, album, cover
    case artistId = "artist_id"
    case albumId = "album_id"
    case durationMs = "duration_ms"
    case isVIP = "is_vip"
  }

  init(
    id: String,
    title: String,
    artist: String,
    album: String = "",
    artistId: String = "",
    albumId: String = "",
    cover: String = "",
    durationMs: Int = 0,
    isVIP: Bool = false
  ) {
    self.id = id
    self.title = title
    self.artist = artist
    self.album = album
    self.artistId = artistId
    self.albumId = albumId
    self.cover = cover
    self.durationMs = durationMs
    self.isVIP = isVIP
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
    album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
    artistId = try c.decodeIfPresent(String.self, forKey: .artistId) ?? ""
    albumId = try c.decodeIfPresent(String.self, forKey: .albumId) ?? ""
    cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
    durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
    isVIP = try c.decodeIfPresent(Bool.self, forKey: .isVIP) ?? false
  }

  var coverURL: URL? {
    guard !cover.isEmpty else { return nil }
    return URL(string: cover)
  }

  var subtitle: String {
    if album.isEmpty { return artist }
    return "\(artist) · \(album)"
  }

  var durationLabel: String {
    let total = max(0, durationMs / 1000)
    return String(format: "%d:%02d", total / 60, total % 60)
  }
}

struct SceneItem: Codable, Identifiable, Hashable {
  var id: String { "\(sceneModeId)-\(subQueueType)" }
  var text: String
  var sceneModeId: Int
  var subQueueType: String
  var cover: String

  enum CodingKeys: String, CodingKey {
    case text, cover
    case sceneModeId = "scene_mode_id"
    case subQueueType = "sub_queue_type"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    // scene_mode_id 可能是 -1；sub_queue_type 可能是字符串。
    if let intID = try? c.decode(Int.self, forKey: .sceneModeId) {
      sceneModeId = intID
    } else if let strID = try? c.decode(String.self, forKey: .sceneModeId),
      let parsed = Int(strID)
    {
      sceneModeId = parsed
    } else {
      sceneModeId = -1
    }
    if let s = try? c.decode(String.self, forKey: .subQueueType) {
      subQueueType = s
    } else if let i = try? c.decode(Int.self, forKey: .subQueueType) {
      subQueueType = String(i)
    } else {
      subQueueType = ""
    }
    cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
  }
}

struct PlaylistItem: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var cover: String
  var trackCount: Int

  enum CodingKeys: String, CodingKey {
    case id, title, cover
    case trackCount = "track_count"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
    trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
  }

  var coverURL: URL? {
    guard !cover.isEmpty else { return nil }
    return URL(string: cover)
  }
}

struct RecommendPage: Codable {
  var tracks: [SodaTrack]
  var fetchCounter: UInt32
  var hasMore: Bool
  var didFirstUseTime: UInt64

  enum CodingKeys: String, CodingKey {
    case tracks
    case fetchCounter = "fetch_counter"
    case hasMore = "has_more"
    case didFirstUseTime = "did_first_use_time"
  }
}

struct ArtistInfo: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var avatar: String
  var trackCount: Int
  var followerCount: Int

  enum CodingKeys: String, CodingKey {
    case id, name, avatar
    case trackCount = "track_count"
    case followerCount = "follower_count"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    name = try c.decodeIfPresent(String.self, forKey: .name) ?? "音乐人"
    avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
    trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
    followerCount = try c.decodeIfPresent(Int.self, forKey: .followerCount) ?? 0
  }

  var avatarURL: URL? {
    guard !avatar.isEmpty else { return nil }
    return URL(string: avatar)
  }
}

struct AlbumItem: Codable, Identifiable, Hashable {
  var id: String
  var title: String
  var cover: String
  var artist: String
  var trackCount: Int
  var releaseDate: Int64
  var company: String

  enum CodingKeys: String, CodingKey {
    case id, title, cover, artist, company
    case trackCount = "track_count"
    case releaseDate = "release_date"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? "专辑"
    cover = try c.decodeIfPresent(String.self, forKey: .cover) ?? ""
    artist = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
    trackCount = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
    releaseDate = try c.decodeIfPresent(Int64.self, forKey: .releaseDate) ?? 0
    company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
  }

  var coverURL: URL? {
    guard !cover.isEmpty else { return nil }
    return URL(string: cover)
  }

  var releaseLabel: String {
    guard releaseDate > 0 else { return "" }
    let date = Date(timeIntervalSince1970: TimeInterval(releaseDate))
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "zh_CN")
    fmt.dateFormat = "yyyy-MM-dd"
    return fmt.string(from: date)
  }
}

struct ArtistDetailPage: Codable {
  var artist: ArtistInfo
  var description: String
  var tracks: [SodaTrack]
  var albums: [AlbumItem]
  var tracksHasMore: Bool

  enum CodingKeys: String, CodingKey {
    case artist, description, tracks, albums
    case tracksHasMore = "tracks_has_more"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    artist = try c.decode(ArtistInfo.self, forKey: .artist)
    description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
    tracks = try c.decodeIfPresent([SodaTrack].self, forKey: .tracks) ?? []
    albums = try c.decodeIfPresent([AlbumItem].self, forKey: .albums) ?? []
    tracksHasMore = try c.decodeIfPresent(Bool.self, forKey: .tracksHasMore) ?? false
  }
}

struct AlbumDetailPage: Codable {
  var album: AlbumItem
  var tracks: [SodaTrack]

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    album = try c.decode(AlbumItem.self, forKey: .album)
    tracks = try c.decodeIfPresent([SodaTrack].self, forKey: .tracks) ?? []
  }

  enum CodingKeys: String, CodingKey {
    case album, tracks
  }
}

struct LyricWord: Hashable {
  var startSeconds: Double
  var endSeconds: Double
  var text: String
}

/// 对齐 SodaM `LyricLine`：支持增强 LRC 逐字时间轴。
struct LyricLine: Identifiable, Hashable {
  var id: Int { Int((startSeconds * 1000).rounded()) }
  var startSeconds: Double
  var endSeconds: Double
  var text: String
  var words: [LyricWord]
  var hasWordTimeline: Bool

  /// 兼容旧字段名。
  var timeMs: Int { Int((startSeconds * 1000).rounded()) }

  func activeEndSeconds(nextStart: Double?) -> Double {
    if let next = nextStart, next > startSeconds {
      return next
    }
    return nextStart ?? .infinity
  }

  func isActive(at position: Double, nextStart: Double?) -> Bool {
    position >= startSeconds && position < activeEndSeconds(nextStart: nextStart)
  }

  func charsRevealed(at position: Double) -> (revealed: Double, total: Double)? {
    guard hasWordTimeline else { return nil }
    let chars = Array(text)
    let total = Double(chars.count)
    guard total > 0 else { return nil }
    let timeline = charTimeline(chars: chars)
    var done = 0.0
    for (start, end) in timeline {
      if position >= end {
        done += 1
        continue
      }
      if position > start {
        let span = end - start
        if span > 0 {
          done += min(1, max(0, (position - start) / span))
        } else {
          done += 1
        }
      }
      break
    }
    return (done, total)
  }

  func highlightFraction(at position: Double) -> Double {
    if position < startSeconds { return 0 }
    if position >= endSeconds { return 1 }
    if hasWordTimeline, let (revealed, total) = charsRevealed(at: position), total > 0 {
      return min(1, max(0, revealed / total))
    }
    let span = endSeconds - startSeconds
    if span <= 0 { return 1 }
    return min(1, max(0, (position - startSeconds) / span))
  }

  private func charTimeline(chars: [Character]) -> [(Double, Double)] {
    var assigned: [(Double, Double)?] = Array(repeating: nil, count: chars.count)
    var cursor = 0
    for word in words {
      let needle = word.text.filter { !$0.isWhitespace }
      if needle.isEmpty { continue }
      guard
        let (begin, endIx) = findSubsequence(haystack: chars, needle: Array(needle), from: cursor)
      else { continue }
      let count = endIx - begin
      if count == 0 { continue }
      let span = max(0, word.endSeconds - word.startSeconds)
      let per = span / Double(count)
      for offset in 0..<count {
        let start = word.startSeconds + per * Double(offset)
        assigned[begin + offset] = (start, start + per)
      }
      cursor = endIx
    }

    if assigned.allSatisfy({ $0 == nil }) {
      let span = max(0, endSeconds - startSeconds)
      let per = span / Double(chars.count)
      return (0..<chars.count).map { index in
        let start = startSeconds + per * Double(index)
        return (start, start + per)
      }
    }

    var index = 0
    while index < assigned.count {
      if assigned[index] != nil {
        index += 1
        continue
      }
      let runStart = index
      while index < assigned.count && assigned[index] == nil {
        index += 1
      }
      let runEnd = index
      let left: Double = {
        if runStart > 0, let prev = assigned[runStart - 1] {
          return prev.1
        }
        return startSeconds
      }()
      let right: Double = {
        if runEnd < assigned.count, let next = assigned[runEnd] {
          return next.0
        }
        return endSeconds
      }()
      let count = runEnd - runStart
      let usable = max(0, right - left)
      let step = count > 0 ? usable / Double(count) : 0
      for offset in 0..<count {
        let start = left + step * Double(offset)
        assigned[runStart + offset] = (start, start + step)
      }
    }

    return assigned.map { $0 ?? (startSeconds, endSeconds) }
  }
}

struct BridgeErrorBody: Codable {
  var error: String
  var hint: String
}

enum SodaPlusError: LocalizedError {
  case bridgeMissing
  case bridge(String, hint: String)
  case decoding(String)
  case emptyQuery
  case notLoggedIn

  var errorDescription: String? {
    switch self {
    case .bridgeMissing:
      return "未找到 sodaplus-bridge。请先运行 ./scripts/build-bridge.sh"
    case .bridge(let message, let hint):
      return "\(message)\n\(hint)"
    case .decoding(let detail):
      return "桥接返回无法解析：\(detail)"
    case .emptyQuery:
      return "请输入搜索关键词"
    case .notLoggedIn:
      return "请先在设置中登录"
    }
  }
}

enum LyricParser {
  /// 对齐 SodaM `parse_lrc`：增强 LRC 保留逐字轴，兼容普通 LRC。
  static func parse(_ raw: String) -> [LyricLine] {
    var lines: [LyricLine] = []
    for rawLine in raw.split(whereSeparator: \.isNewline) {
      var rest = String(rawLine).trimmingCharacters(in: .whitespaces)
      var startSeconds: Double?
      var lineDuration: Double?

      while rest.hasPrefix("[") {
        guard let close = rest.firstIndex(of: "]") else { break }
        let tag = String(rest[rest.index(after: rest.startIndex)..<close])
        let tail = String(rest[rest.index(after: close)...])
        if let comma = tag.firstIndex(of: ",") {
          let first = String(tag[..<comma]).trimmingCharacters(in: .whitespaces)
          let second = String(tag[tag.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
          guard let firstMs = Double(first) else { break }
          let secondMs = Double(second) ?? 0
          startSeconds = firstMs / 1000
          lineDuration = max(0, secondMs) / 1000
          rest = tail.trimmingCharacters(in: .whitespaces)
          break
        }
        if let value = parseLRCTimeTag(tag) {
          startSeconds = value
          rest = tail.trimmingCharacters(in: .whitespaces)
        } else {
          break
        }
      }

      guard let start = startSeconds else { continue }
      let text = stripWordTags(rest).trimmingCharacters(in: .whitespaces)
      guard !text.isEmpty else { continue }

      var words = parseWordTags(rest, lineStart: start, lineDuration: lineDuration)
      let hasWordTimeline = !words.isEmpty
      if words.isEmpty {
        let end = lineDuration.map { start + $0 } ?? start
        words.append(LyricWord(startSeconds: start, endSeconds: end, text: text))
      }
      words.sort { $0.startSeconds < $1.startSeconds }
      let endSeconds: Double
      if let duration = lineDuration, duration > 0 {
        endSeconds = start + duration
      } else {
        endSeconds = words.map(\.endSeconds).max() ?? start
      }
      lines.append(
        LyricLine(
          startSeconds: start,
          endSeconds: endSeconds,
          text: text,
          words: words,
          hasWordTimeline: hasWordTimeline
        )
      )
    }
    lines.sort { $0.startSeconds < $1.startSeconds }
    var deduped: [LyricLine] = []
    for line in lines {
      if let last = deduped.last,
        abs(last.startSeconds - line.startSeconds) < 1e-9,
        last.text == line.text
      {
        continue
      }
      deduped.append(line)
    }
    return deduped
  }

  private static func parseLRCTimeTag(_ tag: String) -> Double? {
    guard let colon = tag.firstIndex(of: ":") else { return nil }
    let minutes = Double(tag[..<colon].trimmingCharacters(in: .whitespaces))
    let seconds = Double(tag[tag.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    guard let minutes, let seconds else { return nil }
    return minutes * 60 + seconds
  }

  private static func stripWordTags(_ content: String) -> String {
    var text = ""
    var inside = false
    for character in content {
      switch character {
      case "<": inside = true
      case ">": inside = false
      default:
        if !inside { text.append(character) }
      }
    }
    return text
  }

  private static func parseWordTags(
    _ content: String,
    lineStart: Double,
    lineDuration: Double?
  ) -> [LyricWord] {
    var words: [LyricWord] = []
    var cursor = content.startIndex
    var current: (Double, Double)?
    var sawTimelineTag = false

    while let openRel = content[cursor...].firstIndex(of: "<") {
      pushTextBefore(
        &words,
        text: String(content[cursor..<openRel]),
        lineStart: lineStart,
        current: current
      )
      guard let closeRel = content[openRel...].firstIndex(of: ">") else { break }
      let tagStart = content.index(after: openRel)
      let tag = String(content[tagStart..<closeRel])
      if tag.hasPrefix("/") {
        current = nil
      } else if let parsed = parseWordTag(tag, lineStart: lineStart) {
        sawTimelineTag = true
        current = parsed
      } else {
        current = nil
      }
      cursor = content.index(after: closeRel)
    }
    pushTextBefore(
      &words,
      text: String(content[cursor...]),
      lineStart: lineStart,
      current: current
    )
    if !sawTimelineTag {
      words.removeAll()
    }
    _ = lineDuration
    return words
  }

  private static func pushTextBefore(
    _ words: inout [LyricWord],
    text: String,
    lineStart: Double,
    current: (Double, Double)?
  ) {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    let (start, end) = current ?? (lineStart, lineStart)
    words.append(
      LyricWord(startSeconds: start, endSeconds: max(start, end), text: trimmed)
    )
  }

  /// 汽水格式 `<offset,span,flag>`，offset 相对行首，单位毫秒。
  private static func parseWordTag(_ tag: String, lineStart: Double) -> (Double, Double)? {
    let parts = tag.split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count >= 2,
      let offset = Double(parts[0].trimmingCharacters(in: .whitespaces)),
      let span = Double(parts[1].trimmingCharacters(in: .whitespaces))
    else { return nil }
    let start = lineStart + offset / 1000
    let end = start + max(0, span) / 1000
    return (start, end)
  }
}

private func findSubsequence(
  haystack: [Character],
  needle: [Character],
  from: Int
) -> (Int, Int)? {
  guard !needle.isEmpty else { return nil }
  for begin in from..<haystack.count {
    var at = begin
    var first: Int?
    var matched = true
    for want in needle {
      while at < haystack.count && haystack[at].isWhitespace {
        at += 1
      }
      if at >= haystack.count || haystack[at] != want {
        matched = false
        break
      }
      if first == nil { first = at }
      at += 1
    }
    if matched, let first {
      return (first, at)
    }
  }
  return nil
}
