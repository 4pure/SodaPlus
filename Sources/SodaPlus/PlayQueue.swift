import Foundation

/// 对齐 SodaM `Queue`：列表循环 / 单曲循环 / 随机（含 history / shuffle_round）。
@MainActor
final class PlayQueue: ObservableObject {
  @Published private(set) var tracks: [SodaTrack] = []
  @Published private(set) var index: Int = 0
  @Published var mode: PlayMode = .listLoop {
    didSet {
      if mode == .shuffle {
        shuffleRound = buildShuffleRound()
      } else {
        shuffleRound = []
        history = []
        redo = nil
      }
    }
  }

  private var history: [Int] = []
  private var shuffleRound: [Int] = []
  private var redo: Int?

  var current: SodaTrack? {
    guard tracks.indices.contains(index) else { return nil }
    return tracks[index]
  }

  var isEmpty: Bool { tracks.isEmpty }

  /// 预取用：当前之后按播放顺序的后续曲（不含当前）。
  var upcoming: [SodaTrack] {
    Array(displayEntries.dropFirst().map(\.track))
  }

  /// 弹窗列表：当前曲置顶，其后按实际播放顺序（随机用 shuffleRound）。
  /// 用队列下标作身份，避免同曲重复 id 造成 LazyVStack 空白行。
  var displayEntries: [(queueIndex: Int, track: SodaTrack)] {
    guard !tracks.isEmpty else { return [] }
    guard tracks.indices.contains(index) else {
      return tracks.enumerated().map { (queueIndex: $0.offset, track: $0.element) }
    }
    var entries: [(queueIndex: Int, track: SodaTrack)] = [
      (queueIndex: index, track: tracks[index])
    ]
    switch mode {
    case .shuffle:
      for i in shuffleRound where tracks.indices.contains(i) {
        entries.append((queueIndex: i, track: tracks[i]))
      }
    case .listLoop, .repeatOne:
      if index + 1 < tracks.count {
        for i in (index + 1)..<tracks.count {
          entries.append((queueIndex: i, track: tracks[i]))
        }
      }
      if index > 0 {
        for i in 0..<index {
          entries.append((queueIndex: i, track: tracks[i]))
        }
      }
    }
    return entries
  }

  func replace(_ newTracks: [SodaTrack], start: Int = 0) {
    tracks = newTracks
    index = min(max(0, start), max(0, newTracks.count - 1))
    history = []
    redo = nil
    shuffleRound = mode == .shuffle ? buildShuffleRound() : []
  }

  @discardableResult
  func append(_ more: [SodaTrack]) -> Int {
    let known = Set(tracks.map(\.id))
    let fresh = more.filter { !known.contains($0.id) }
    tracks.append(contentsOf: fresh)
    if mode == .shuffle, !fresh.isEmpty {
      shuffleRound = buildShuffleRound()
    }
    return fresh.count
  }

  func insertNext(_ track: SodaTrack) {
    if let existing = tracks.firstIndex(where: { $0.id == track.id }) {
      if existing == index { return }
      tracks.remove(at: existing)
      let insertAt = min(index + 1, tracks.count)
      tracks.insert(track, at: insertAt)
      if existing < index { index -= 1 }
    } else {
      let insertAt = min(index + 1, tracks.count)
      tracks.insert(track, at: insertAt)
    }
    if mode == .shuffle {
      shuffleRound = buildShuffleRound()
    }
  }

  func jump(to newIndex: Int) {
    guard tracks.indices.contains(newIndex) else { return }
    if mode == .shuffle, newIndex != index {
      history.append(index)
      shuffleRound.removeAll { $0 == newIndex }
    }
    index = newIndex
  }

  /// 运行时发现不可播时就地打标（列表 / 队列同步灰显）。
  func markUnplayable(id: String) {
    guard let i = tracks.firstIndex(where: { $0.id == id }) else { return }
    tracks[i].playable = false
  }

