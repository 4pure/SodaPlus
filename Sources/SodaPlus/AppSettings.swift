import Foundation

/// 对齐 SodaM `Settings` / `DEFAULT_SIGNER_*`。
struct AppSettings: Codable, Equatable {
  var signerURL: String
  var signerToken: String
  var cookie: String
  var deviceID: String
  var iid: String
  var fp: String
  var quality: String
  var volume: Float
  var volumeBeforeMute: Float
  var playMode: PlayMode
  var audioCacheLimitMB: UInt64
  var theme: String

  enum CodingKeys: String, CodingKey {
    case cookie, quality, volume, theme
    case signerURL = "signer_url"
    case signerToken = "signer_token"
    case deviceID = "device_id"
    case iid, fp
    case volumeBeforeMute = "volume_before_mute"
    case playMode = "play_mode"
    case audioCacheLimitMB = "audio_cache_limit_mb"
  }

  static let defaultSignerURL = "http://103.236.75.83:8899/sign"
  static let defaultSignerToken = "b356ad402bc31ee9e5a99cfdbf41eaa39961a562251c3359"

  static var `default`: AppSettings {
    AppSettings(
      signerURL: defaultSignerURL,
      signerToken: defaultSignerToken,
      cookie: "",
      deviceID: "",
      iid: "",
      fp: "",
      quality: "auto",
      volume: 1,
      volumeBeforeMute: 1,
      playMode: .listLoop,
      audioCacheLimitMB: 10 * 1024,
      theme: "dark"
    )
  }

  var isLoggedIn: Bool {
    !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static func configURL() throws -> URL {
    let root = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("SodaPlus", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("config.json")
  }

  static func cacheRoot() throws -> URL {
    let root = try FileManager.default.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent("SodaPlus", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let audio = root.appendingPathComponent("audio", isDirectory: true)
    try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
    return root
  }

  static func audioCacheDir() throws -> URL {
    try cacheRoot().appendingPathComponent("audio", isDirectory: true)
  }

  static func load() -> AppSettings {
    do {
      let url = try configURL()
      guard FileManager.default.fileExists(atPath: url.path) else {
        return .default
      }
      let data = try Data(contentsOf: url)
      var settings = try JSONDecoder().decode(AppSettings.self, from: data)
      if settings.signerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        settings.signerURL = defaultSignerURL
        settings.signerToken = defaultSignerToken
      }
      return settings
    } catch {
      print("[SodaPlus] load settings failed: \(error)")
      return .default
    }
  }

  func save() {
    do {
      let url = try Self.configURL()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(self).write(to: url, options: .atomic)
    } catch {
      print("[SodaPlus] save settings failed: \(error)")
    }
  }

  func bridgeEnvironment() -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["SODA_COOKIE"] = cookie
    env["QISHUI_SIGNER_URL"] = signerURL
    env["QISHUI_SIGNER_TOKEN"] = signerToken
    env["SODA_DEVICE_ID"] = deviceID
    env["SODA_IID"] = iid
    env["SODA_FP"] = fp
    env["SODAM_QUALITY"] = quality
    return env
  }

  var qualityCacheTag: String {
    let q = quality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty || q == "auto" || q == "best" { return "auto" }
    return q
  }
}
