import Foundation

/// 最近一次播放队列快照：再次打开时优先恢复，缓存命中可秒就绪。
struct PlaybackSession: Codable, Equatable {
  var tracks: [SodaTrack]
  var index: Int
  var position: Double
  var qualityTag: String

  static func fileURL() throws -> URL {
    try AppSettings.configURL()
      .deletingLastPathComponent()
      .appendingPathComponent("playback-session.json")
  }

  static func load() -> PlaybackSession? {
    do {
      let url = try fileURL()
      guard FileManager.default.fileExists(atPath: url.path) else { return nil }
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(PlaybackSession.self, from: data)
    } catch {
      print("[SodaPlus] load playback session failed: \(error)")
      return nil
    }
  }

  func save() {
    do {
      let url = try Self.fileURL()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      try encoder.encode(self).write(to: url, options: .atomic)
    } catch {
      print("[SodaPlus] save playback session failed: \(error)")
    }
  }

  static func clear() {
    do {
      let url = try fileURL()
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
    } catch {
      print("[SodaPlus] clear playback session failed: \(error)")
    }
  }
}