  /// 从 `start` 起找下一首可播（含 start）；没有则 nil。
  func firstPlayableIndex(from start: Int = 0) -> Int? {
    guard !tracks.isEmpty else { return nil }
    let n = tracks.count
    let origin = min(max(0, start), n - 1)
    for offset in 0..<n {
      let i = (origin + offset) % n
      if tracks[i].playable { return i }
    }
    return nil
  }

  @discardableResult
  func advance() -> SodaTrack? {
    guard !tracks.isEmpty else { return nil }
    switch mode {
    case .repeatOne:
      break
    case .listLoop:
      index = (index + 1) % tracks.count
    case .shuffle:
      history.append(index)
      if let redoIndex = redo {
        redo = nil
        shuffleRound.removeAll { $0 == redoIndex }
        index = redoIndex
        if shuffleRound.isEmpty {
          history = []
          shuffleRound = buildShuffleRound()
        }
        return current
      }
      if let next = nextShuffleIndex() {
        index = next
        if shuffleRound.isEmpty {
          history = []
          shuffleRound = buildShuffleRound()
        }
      }
    }
    return current
  }

  /// 前进并跳过不可播；整圈都不可播则返回 nil（index 停在原处）。
  /// 步进一律按「下一首」语义（单曲循环也离开当前），避免卡在灰歌上。
  @discardableResult
  func advancePlayable(userInitiated: Bool = false) -> SodaTrack? {
    _ = userInitiated
    guard !tracks.isEmpty else { return nil }
    guard tracks.contains(where: \.playable) else { return nil }
    let origin = index
    for _ in 0..<tracks.count {
      guard let track = nextUser() else { return nil }
      if track.playable { return track }
      if index == origin { break }
    }
    index = origin
    return nil
  }

  /// 用户点「下一首」：单曲循环也前进。
  @discardableResult
  func nextUser() -> SodaTrack? {
    if mode == .repeatOne {
      let previous = mode
      mode = .listLoop
      let track = advance()
      mode = previous
      return track
    }
    return advance()
  }

  @discardableResult
  func previous() -> SodaTrack? {
    guard !tracks.isEmpty else { return nil }
    switch mode {
    case .listLoop, .repeatOne:
      index = (index - 1 + tracks.count) % tracks.count
    case .shuffle:
      if let last = history.popLast() {
        redo = index
        shuffleRound.insert(index, at: 0)
        index = last
      } else if tracks.count > 1 {
        index = (index - 1 + tracks.count) % tracks.count
      }
    }
    return current
  }

  /// 上一首并跳过不可播。
  @discardableResult
  func previousPlayable() -> SodaTrack? {
    guard !tracks.isEmpty else { return nil }
    guard tracks.contains(where: \.playable) else { return nil }
    let origin = index
    for _ in 0..<tracks.count {
      guard let track = previous() else { return nil }
      if track.playable { return track }
      if index == origin { break }
    }
    index = origin
    return nil
  }

  private func nextShuffleIndex() -> Int? {
    guard tracks.count > 1 else { return nil }
    if shuffleRound.isEmpty {
      shuffleRound = buildShuffleRound()
    }
    guard !shuffleRound.isEmpty else { return nil }
    return shuffleRound.removeFirst()
  }

  private func buildShuffleRound() -> [Int] {
    var round = Array(tracks.indices).filter { $0 != index }
    guard round.count > 1 else { return round }
    var state = UInt64(Date().timeIntervalSince1970 * 1_000_000)
    for i in stride(from: round.count - 1, through: 1, by: -1) {
      state = mix(state)
      let pick = Int(state % UInt64(i + 1))
      round.swapAt(i, pick)
    }
    return round
  }

  private func mix(_ value: UInt64) -> UInt64 {
    var v = value &+ 0x9E37_79B9_7F4A_7C15
    v = (v ^ (v >> 30)) &* 0xBF58_476D_1CE4_E5B9
    v = (v ^ (v >> 27)) &* 0x94D0_49BB_1331_11EB
    return v ^ (v >> 31)
  }
}
