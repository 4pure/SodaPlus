import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  @Published var settings: AppSettings
  @Published var nav: NavDestination = .settings
  @Published var settingsCategory: SettingsCategory = .playback
  @Published var account = AccountInfo.empty
  /// 窗口顶部短时提示（登录引导、失败、账号状态等；播放/设置变更/加载成功不刷）。
  @Published private(set) var message = ""
  @Published var isBusy = false
  /// 用户点播且本地未缓存时的缓冲态（底栏播放钮转圈）。
  @Published private(set) var isBuffering = false
  @Published var showQueue = false
  @Published var loginModalOpen = false
  private var messageSeq: UInt64 = 0

  @Published var homeTracks: [SodaTrack] = []
  /// 推荐装载失败终态（对齐 SodaM）：有值时 Home 显示重试，不再空转。
  @Published var homeError: String?
  /// 当前队列是否来自推荐流（点「推荐」时已在流上则只打开播放页）。
  @Published private(set) var queueIsRecommendation = false
  @Published var scenes: [SceneItem] = []
  @Published var searchQuery = ""
  @Published var searchTracks: [SodaTrack] = []
  @Published var likedTracks: [SodaTrack] = []
  @Published var douyinLikedTracks: [SodaTrack] = []
  @Published var historyTracks: [SodaTrack] = []
  @Published var playlists: [PlaylistItem] = []
  @Published var playlistDetail: PlaylistItem?
  @Published var playlistTracks: [SodaTrack] = []
  @Published var lyricLines: [LyricLine] = []
  @Published var likedIDs: Set<String> = []

  /// 侧栏「创建的歌单」：排除系统喜欢 / 抖音收藏。
  var createdPlaylists: [PlaylistItem] {
    playlists.filter { !$0.isSystemPlaylist }
  }

  @Published var openArtist: ArtistDetailPage?
  @Published var openAlbum: AlbumDetailPage?
  @Published var detailLoading = false
  @Published var detailError = ""

  @Published var qrScanURL = ""
  @Published var qrToken = ""
  @Published var qrMessage = ""
  @Published var qrNSImage: NSImage?
  /// 二次验证：本机 security_host 地址；非空时登录弹层切到内嵌 WebView。
  @Published var qrVerifyURL = ""
  @Published var cookieDraft = ""
  @Published var signerURLDraft = ""
  @Published var signerTokenDraft = ""
  @Published private(set) var audioCacheBytes: UInt64 = 0
  @Published private(set) var audioCacheFileCount = 0
  @Published private(set) var launchAtLoginEnabled = false
  @Published private(set) var isMeasuringCache = false

  let queue = PlayQueue()
  let player = PlayerController()
  let theme = ThemeStore()
  private let bridge = BridgeClient()
  private var cancellables = Set<AnyCancellable>()

  private var recommendCounter: UInt32 = 0
  private var recommendDidFirstUse: UInt64 = UInt64(Date().timeIntervalSince1970)
  private var activeScene: SceneItem?
  private var qrPollTask: Task<Void, Never>?
  private var loadSeq: UInt64 = 0
  private var ambientSeq: UInt64 = 0
  private var prefetchTask: Task<Void, Never>?
  private static let prefetchAheadCount = 2
  /// 进程内歌词缓存，切回已拉过的曲目可立刻显示。
  private var lyricCache: [String: [LyricLine]] = [:]
  /// 同曲同音质进行中的下载，避免预载与点播重复拉流。
  private var inflightDownloads: [String: InFlightDownload] = [:]
  /// 进入艺人/专辑页之前的导航，用于返回。
  private var detailReturnNav: NavDestination = .home
  /// 展开歌曲详情前的导航，用于从播放栏再次点封面收起。
  private var nowPlayingReturnNav: NavDestination = .home

  init() {
    settings = AppSettings.load()
    cookieDraft = settings.cookie
    signerURLDraft = settings.signerURL
    signerTokenDraft = settings.signerToken
    queue.mode = settings.playMode
    player.volume = settings.volume
    theme.setMode(settings.appearanceMode)
    refreshLaunchAtLoginStatus()

    queue.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
    player.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)
    theme.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &cancellables)

    player.onTrackEnded = { [weak self] in
      self?.handleTrackEnded()
    }
    player.onRemotePlay = { [weak self] in
      self?.remotePlay()
    }
    player.onRemotePause = { [weak self] in
      self?.remotePause()
    }
    player.onRemoteToggle = { [weak self] in
      self?.togglePlayPause()
    }
    player.onRemoteNext = { [weak self] in
      self?.playNext(userInitiated: true)
    }
    player.onRemotePrevious = { [weak self] in
      self?.playPrevious()
    }

    refreshAudioCacheUsage()

    if settings.isLoggedIn {
      nav = .home
      let warmSettings = settings
      Task { await self.warmBridge(warmSettings) }
      Task { await bootstrapLoggedIn() }
    } else {
      nav = .settings
      setMessage("请先在设置中扫码登录或粘贴 Cookie")
    }
  }

  private func warmBridge(_ settings: AppSettings) async {
    do {
      try await bridge.warm(settings: settings)
    } catch {
      print("[SodaPlus] bridge warm failed: \(error)")
    }
  }

  /// 对齐 SodaM `toggle_play`：已装载则暂停/继续，否则从队列装载当前曲。
  func togglePlayPause() {
    if let loaded = player.current,
      player.hasLoadedItem,
      let queued = queue.current,
      loaded.id == queued.id
    {
      if player.isPlaying {
        player.pause()
        persistSession()
      } else {
        player.resume()
      }
      return
    }
    guard let track = queue.current else { return }
    Task { await loadAndPlay(track, autoplay: true) }
  }

  func remotePlay() {
    if player.isPlaying { return }
    togglePlayPause()
  }

  func remotePause() {
    guard player.isPlaying else { return }
    player.pause()
    persistSession()
  }

  var isLoggedIn: Bool { settings.isLoggedIn }

  /// 顶部 message：新文案顶掉旧的，5 秒后消失；切页清空。
  func setMessage(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    messageSeq &+= 1
    let seq = messageSeq
    message = trimmed
    guard !trimmed.isEmpty else { return }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      if seq == messageSeq {
        message = ""
      }
    }
  }

  func clearMessage() {
    messageSeq &+= 1
    message = ""
  }

  func selectNav(_ destination: NavDestination) {
    if !isLoggedIn, destination != .settings {
      nav = .settings
      setMessage("请先登录：点右上角头像")
      return
    }
    clearMessage()
    // App 内切页算失焦：关掉队列弹层；切到其它 macOS App 不关。
    showQueue = false
    if destination != .artist && destination != .album {
      openArtist = nil
      openAlbum = nil
      detailError = ""
    }
    if destination != .library {
      playlistDetail = nil
      playlistTracks = []
    }
    // 对齐 SodaM / 官方汽水：点「推荐」进播放页，而不是曲目表。
    if destination == .home {
      Task { await activateRecommendation() }
      return
    }
    nav = destination
    Task {
      switch destination {
      case .scenes:
        if scenes.isEmpty { await loadScenes() }
      case .liked:
        await loadLiked()
      case .douyinLiked:
        await loadDouyinLiked()
      case .history:
        await loadHistory()
      case .library:
        await loadPlaylists()
      case .search:
        break
      default:
        break
      }
    }
  }

  /// 对齐 SodaM `activate_recommendation`：已在推荐流则打开播放页，否则装载后进入。
  func activateRecommendation() async {
    guard isLoggedIn else {
      nav = .settings
      setMessage("请先登录：点右上角头像")
      return
    }
    if homeError != nil {
      await retryRecommendation()
      return
    }
    if queueIsRecommendation, !queue.tracks.isEmpty {
      nav = .nowPlaying
      return
    }
    if isBusy, homeTracks.isEmpty {
      nav = .home
      setMessage("推荐队列还在加载，稍等一下…")
      return
    }
    nav = .home
    await loadHome(reset: true, adoptQueue: true)
  }

  func retryRecommendation() async {
    homeError = nil
    nav = .home
    await loadHome(reset: true, adoptQueue: true)
  }

  func openNowPlaying() {
    guard !queue.tracks.isEmpty || player.current != nil else { return }
    if nav != .nowPlaying {
      nowPlayingReturnNav = nav
    }
    nav = .nowPlaying
  }

  /// 播放栏封面：展开 / 收起歌曲详情。
  func toggleNowPlaying() {
    if nav == .nowPlaying {
      let back = nowPlayingReturnNav == .nowPlaying ? .home : nowPlayingReturnNav
      nav = back
      return
    }
    openNowPlaying()
  }

  func backFromDetail() {
    openArtist = nil
    openAlbum = nil
    detailError = ""
    detailLoading = false
    nav =
      detailReturnNav == .artist || detailReturnNav == .album
      ? .home
      : detailReturnNav
  }

  func openArtistPage(id: String, nameHint: String = "") {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      setMessage("该曲目没有音乐人 ID")
      return
    }
    if nav != .artist && nav != .album {
      detailReturnNav = nav
    }
    openAlbum = nil
    openArtist = nil
    detailError = ""
    nav = .artist
    Task { await loadArtist(id: id, nameHint: nameHint) }
  }

  func openAlbumPage(id: String, titleHint: String = "") {
    guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      setMessage("该曲目没有专辑 ID")
      return
    }
    if nav != .artist && nav != .album {
      detailReturnNav = nav
    }
    openArtist = nil
    openAlbum = nil
    detailError = ""
    nav = .album
    Task { await loadAlbum(id: id, titleHint: titleHint) }
  }

  func openArtistFromTrack(_ track: SodaTrack) {
    openArtistPage(id: track.artistId, nameHint: track.artist)
  }

  func openAlbumFromTrack(_ track: SodaTrack) {
    openAlbumPage(id: track.albumId, titleHint: track.album)
  }

  func bootstrapLoggedIn() async {
    // 先恢复上次队列：有缓存时可秒就绪；推荐流并行拉取，不抢占已恢复的播放队列。
    let restored = restoreSessionIfPossible()
    async let accountTask: Void = refreshAccount()
    async let homeTask: Void = loadHome(reset: true, adoptQueue: !restored)
    async let likedTask: Void = loadLikedIDs()
    _ = await (accountTask, homeTask, likedTask)
    // 对齐汽水：登录后落在播放页，而不是推荐曲目表。
    if queue.current != nil || player.current != nil {
      nav = .nowPlaying
    }
  }

  func refreshAccount() async {
    guard isLoggedIn else { return }
    do {
      account = try await bridge.me(settings: settings)
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] me failed: \(error)")
    }
  }

  func saveCookieFromDraft() {
    settings.cookie = cookieDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.save()
    stopQRPolling()
    if settings.isLoggedIn {
      nav = .home
      Task { await bootstrapLoggedIn() }
      setMessage("Cookie 已保存")
    }
  }

  func logout() {
    stopQRPolling()
    settings.cookie = ""
    cookieDraft = ""
    settings.save()
    account = .empty
    homeTracks = []
    homeError = nil
    queueIsRecommendation = false
    likedTracks = []
    douyinLikedTracks = []
    historyTracks = []
    playlists = []
    playlistDetail = nil
    playlistTracks = []
    searchTracks = []
    lyricLines = []
    likedIDs = []
    player.stop()
    queue.replace([])
    PlaybackSession.clear()
    isBuffering = false
    showQueue = false
    nav = .settings
    setMessage("已退出登录")
  }

  func openLoginModal() {
    loginModalOpen = true
    startQRLogin()
  }

  func closeLoginModal() {
    loginModalOpen = false
    qrVerifyURL = ""
    stopQRPolling()
  }

  func startQRLogin() {
    stopQRPolling()
    qrMessage = "正在创建二维码…"
    qrNSImage = nil
    qrScanURL = ""
    qrVerifyURL = ""
    Task {
      do {
        // 常驻 bridge serve：create/check 必须同进程，否则 CDP cookie jar 对不上（SodaM 同理）。
        let qr = try await bridge.qrCreate(settings: settings)
        guard !qr.scanURL.isEmpty else {
          qrMessage = "二维码地址为空，请重试或改用 Cookie"
          return
        }
        qrToken = qr.token
        qrScanURL = qr.scanURL
        qrNSImage = QRCodeImage.make(from: qr.scanURL)
        qrMessage = "请用汽水音乐 App 扫码并确认"
        startQRPolling()
      } catch {
        qrMessage = error.localizedDescription
        print("[SodaPlus] qr-create failed: \(error)")
      }
    }
  }

  private func startQRPolling() {
    let token = qrToken
    qrPollTask = Task {
      // 对齐 SodaM：6 秒一轮（3 秒会触发 error_code=7 限流，确认握手会被丢掉）
      var verifyOpened = false
      for _ in 0..<80 {
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        guard !Task.isCancelled else { return }
        do {
          let result = try await bridge.qrCheck(token: token, settings: settings)
          let statusText: String = {
            if !result.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              return result.message
            }
            switch result.status {
            case "waiting": return "等待扫码…"
            case "scanned": return "已扫码，请在手机上确认"
            case "success": return "登录成功"
            case "expired": return "二维码已过期"
            case "failed": return "登录失败"
            default: return result.status
            }
          }()
          await MainActor.run { qrMessage = statusText }

          if result.status == "success",
            !result.cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          {
            await MainActor.run {
              settings.cookie = result.cookie
              cookieDraft = result.cookie
              settings.save()
              stopQRPolling()
              qrMessage = "登录成功"
              qrNSImage = nil
              qrVerifyURL = ""
              loginModalOpen = false
              nav = .home
              setMessage("登录成功，正在读取账号信息…")
            }
            await bootstrapLoggedIn()
            return
          }

          if result.needSecondVerify, !verifyOpened {
            verifyOpened = true
            do {
              let url = try await bridge.qrOpenVerify(token: token, settings: settings)
              await MainActor.run {
                if URL(string: url) != nil {
                  qrVerifyURL = url
                  qrMessage = "请在下方完成二次验证"
                } else {
                  qrMessage = "二次验证地址无效，请改用 Cookie 登录"
                }
              }
            } catch {
              await MainActor.run {
                qrMessage = "需要二次验证但打开失败，请改用 Cookie 登录"
              }
              print("[SodaPlus] second verify failed: \(error)")
            }
          }

          if result.rateLimited {
            try? await Task.sleep(nanoseconds: 9_000_000_000)
          }

          if result.status == "expired" || result.status == "failed" {
            await MainActor.run {
              qrMessage =
                result.status == "expired"
                ? "二维码已过期，正在自动换新码…"
                : "登录失败，正在重试…"
            }
            await MainActor.run { startQRLogin() }
            return
          }
        } catch {
          // 单次失败不中断（对齐 SodaM）
          await MainActor.run { qrMessage = "轮询异常，继续等待…" }
          print("[SodaPlus] qr-check failed: \(error)")
        }
      }
      await MainActor.run {
        qrMessage = "登录超时，请重新获取二维码"
        stopQRPolling()
      }
    }
  }

  func stopQRPolling() {
    qrPollTask?.cancel()
    qrPollTask = nil
  }

  func updateVolume(_ value: Float) {
    if value > 0.01 {
      settings.volumeBeforeMute = value
    }
    player.volume = value
    settings.volume = value
    settings.save()
  }

  func toggleMute() {
    if player.volume < 0.01 {
      let restore = settings.volumeBeforeMute > 0.01 ? settings.volumeBeforeMute : 1
      updateVolume(restore)
    } else {
      settings.volumeBeforeMute = player.volume
      updateVolume(0)
    }
  }

  func cyclePlayMode() {
    queue.mode = queue.mode.next()
    settings.playMode = queue.mode
    settings.save()
  }

  func setQuality(_ quality: String) {
    setQuality(QualityPreference.from(stored: quality))
  }

  func setQuality(_ preference: QualityPreference) {
    settings.quality = preference.rawValue
    settings.save()
  }

  func setCloseWindowAction(_ action: CloseWindowAction) {
    guard settings.closeWindowAction != action else { return }
    settings.closeWindowAction = action
    settings.save()
  }

  func setAppearanceMode(_ mode: AppearanceMode) {
    guard settings.appearanceMode != mode else { return }
    settings.appearanceMode = mode
    theme.setMode(mode)
    settings.save()
  }

  func setAudioCacheLimitMB(_ limitMB: UInt64) {
    let clamped = min(max(limitMB, 1024), 1024 * 1024)
    guard settings.audioCacheLimitMB != clamped else { return }
    settings.audioCacheLimitMB = clamped
    settings.save()
    pruneAudioCacheIfNeeded()
    refreshAudioCacheUsage()
  }

  func saveSignerFromDraft() {
    let url = signerURLDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    let token = signerTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    settings.signerURL = url.isEmpty ? AppSettings.defaultSignerURL : url
    settings.signerToken = token.isEmpty ? AppSettings.defaultSignerToken : token
    signerURLDraft = settings.signerURL
    signerTokenDraft = settings.signerToken
    settings.save()
  }

  func resetSignerToDefault() {
    settings.signerURL = AppSettings.defaultSignerURL
    settings.signerToken = AppSettings.defaultSignerToken
    signerURLDraft = settings.signerURL
    signerTokenDraft = settings.signerToken
    settings.save()
  }

  func refreshLaunchAtLoginStatus() {
    launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      refreshLaunchAtLoginStatus()
    } catch {
      refreshLaunchAtLoginStatus()
      setMessage("开机自启设置失败：\(error.localizedDescription)")
      print("[SodaPlus] launch at login failed: \(error)")
    }
  }

  func openConfigFile() {
    do {
      let url = try AppSettings.configURL()
      if !FileManager.default.fileExists(atPath: url.path) {
        settings.save()
      }
      NSWorkspace.shared.activateFileViewerSelecting([url])
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] open config failed: \(error)")
    }
  }

  func openAudioCacheFolder() {
    do {
      let dir = try AppSettings.audioCacheDir()
      NSWorkspace.shared.open(dir)
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] open cache folder failed: \(error)")
    }
  }

  var appVersionLabel: String {
    let short =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "0.1.0"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    if let build, !build.isEmpty, build != short {
      return "SodaPlus \(short) (\(build))"
    }
    return "SodaPlus \(short)"
  }

  func refreshAudioCacheUsage() {
    isMeasuringCache = true
    Task {
      let summary = await Self.measureAudioCache()
      audioCacheBytes = summary.bytes
      audioCacheFileCount = summary.files
      isMeasuringCache = false
    }
  }

  func clearAudioCache() {
    do {
      let dir = try AppSettings.audioCacheDir()
      let files = try FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil
      )
      let playingPath = player.current.flatMap { try? cacheURL(for: $0).path }
      for file in files {
        if let playingPath, file.path == playingPath { continue }
        try? FileManager.default.removeItem(at: file)
      }
      refreshAudioCacheUsage()
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] clear cache failed: \(error)")
    }
  }

  static func humanBytes(_ bytes: UInt64) -> String {
    let value = Double(bytes)
    let kb = 1024.0
    if value >= kb * kb * kb {
      return String(format: "%.2f GB", value / (kb * kb * kb))
    }
    if value >= kb * kb {
      return String(format: "%.1f MB", value / (kb * kb))
    }
    if value >= kb {
      return String(format: "%.0f KB", value / kb)
    }
    return "\(bytes) B"
  }

  private static func measureAudioCache() async -> (bytes: UInt64, files: Int) {
    await Task.detached(priority: .utility) {
      do {
        let dir = try AppSettings.audioCacheDir()
        let files = try FileManager.default.contentsOfDirectory(
          at: dir,
          includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
          options: [.skipsHiddenFiles]
        )
        var total: UInt64 = 0
        var count = 0
        for file in files {
          let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
          guard values.isRegularFile == true else { continue }
          total += UInt64(values.fileSize ?? 0)
          count += 1
        }
        return (total, count)
      } catch {
        print("[SodaPlus] measure cache failed: \(error)")
        return (0, 0)
      }
    }.value
  }

  /// 超出上限时按最近使用时间淘汰（跳过正在播放的文件）。
  private func pruneAudioCacheIfNeeded() {
    let limit = settings.audioCacheLimitBytes
    guard limit > 0 else { return }
    let playingPath = player.current.flatMap { try? cacheURL(for: $0).path }
    Task.detached(priority: .utility) {
      do {
        let dir = try AppSettings.audioCacheDir()
        let files = try FileManager.default.contentsOfDirectory(
          at: dir,
          includingPropertiesForKeys: [
            .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isRegularFileKey,
          ],
          options: [.skipsHiddenFiles]
        )
        struct Entry {
          let url: URL
          let size: UInt64
          let accessed: Date
        }
        var entries: [Entry] = []
        var total: UInt64 = 0
        for file in files {
          let values = try file.resourceValues(forKeys: [
            .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isRegularFileKey,
          ])
          guard values.isRegularFile == true else { continue }
          if let playingPath, file.path == playingPath { continue }
          let size = UInt64(values.fileSize ?? 0)
          let accessed =
            values.contentAccessDate
            ?? values.contentModificationDate
            ?? .distantPast
          entries.append(Entry(url: file, size: size, accessed: accessed))
          total += size
        }
        guard total > limit else { return }
        entries.sort { $0.accessed < $1.accessed }
        for entry in entries {
          guard total > limit else { break }
          try? FileManager.default.removeItem(at: entry.url)
          total -= entry.size
        }
      } catch {
        print("[SodaPlus] prune cache failed: \(error)")
      }
      await self.refreshAudioCacheUsage()
    }
  }

  func loadHome(reset: Bool, adoptQueue: Bool = true) async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    if reset {
      recommendCounter = 0
      recommendDidFirstUse = UInt64(Date().timeIntervalSince1970)
      activeScene = nil
      homeError = nil
    }
    do {
      let page = try await bridge.recommend(
        settings: settings,
        fetchCounter: recommendCounter,
        didFirstUseTime: recommendDidFirstUse,
        scene: activeScene
      )
      recommendCounter = page.fetchCounter
      recommendDidFirstUse = page.didFirstUseTime
      homeError = nil
      if reset {
        homeTracks = page.tracks
        if adoptQueue, let first = page.tracks.first {
          queue.replace(page.tracks, start: 0)
          queueIsRecommendation = true
          persistSession(position: 0)
          // 立刻挂 Now Playing，系统控可在下载完成前响应 Play。
          player.present(track: first, isPlaying: false)
          Task { await loadAndPlay(first, autoplay: true) }
          nav = .nowPlaying
        } else if page.tracks.isEmpty {
          homeError = "推荐队列是空的，稍后再试"
          nav = .home
        } else if !queue.tracks.isEmpty {
          // 保留已恢复的播放队列，仍进入播放页。
          nav = .nowPlaying
        }
      } else {
        homeTracks.append(contentsOf: page.tracks)
        _ = queue.append(page.tracks)
        persistSession()
        schedulePrefetch()
      }
    } catch {
      let message = error.localizedDescription
      homeError = message
      setMessage(message)
      nav = .home
      print("[SodaPlus] recommend failed: \(error)")
    }
  }

  func loadScenes() async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      scenes = try await bridge.scenes(settings: settings)
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] scenes failed: \(error)")
    }
  }

  func playScene(_ scene: SceneItem) async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    activeScene = scene
    recommendCounter = 0
    recommendDidFirstUse = UInt64(Date().timeIntervalSince1970)
    do {
      let page = try await bridge.recommend(
        settings: settings,
        fetchCounter: recommendCounter,
        didFirstUseTime: recommendDidFirstUse,
        scene: scene
      )
      recommendCounter = page.fetchCounter
      homeTracks = page.tracks
      queue.replace(page.tracks, start: 0)
      queueIsRecommendation = true
      persistSession(position: 0)
      nav = .nowPlaying
      if let first = page.tracks.first {
        await loadAndPlay(first, autoplay: true)
      }
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] scene play failed: \(error)")
    }
  }

  func search() async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      searchTracks = try await bridge.search(query: searchQuery, settings: settings)
    } catch {
      searchTracks = []
      setMessage(error.localizedDescription)
      print("[SodaPlus] search failed: \(error)")
    }
  }

  func loadLiked() async {
    guard isLoggedIn else { return }
    // 列表拉取不抢全局 isBusy，避免与下载串行时把整页锁死。
    do {
      likedTracks = try await bridge.liked(settings: settings)
      likedIDs = Set(likedTracks.map(\.id))
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] liked failed: \(error)")
    }
  }

  func loadDouyinLiked() async {
    guard isLoggedIn else { return }
    do {
      douyinLikedTracks = try await bridge.douyinLiked(settings: settings)
    } catch {
      douyinLikedTracks = []
      setMessage(error.localizedDescription)
      print("[SodaPlus] douyin liked failed: \(error)")
    }
  }

  func loadHistory() async {
    guard isLoggedIn else { return }
    do {
      historyTracks = try await bridge.recent(settings: settings)
    } catch {
      historyTracks = []
      setMessage(error.localizedDescription)
      print("[SodaPlus] history failed: \(error)")
    }
  }

  func loadLikedIDs() async {
    do {
      let tracks = try await bridge.liked(settings: settings)
      likedIDs = Set(tracks.map(\.id))
    } catch {
      print("[SodaPlus] liked ids failed: \(error)")
    }
  }

  func loadPlaylists() async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      playlists = try await bridge.myPlaylists(settings: settings)
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] playlists failed: \(error)")
    }
  }

  func createPlaylist(name: String) async {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isLoggedIn, !trimmed.isEmpty else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      let created = try await bridge.createPlaylist(name: trimmed, settings: settings)
      await loadPlaylists()
      await openPlaylist(created)
      setMessage("已创建歌单「\(trimmed)」")
    } catch {
      setMessage(error.localizedDescription)
      print("[SodaPlus] create playlist failed: \(error)")
    }
  }

  func openPlaylist(_ item: PlaylistItem) async {
    isBusy = true
    defer { isBusy = false }
    clearMessage()
    showQueue = false
    nav = .library
    playlistDetail = item
    do {
      playlistTracks = try await bridge.playlistTracks(id: item.id, settings: settings)
    } catch {
      playlistTracks = []
      setMessage(error.localizedDescription)
      print("[SodaPlus] playlist failed: \(error)")
    }
  }

  /// 歌单/列表「播放全部」：从第一首起整表入队；留在当前页，不进歌曲详情。
  func playAll(_ tracks: [SodaTrack]) {
    guard !tracks.isEmpty else { return }
    guard let start = tracks.firstIndex(where: \.playable) else {
      setMessage("该列表暂无可播放歌曲")
      return
    }
    playTrack(tracks[start], asQueue: tracks)
  }

  func playTrack(_ track: SodaTrack, asQueue source: [SodaTrack]? = nil) {
    if let source, !source.isEmpty {
      let start = source.firstIndex(where: { $0.id == track.id }) ?? 0
      queue.replace(source, start: start)
      // 从推荐列表点播仍算推荐流；其它来源（搜索/歌单等）清掉标记。
      queueIsRecommendation =
        !homeTracks.isEmpty
        && source.count == homeTracks.count
        && zip(source, homeTracks).allSatisfy { $0.id == $1.id }
    } else if queue.tracks.contains(where: { $0.id == track.id }) {
      if let idx = queue.tracks.firstIndex(where: { $0.id == track.id }) {
        queue.jump(to: idx)
      }
    } else {
      queue.replace([track], start: 0)
      queueIsRecommendation = false
    }

    if !track.playable {
      setMessage("该歌曲暂不可播放")
      // 点灰歌：保留队列位置，尝试从当前起播下一首可播。
      if let nextIdx = queue.firstPlayableIndex(from: queue.index),
        queue.tracks.indices.contains(nextIdx),
        queue.tracks[nextIdx].id != track.id
      {
        queue.jump(to: nextIdx)
        persistSession(position: 0)
        Task { await loadAndPlay(queue.tracks[nextIdx], autoplay: true) }
      }
      return
    }

    persistSession(position: 0)
    Task { await loadAndPlay(track, autoplay: true) }
  }

  func playNextInQueue(_ track: SodaTrack) {
    guard track.playable else {
      setMessage("该歌曲暂不可播放")
      return
    }
    queue.insertNext(track)
  }

  func toggleLike(_ track: SodaTrack) {
    let willLike = !likedIDs.contains(track.id)
    Task {
      do {
        try await bridge.setLiked(trackID: track.id, liked: willLike, settings: settings)
        if willLike {
          likedIDs.insert(track.id)
        } else {
          likedIDs.remove(track.id)
        }
      } catch {
        setMessage(error.localizedDescription)
        print("[SodaPlus] like failed: \(error)")
      }
    }
  }

  func playNext(userInitiated: Bool) {
    guard let track = queue.advancePlayable(userInitiated: userInitiated) else {
      if userInitiated { setMessage("暂无可播放的下一首") }
      return
    }
    persistSession(position: 0)
    Task { await loadAndPlay(track, autoplay: true) }
    if homeTracks.count - queue.index < 5,
      activeScene != nil || queueIsRecommendation || nav == .home || nav == .nowPlaying
    {
      Task { await loadHome(reset: false) }
    }
  }

  func playPrevious() {
    guard let track = queue.previousPlayable() else {
      setMessage("暂无可播放的上一首")
      return
    }
    persistSession(position: 0)
    Task { await loadAndPlay(track, autoplay: true) }
  }

  private func handleTrackEnded() {
    if queue.mode == .repeatOne, let current = queue.current, current.playable {
      Task { await loadAndPlay(current, autoplay: true) }
    } else {
      playNext(userInitiated: false)
    }
  }

  private func loadAndPlay(_ track: SodaTrack, autoplay: Bool, seekTo: Double? = nil) async {
    if !track.playable {
      if autoplay {
        setMessage("该歌曲暂不可播放")
        playNext(userInitiated: false)
      }
      return
    }

    loadSeq += 1
    let seq = loadSeq
    player.present(track: track, isPlaying: false)
    updateAmbient(for: track)
    // 歌词与音频并行：先清旧词 / 命中缓存，再后台拉，不堵开播。
    applyLyricsForPlay(track: track, seq: seq)

    let cached = isCached(track)
    let showBuffering = autoplay && !cached
    if showBuffering {
      isBuffering = true
    } else if seq == loadSeq {
      if isBuffering { isBuffering = false }
    }

    do {
      let fileURL = try await cachedOrDownload(track)
      guard seq == loadSeq else { return }
      player.play(fileURL: fileURL, track: track)
      if let seekTo, seekTo > 1 {
        player.seek(to: seekTo)
      }
      if !autoplay {
        player.pause()
      }
      isBuffering = false
      persistSession(position: seekTo ?? (autoplay ? 0 : player.position))
      schedulePrefetch()
    } catch {
      guard seq == loadSeq else { return }
      isBuffering = false
      if Self.isTrackUnavailable(error) {
        queue.markUnplayable(id: track.id)
        markTrackUnplayableInLists(id: track.id)
        if autoplay {
          setMessage("该歌曲暂不可播放")
          playNext(userInitiated: false)
        } else {
          setMessage("该歌曲暂不可播放")
        }
        print("[SodaPlus] play unavailable: \(error)")
        return
      }
      if autoplay {
        setMessage(error.localizedDescription)
      }
      print("[SodaPlus] play failed: \(error)")
    }
  }

  /// 汽水侧下架 / 无资源：SEO 未知、资源不存在等。
  private static func isTrackUnavailable(_ error: Error) -> Bool {
    let text = error.localizedDescription
    return text.contains("SEO页面歌曲未知")
      || text.contains("1000091")
      || text.contains("ERR_RESOURCE_NOT_FOUND")
      || text.contains("1000005")
      || text.contains("soda seo_track missing track id")
  }

  private func markTrackUnplayableInLists(id: String) {
    func mark(_ tracks: inout [SodaTrack]) {
      if let i = tracks.firstIndex(where: { $0.id == id }) {
        tracks[i].playable = false
      }
    }
    mark(&douyinLikedTracks)
    mark(&likedTracks)
    mark(&historyTracks)
    mark(&playlistTracks)
    mark(&homeTracks)
    mark(&searchTracks)
  }

  private func cacheURL(for track: SodaTrack) throws -> URL {
    let dir = try AppSettings.audioCacheDir()
    return dir.appendingPathComponent("\(track.id)-\(settings.qualityCacheTag).m4a")
  }

  private func downloadKey(for track: SodaTrack) -> String {
    "\(track.id)-\(settings.qualityCacheTag)"
  }

  private func isCached(_ track: SodaTrack) -> Bool {
    (try? cacheURL(for: track)).map {
      FileManager.default.fileExists(atPath: $0.path)
    } ?? false
  }

  private func cachedOrDownload(_ track: SodaTrack) async throws -> URL {
    let fileURL = try cacheURL(for: track)
    if FileManager.default.fileExists(atPath: fileURL.path) {
      return fileURL
    }
    let key = downloadKey(for: track)
    if let existing = inflightDownloads[key] {
      return try await existing.task.value
    }
    let settings = self.settings
    let task = Task {
      try await bridge.download(trackID: track.id, to: fileURL, settings: settings)
      return fileURL
    }
    let box = InFlightDownload(task: task)
    inflightDownloads[key] = box
    do {
      let url = try await task.value
      if inflightDownloads[key] === box {
        inflightDownloads.removeValue(forKey: key)
      }
      pruneAudioCacheIfNeeded()
      return url
    } catch {
      if inflightDownloads[key] === box {
        inflightDownloads.removeValue(forKey: key)
      }
      throw error
    }
  }

  /// 后台预取队列后续曲目（bridge 串行，逐首排队），切歌尽量走本地缓存。
  private func schedulePrefetch() {
    prefetchTask?.cancel()
    let ahead = Array(queue.upcoming.prefix(Self.prefetchAheadCount))
      .filter { $0.playable && !isCached($0) }
    guard !ahead.isEmpty else { return }
    prefetchTask = Task {
      for track in ahead {
        if Task.isCancelled { return }
        do {
          _ = try await cachedOrDownload(track)
        } catch {
          print("[SodaPlus] prefetch failed \(track.id): \(error)")
        }
      }
    }
  }

  /// 恢复上次队列；当前曲有缓存则静默装载就绪。
  @discardableResult
  private func restoreSessionIfPossible() -> Bool {
    guard let session = PlaybackSession.load(), !session.tracks.isEmpty else {
      return false
    }
    let index = min(max(0, session.index), session.tracks.count - 1)
    queue.replace(session.tracks, start: index)
    guard let track = queue.current else { return false }
    player.present(track: track, isPlaying: false)
    let seekTo = max(0, session.position)
    Task { await loadAndPlay(track, autoplay: false, seekTo: seekTo) }
    return true
  }

  private func persistSession(position: Double? = nil) {
    guard !queue.tracks.isEmpty else {
      PlaybackSession.clear()
      return
    }
    PlaybackSession(
      tracks: queue.tracks,
      index: queue.index,
      position: position ?? player.position,
      qualityTag: settings.qualityCacheTag
    ).save()
  }

  private func applyLyricsForPlay(track: SodaTrack, seq: UInt64) {
    if let cached = lyricCache[track.id] {
      lyricLines = cached
      return
    }
    lyricLines = []
    Task { await loadLyrics(for: track, seq: seq) }
  }

  private func loadLyrics(for track: SodaTrack, seq: UInt64) async {
    do {
      let raw = try await bridge.lyrics(trackID: track.id, settings: settings)
      let parsed = LyricParser.parse(raw)
      lyricCache[track.id] = parsed
      guard seq == loadSeq else { return }
      lyricLines = parsed
    } catch {
      guard seq == loadSeq else { return }
      lyricLines = []
      print("[SodaPlus] lyrics failed: \(error)")
    }
  }

  private func updateAmbient(for track: SodaTrack) {
    ambientSeq += 1
    let seq = ambientSeq
    guard let url = track.coverURL else {
      theme.setAmbient(nil)
      return
    }
    Task {
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard seq == ambientSeq else { return }
        guard let image = NSImage(data: data),
          let rgb = AmbientColor.dominant(from: image)
        else {
          await MainActor.run {
            guard seq == self.ambientSeq else { return }
            self.theme.setAmbient(nil)
          }
          return
        }
        await MainActor.run {
          guard seq == self.ambientSeq else { return }
          self.theme.setAmbient(rgb)
        }
      } catch {
        await MainActor.run {
          guard seq == self.ambientSeq else { return }
          self.theme.setAmbient(nil)
        }
        print("[SodaPlus] ambient failed: \(error)")
      }
    }
  }

  private func loadArtist(id: String, nameHint: String) async {
    detailLoading = true
    detailError = ""
    defer { detailLoading = false }
    do {
      openArtist = try await bridge.artist(id: id, settings: settings)
    } catch {
      detailError = error.localizedDescription
      setMessage(error.localizedDescription)
      print("[SodaPlus] artist failed: \(error)")
    }
  }

  private func loadAlbum(id: String, titleHint: String) async {
    detailLoading = true
    detailError = ""
    defer { detailLoading = false }
    do {
      openAlbum = try await bridge.album(id: id, settings: settings)
    } catch {
      detailError = error.localizedDescription
      setMessage(error.localizedDescription)
      print("[SodaPlus] album failed: \(error)")
    }
  }

}

/// 用引用相等区分同 key 的新旧下载任务，避免失败清理误删后一次。
private final class InFlightDownload {
  let task: Task<URL, Error>
  init(task: Task<URL, Error>) {
    self.task = task
  }
}
