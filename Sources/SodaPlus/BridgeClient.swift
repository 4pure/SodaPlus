import Foundation

/// 常驻 `sodaplus-bridge serve`：扫码登录必须同进程保活 CDP（对齐 SodaM / libresoda）。
actor BridgeClient {
  private let bridgeURL: URL
  private var process: Process?
  private var stdinHandle: FileHandle?
  private var readerTask: Task<Void, Never>?
  private var nextID: UInt64 = 1
  private var pending: [UInt64: CheckedContinuation<Data, Error>] = [:]
  private var lineBuffer = Data()
  private var lastConfigFingerprint = ""

  init(bridgeURL: URL? = nil) {
    if let bridgeURL {
      self.bridgeURL = bridgeURL
    } else {
      self.bridgeURL = Self.defaultBridgeURL()
    }
  }

  private static func defaultBridgeURL() -> URL {
    let env = ProcessInfo.processInfo.environment["SODAPLUS_BRIDGE"]
    if let env, !env.isEmpty {
      return URL(fileURLWithPath: env)
    }
    let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    var candidates: [URL] = [
      Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/sodaplus-bridge"),
      cwd.appendingPathComponent("bridge/target/release/sodaplus-bridge"),
      cwd.appendingPathComponent("bridge/target/debug/sodaplus-bridge"),
    ]
    if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
      candidates.insert(exeDir.appendingPathComponent("sodaplus-bridge"), at: 0)
    }
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
      ?? cwd.appendingPathComponent("bridge/target/debug/sodaplus-bridge")
  }

  /// 启动预热：拉起 `serve` 并推送 configure，避免首次业务 API 才付冷启动。
  func warm(settings: AppSettings) async throws {
    try await ensureDaemon()
    try await syncConfigIfNeeded(settings)
  }

  func me(settings: AppSettings) async throws -> AccountInfo {
    try decode(AccountInfo.self, from: await call(cmd: "me", settings: settings))
  }

  func recommend(
    settings: AppSettings,
    fetchCounter: UInt32,
    didFirstUseTime: UInt64,
    scene: SceneItem?
  ) async throws -> RecommendPage {
    var extra: [String: Any] = [
      "fetch_counter": fetchCounter,
      "did_first_use_time": didFirstUseTime,
    ]
    if let scene {
      extra["scene_mode_id"] = scene.sceneModeId
      extra["preference_mode"] = scene.subQueueType
    }
    return try decode(
      RecommendPage.self,
      from: await call(cmd: "recommend", settings: settings, extra: extra)
    )
  }

  func scenes(settings: AppSettings) async throws -> [SceneItem] {
    struct Envelope: Codable { var scenes: [SceneItem] }
    return try decode(Envelope.self, from: await call(cmd: "scenes", settings: settings)).scenes
  }

  func search(query: String, settings: AppSettings) async throws -> [SodaTrack] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw SodaPlusError.emptyQuery }
    struct Envelope: Codable { var tracks: [SodaTrack] }
    return try decode(
      Envelope.self,
      from: await call(cmd: "search", settings: settings, extra: ["query": trimmed])
    ).tracks
  }

  func liked(settings: AppSettings) async throws -> [SodaTrack] {
    struct Envelope: Codable { var tracks: [SodaTrack] }
    return try decode(Envelope.self, from: await call(cmd: "liked", settings: settings)).tracks
  }

  func myPlaylists(settings: AppSettings) async throws -> [PlaylistItem] {
    struct Envelope: Codable { var playlists: [PlaylistItem] }
    return try decode(
      Envelope.self,
      from: await call(cmd: "my-playlists", settings: settings)
    ).playlists
  }

  func playlistTracks(id: String, settings: AppSettings) async throws -> [SodaTrack] {
    struct Envelope: Codable { var tracks: [SodaTrack] }
    return try decode(
      Envelope.self,
      from: await call(cmd: "playlist", settings: settings, extra: ["id_arg": id])
    ).tracks
  }

  /// 优先返回增强 LRC 原文（含逐字时间轴），否则回退到扁平 lrc。
  func lyrics(trackID: String, settings: AppSettings) async throws -> String {
    struct Envelope: Codable {
      var raw: String?
      var lrc: String?
    }
    let env = try decode(
      Envelope.self,
      from: await call(cmd: "lyrics", settings: settings, extra: ["id_arg": trackID])
    )
    if let raw = env.raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
      return raw
    }
    return env.lrc ?? ""
  }

  func artist(id: String, settings: AppSettings) async throws -> ArtistDetailPage {
    try decode(
      ArtistDetailPage.self,
      from: await call(cmd: "artist", settings: settings, extra: ["id_arg": id])
    )
  }

  func album(id: String, settings: AppSettings) async throws -> AlbumDetailPage {
    try decode(
      AlbumDetailPage.self,
      from: await call(cmd: "album", settings: settings, extra: ["id_arg": id])
    )
  }

  func download(trackID: String, to destination: URL, settings: AppSettings) async throws {
    _ = try await call(
      cmd: "download",
      settings: settings,
      extra: ["id_arg": trackID, "out": destination.path]
    )
  }

  func setLiked(trackID: String, liked: Bool, settings: AppSettings) async throws {
    _ = try await call(
      cmd: liked ? "collect" : "uncollect",
      settings: settings,
      extra: ["id_arg": trackID, "liked": liked]
    )
  }

  func qrCreate(settings: AppSettings) async throws -> (
    token: String, scanURL: String, qrImage: String
  ) {
    struct Envelope: Codable {
      var token: String
      var scanURL: String
      var qrImage: String
      enum CodingKeys: String, CodingKey {
        case token
        case scanURL = "scan_url"
        case qrImage = "qr_image"
      }
    }
    let env = try decode(Envelope.self, from: await call(cmd: "qr-create", settings: settings))
    return (env.token, env.scanURL, env.qrImage)
  }

  func qrCheck(token: String, settings: AppSettings) async throws -> QRCheckResult {
    try decode(
      QRCheckResult.self,
      from: await call(cmd: "qr-check", settings: settings, extra: ["token": token])
    )
  }

  func qrOpenVerify(token: String, settings: AppSettings) async throws -> String {
    struct Envelope: Codable { var url: String }
    return try decode(
      Envelope.self,
      from: await call(cmd: "qr-open-verify", settings: settings, extra: ["token": token])
    ).url
  }

  private func call(
    cmd: String,
    settings: AppSettings,
    extra: [String: Any] = [:]
  ) async throws -> Data {
    try await ensureDaemon()
    try await syncConfigIfNeeded(settings)

    let id = nextID
    nextID += 1

    var payload: [String: Any] = [
      "id": id,
      "cmd": cmd,
    ]
    for (key, value) in extra {
      payload[key] = value
    }

    let body = try JSONSerialization.data(withJSONObject: payload)
    guard var line = String(data: body, encoding: .utf8) else {
      throw SodaPlusError.decoding("request encode failed")
    }
    line.append("\n")
    guard let stdinHandle, let data = line.data(using: .utf8) else {
      throw SodaPlusError.bridgeMissing
    }

    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      do {
        try stdinHandle.write(contentsOf: data)
      } catch {
        pending.removeValue(forKey: id)
        continuation.resume(throwing: error)
      }
    }
  }

  private func ensureDaemon() async throws {
    if let process, process.isRunning {
      return
    }
    guard FileManager.default.isExecutableFile(atPath: bridgeURL.path) else {
      throw SodaPlusError.bridgeMissing
    }

    // 清掉上次异常退出留下的 headless Chrome，避免占住 Dock。
    Self.killOrphanCdpChrome()

    let process = Process()
    process.executableURL = bridgeURL
    process.arguments = ["serve"]
    process.environment = ProcessInfo.processInfo.environment
    process.terminationHandler = { _ in
      Self.killOrphanCdpChrome()
    }

    let stdin = Pipe()
    let stdout = Pipe()
    let stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()

    self.process = process
    self.stdinHandle = stdin.fileHandleForWriting
    self.lastConfigFingerprint = ""

    let outHandle = stdout.fileHandleForReading
    outHandle.readabilityHandler = { [weak self] handle in
      let chunk = handle.availableData
      guard !chunk.isEmpty else {
        Task { await self?.handleStdoutEOF() }
        return
      }
      Task { await self?.consumeStdout(chunk) }
    }
    readerTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 500_000_000)
        guard let self else { return }
        if await self.process?.isRunning != true {
          await self.handleStdoutEOF()
          return
        }
      }
    }
  }

  private func handleStdoutEOF() {
    stdinHandle = nil
    process = nil
    Self.killOrphanCdpChrome()
    failAllPending(
      SodaPlusError.bridge("bridge_exited", hint: "sodaplus-bridge serve 已退出；将自动重启")
    )
  }

  /// 结束仍挂着的 libresoda CDP / 独立 helper，避免占住系统 Chrome。
  private static func killOrphanCdpChrome() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    task.arguments = ["-f", "libresoda-cdp-|/LibresodaCDP.app/"]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      print("[SodaPlus] kill orphan CDP chrome failed: \(error)")
    }
  }

  private func syncConfigIfNeeded(_ settings: AppSettings) async throws {
    let fingerprint = [
      settings.cookie,
      settings.signerURL,
      settings.signerToken,
      settings.deviceID,
      settings.iid,
      settings.fp,
      settings.quality,
    ].joined(separator: "\u{1e}")
    guard fingerprint != lastConfigFingerprint else { return }

    let id = nextID
    nextID += 1
    let payload: [String: Any] = [
      "id": id,
      "cmd": "configure",
      "config": [
        "cookie": settings.cookie,
        "signer_url": settings.signerURL,
        "signer_token": settings.signerToken,
        "device_id": settings.deviceID,
        "iid": settings.iid,
        "fp": settings.fp,
        "quality": settings.quality,
      ],
    ]
    let body = try JSONSerialization.data(withJSONObject: payload)
    guard let line = String(data: body, encoding: .utf8),
      let data = line.appending("\n").data(using: .utf8),
      let stdinHandle
    else {
      throw SodaPlusError.bridgeMissing
    }
    _ = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Data, Error>) in
      pending[id] = continuation
      do {
        try stdinHandle.write(contentsOf: data)
      } catch {
        pending.removeValue(forKey: id)
        continuation.resume(throwing: error)
      }
    }
    lastConfigFingerprint = fingerprint
  }

  private func consumeStdout(_ chunk: Data) {
    lineBuffer.append(chunk)
    while let range = lineBuffer.range(of: Data([0x0A])) {
      let line = lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound)
      lineBuffer.removeSubrange(lineBuffer.startIndex...range.lowerBound)
      handleResponseLine(line)
    }
  }

  private func handleResponseLine(_ line: Data) {
    guard !line.isEmpty else { return }
    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
      let idValue = obj["id"],
      let id = (idValue as? UInt64) ?? (idValue as? Int).map(UInt64.init)
    else {
      print("[SodaPlus] bridge bad response: \(String(data: line, encoding: .utf8) ?? "binary")")
      return
    }
    guard let continuation = pending.removeValue(forKey: id) else { return }

    if let ok = obj["ok"] as? Bool, !ok {
      let error = obj["error"] as? String ?? "bridge_error"
      let hint = obj["hint"] as? String ?? ""
      continuation.resume(throwing: SodaPlusError.bridge(error, hint: hint))
      return
    }
    if obj["error"] != nil, obj["ok"] == nil {
      let error = obj["error"] as? String ?? "bridge_error"
      let hint = obj["hint"] as? String ?? ""
      continuation.resume(throwing: SodaPlusError.bridge(error, hint: hint))
      return
    }
    continuation.resume(returning: line)
  }

  private func failAllPending(_ error: Error) {
    let items = pending
    pending.removeAll()
    for (_, continuation) in items {
      continuation.resume(throwing: error)
    }
  }

  private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw SodaPlusError.decoding(String(data: data, encoding: .utf8) ?? "binary")
    }
  }
}

struct QRCheckResult: Codable {
  var status: String
  var message: String
  var cookie: String
  var needSecondVerify: Bool
  var rateLimited: Bool

  enum CodingKeys: String, CodingKey {
    case status, message, cookie
    case needSecondVerify = "need_second_verify"
    case rateLimited = "rate_limited"
  }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
    message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
    cookie = try c.decodeIfPresent(String.self, forKey: .cookie) ?? ""
    needSecondVerify = try c.decodeIfPresent(Bool.self, forKey: .needSecondVerify) ?? false
    rateLimited = try c.decodeIfPresent(Bool.self, forKey: .rateLimited) ?? false
  }
}
