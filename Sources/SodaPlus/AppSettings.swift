import Foundation

/// 红 X 关闭主窗口后的行为（对齐汽水「关闭主面板」：托盘继续 / 退出）。
enum CloseWindowAction: String, Codable, CaseIterable, Identifiable, Hashable {
  case continueInBackground
  case quit

  var id: String { rawValue }

  var title: String {
    switch self {
    case .continueInBackground: return "最小化到菜单栏"
    case .quit: return "退出程序"
    }
  }

  var subtitle: String {
    switch self {
    case .continueInBackground: return "隐藏 Dock，菜单栏可继续控制播放"
    case .quit: return "关闭主窗口即完全退出"
    }
  }
}

/// 音质意图，对齐 libresoda / SodaM 档位表（存 `config.json` 的 `quality` 字符串）。
enum QualityPreference: String, CaseIterable, Identifiable, Hashable {
  case auto
  case hires
  case lossless
  case dolby
  case highest
  case medium
  case low

  var id: String { rawValue }

  var title: String {
    switch self {
    case .auto: return "自动"
    case .hires: return "Hi-Res"
    case .lossless: return "无损音质"
    case .dolby: return "杜比全景声"
    case .highest: return "极高音质"
    case .medium: return "较高音质"
    case .low: return "流畅"
    }
  }

  var hint: String {
    switch self {
    case .auto: return "不设上限，按账号权益和单曲可用档位取最高"
    case .hires: return "优先 Hi-Res 无损；没有可用档位时由服务端回退"
    case .lossless: return "优先无损；没有可用无损时由服务端回退"
    case .dolby: return "优先杜比全景声；没有可用档位时由服务端回退"
    case .highest: return "优先极高（≈320k）；没有可用档位时由服务端回退"
    case .medium: return "优先较高；没有可用档位时由服务端回退"
    case .low: return "优先流畅（≈128k）；没有可用档位时由服务端回退"
    }
  }

  static func from(stored: String) -> QualityPreference {
    let q = stored.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if q.isEmpty || q == "best" { return .auto }
    return QualityPreference(rawValue: q) ?? .auto
  }
}

/// 设置页左侧分类（对齐汽水音乐设置侧栏）。
enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
  case playback
  case shortcuts
  case usage
  case account
  case advanced
  case about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .playback: return "播放相关"
    case .shortcuts: return "快捷键"
    case .usage: return "使用相关"
    case .account: return "账户"
    case .advanced: return "高级"
    case .about: return "关于"
    }
  }
}

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
  var closeWindowAction: CloseWindowAction

  enum CodingKeys: String, CodingKey {
    case cookie, quality, volume, theme
    case signerURL = "signer_url"
    case signerToken = "signer_token"
    case deviceID = "device_id"
    case iid, fp
    case volumeBeforeMute = "volume_before_mute"
    case playMode = "play_mode"
    case audioCacheLimitMB = "audio_cache_limit_mb"
    case closeWindowAction = "close_window_action"
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
      theme: "dark",
      closeWindowAction: .continueInBackground
    )
  }

  init(
    signerURL: String,
    signerToken: String,
    cookie: String,
    deviceID: String,
    iid: String,
    fp: String,
    quality: String,
    volume: Float,
    volumeBeforeMute: Float,
    playMode: PlayMode,
    audioCacheLimitMB: UInt64,
    theme: String,
    closeWindowAction: CloseWindowAction
  ) {
    self.signerURL = signerURL
    self.signerToken = signerToken
    self.cookie = cookie
    self.deviceID = deviceID
    self.iid = iid
    self.fp = fp
    self.quality = quality
    self.volume = volume
    self.volumeBeforeMute = volumeBeforeMute
    self.playMode = playMode
    self.audioCacheLimitMB = audioCacheLimitMB
    self.theme = theme
    self.closeWindowAction = closeWindowAction
  }

  init(from decoder: Decoder) throws {
    let defaults = AppSettings.default
    let c = try decoder.container(keyedBy: CodingKeys.self)
    signerURL = try c.decodeIfPresent(String.self, forKey: .signerURL) ?? defaults.signerURL
    signerToken = try c.decodeIfPresent(String.self, forKey: .signerToken) ?? defaults.signerToken
    cookie = try c.decodeIfPresent(String.self, forKey: .cookie) ?? defaults.cookie
    deviceID = try c.decodeIfPresent(String.self, forKey: .deviceID) ?? defaults.deviceID
    iid = try c.decodeIfPresent(String.self, forKey: .iid) ?? defaults.iid
    fp = try c.decodeIfPresent(String.self, forKey: .fp) ?? defaults.fp
    quality = try c.decodeIfPresent(String.self, forKey: .quality) ?? defaults.quality
    volume = try c.decodeIfPresent(Float.self, forKey: .volume) ?? defaults.volume
    volumeBeforeMute =
      try c.decodeIfPresent(Float.self, forKey: .volumeBeforeMute) ?? defaults.volumeBeforeMute
    playMode = try c.decodeIfPresent(PlayMode.self, forKey: .playMode) ?? defaults.playMode
    audioCacheLimitMB =
      try c.decodeIfPresent(UInt64.self, forKey: .audioCacheLimitMB) ?? defaults.audioCacheLimitMB
    theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? defaults.theme
    closeWindowAction =
      try c.decodeIfPresent(CloseWindowAction.self, forKey: .closeWindowAction)
      ?? defaults.closeWindowAction
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(signerURL, forKey: .signerURL)
    try c.encode(signerToken, forKey: .signerToken)
    try c.encode(cookie, forKey: .cookie)
    try c.encode(deviceID, forKey: .deviceID)
    try c.encode(iid, forKey: .iid)
    try c.encode(fp, forKey: .fp)
    try c.encode(quality, forKey: .quality)
    try c.encode(volume, forKey: .volume)
    try c.encode(volumeBeforeMute, forKey: .volumeBeforeMute)
    try c.encode(playMode, forKey: .playMode)
    try c.encode(audioCacheLimitMB, forKey: .audioCacheLimitMB)
    try c.encode(theme, forKey: .theme)
    try c.encode(closeWindowAction, forKey: .closeWindowAction)
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

  var qualityPreference: QualityPreference {
    QualityPreference.from(stored: quality)
  }

  var appearanceMode: AppearanceMode {
    get { AppearanceMode.from(stored: theme) }
    set { theme = newValue.rawValue }
  }

  var qualityCacheTag: String {
    let q = qualityPreference
    return q == .auto ? "auto" : q.rawValue
  }

  var audioCacheLimitBytes: UInt64 {
    audioCacheLimitMB * 1024 * 1024
  }
}
