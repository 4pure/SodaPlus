import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
  @Published var settings: AppSettings
  @Published var nav: NavDestination = .settings
  @Published var account = AccountInfo.empty
  @Published private(set) var statusLine = ""
  @Published var isBusy = false
  @Published var showQueue = false
  @Published var loginModalOpen = false
  private var statusSeq: UInt64 = 0

  @Published var homeTracks: [SodaTrack] = []
  @Published var scenes: [SceneItem] = []
  @Published var searchQuery = ""
  @Published var searchTracks: [SodaTrack] = []
  @Published var likedTracks: [SodaTrack] = []
  @Published var playlists: [PlaylistItem] = []
  @Published var playlistDetail: PlaylistItem?
  @Published var playlistTracks: [SodaTrack] = []
  @Published var lyricLines: [LyricLine] = []
  @Published var likedIDs: Set<String> = []

  @Published var openArtist: ArtistDetailPage?
  @Published var openAlbum: AlbumDetailPage?
  @Published var detailLoading = false
  @Published var detailError = ""

  @Published var qrScanURL = ""
  @Published var qrToken = ""
  @Published var qrMessage = ""
  @Published var qrNSImage: NSImage?
  @Published var cookieDraft = ""

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
  /// 进入艺人/专辑页之前的导航，用于返回。
  private var detailReturnNav: NavDestination = .home

  init() {
    settings = AppSettings.load()
    cookieDraft = settings.cookie
    queue.mode = settings.playMode
    player.volume = settings.volume

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

    if settings.isLoggedIn {
      nav = .home
      let warmSettings = settings
      Task { await self.warmBridge(warmSettings) }
      Task { await bootstrapLoggedIn() }
    } else {
      nav = .settings
      setStatus("请先在设置中扫码登录或粘贴 Cookie")
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
        setStatus("已暂停")
      } else {
        player.resume()
        setStatus("播放中")
      }
      return
    }
    guard let track = queue.current else {
      setStatus("队列是空的：先去搜索或打开一张歌单")
      return
    }
    Task { await loadAndPlay(track, autoplay: true) }
  }

  func remotePlay() {
    if player.isPlaying { return }
    togglePlayPause()
  }

  func remotePause() {
    guard player.isPlaying else { return }
    player.pause()
    setStatus("已暂停")
  }

  var isLoggedIn: Bool { settings.isLoggedIn }

  /// 对齐 SodaM 状态行：新文案顶掉旧的，5 秒后消失；切页清空。
  func setStatus(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    statusSeq &+= 1
    let seq = statusSeq
    statusLine = trimmed
    guard !trimmed.isEmpty else { return }
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 5_000_000_000)
      if seq == statusSeq {
        statusLine = ""
      }
    }
  }

  func clearStatus() {
    statusSeq &+= 1
    statusLine = ""
  }

  func selectNav(_ destination: NavDestination) {
    if !isLoggedIn, destination != .settings {
      nav = .settings
      setStatus("请先在「设置」登录")
      return
    }
    clearStatus()
    if destination != .artist && destination != .album {
      openArtist = nil
      openAlbum = nil
      detailError = ""
    }
    nav = destination
    Task {
      switch destination {
      case .home:
        if homeTracks.isEmpty { await loadHome(reset: true) }
      case .scenes:
        if scenes.isEmpty { await loadScenes() }
      case .liked:
        await loadLiked()
      case .library:
        await loadPlaylists()
      default:
        break
      }
    }
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
      setStatus("该曲目没有音乐人 ID")
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
      setStatus("该曲目没有专辑 ID")
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
    await refreshAccount()
    await loadHome(reset: true)
    await loadLikedIDs()
  }

  func refreshAccount() async {
    guard isLoggedIn else { return }
    do {
      account = try await bridge.me(settings: settings)
      setStatus(account.vip ? "已登录 · VIP \(account.nickname)" : "已登录 · \(account.nickname)")
    } catch {
      setStatus(error.localizedDescription)
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
      setStatus("Cookie 已保存")
    }
  }

  func logout() {
    stopQRPolling()
    settings.cookie = ""
    cookieDraft = ""
    settings.save()
    account = .empty
    homeTracks = []
    likedTracks = []
    playlists = []
    searchTracks = []
    lyricLines = []
    likedIDs = []
    player.stop()
    queue.replace([])
    nav = .settings
    setStatus("已退出登录")
  }

  func openLoginModal() {
    loginModalOpen = true
    startQRLogin()
  }

  func closeLoginModal() {
    loginModalOpen = false
    stopQRPolling()
  }

  func startQRLogin() {
    stopQRPolling()
    qrMessage = "正在创建二维码…"
    qrNSImage = nil
    qrScanURL = ""
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
              loginModalOpen = false
              nav = .home
              setStatus("登录成功，正在读取账号信息…")
            }
            await bootstrapLoggedIn()
            return
          }

          if result.needSecondVerify, !verifyOpened {
            verifyOpened = true
            do {
              let url = try await bridge.qrOpenVerify(token: token, settings: settings)
              await MainActor.run {
                qrMessage = "已打开二次验证窗口，请完成验证"
                if let page = URL(string: url) {
                  NSWorkspace.shared.open(page)
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
    setStatus(queue.mode.label)
  }

  func setQuality(_ quality: String) {
    settings.quality = quality
    settings.save()
    let label: String = {
      switch quality {
      case "auto": return "自动"
      case "hires": return "Hi-Res"
      case "lossless": return "无损"
      case "highest": return "极高"
      case "medium": return "标准"
      case "low": return "较低"
      default: return quality
      }
    }()
    setStatus("音质已设为 \(label)，从下一首生效")
  }

  func clearAudioCache() {
    do {
      let dir = try AppSettings.audioCacheDir()
      let files = try FileManager.default.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: nil
      )
      for file in files {
        try? FileManager.default.removeItem(at: file)
      }
      setStatus("已清空音频缓存")
    } catch {
      setStatus(error.localizedDescription)
      print("[SodaPlus] clear cache failed: \(error)")
    }
  }

  func loadHome(reset: Bool) async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    if reset {
      recommendCounter = 0
      recommendDidFirstUse = UInt64(Date().timeIntervalSince1970)
      activeScene = nil
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
      if reset {
        homeTracks = page.tracks
        if let first = page.tracks.first {
          queue.replace(page.tracks, start: 0)
          // 立刻挂 Now Playing，系统控可在下载完成前响应 Play。
          player.present(track: first, isPlaying: false)
          Task { await loadAndPlay(first, autoplay: false) }
        }
      } else {
        homeTracks.append(contentsOf: page.tracks)
        _ = queue.append(page.tracks)
        schedulePrefetch()
      }
      setStatus("推荐 \(homeTracks.count) 首")
    } catch {
      setStatus(error.localizedDescription)
      print("[SodaPlus] recommend failed: \(error)")
    }
  }

  func loadScenes() async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      scenes = try await bridge.scenes(settings: settings)
      setStatus("听歌模式 \(scenes.count) 个")
    } catch {
      setStatus(error.localizedDescription)
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
      nav = .home
      setStatus("已切换：\(scene.text)")
      if let first = page.tracks.first {
        await loadAndPlay(first, autoplay: true)
      }
    } catch {
      setStatus(error.localizedDescription)
      print("[SodaPlus] scene play failed: \(error)")
    }
  }

  func search() async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      searchTracks = try await bridge.search(query: searchQuery, settings: settings)
      setStatus(searchTracks.isEmpty ? "无结果" : "找到 \(searchTracks.count) 首")
    } catch {
      searchTracks = []
      setStatus(error.localizedDescription)
      print("[SodaPlus] search failed: \(error)")
    }
  }

  func loadLiked() async {
    guard isLoggedIn else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      likedTracks = try await bridge.liked(settings: settings)
      likedIDs = Set(likedTracks.map(\.id))
      setStatus("我喜欢 \(likedTracks.count) 首")
    } catch {
      setStatus(error.localizedDescription)
      print("[SodaPlus] liked failed: \(error)")
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
      setStatus("歌单 \(playlists.count) 个")
    } catch {
      setStatus(error.localizedDescription)
      print("[SodaPlus] playlists failed: \(error)")
    }
  }

  func openPlaylist(_ item: PlaylistItem) async {
    isBusy = true
    defer { isBusy = false }
    playlistDetail = item
    do {
      playlistTracks = try await bridge.playlistTracks(id: item.id, settings: settings)
      setStatus("\(item.title) · \(playlistTracks.count) 首")
    } catch {
      playlistTracks = []
      setStatus(error.localizedDescription)
      print("[SodaPlus] playlist failed: \(error)")
    }
  }

  func playTrack(_ track: SodaTrack, asQueue source: [SodaTrack]? = nil) {
    if let source, !source.isEmpty {
      let start = source.firstIndex(where: { $0.id == track.id }) ?? 0
      queue.replace(source, start: start)
    } else if queue.tracks.contains(where: { $0.id == track.id }) {
      if let idx = queue.tracks.firstIndex(where: { $0.id == track.id }) {
        queue.jump(to: idx)
      }
    } else {
      queue.replace([track], start: 0)
    }
    Task { await loadAndPlay(track, autoplay: true) }
  }

  func playNextInQueue(_ track: SodaTrack) {
    queue.insertNext(track)
    setStatus("已加入下一首：\(track.title)")
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
        setStatus(willLike ? "已喜欢 \(track.title)" : "已取消喜欢")
      } catch {
        setStatus(error.localizedDescription)
        print("[SodaPlus] like failed: \(error)")
      }
    }
  }

  func playNext(userInitiated: Bool) {
    let track = userInitiated ? queue.nextUser() : queue.advance()
    guard let track else { return }
    Task { await loadAndPlay(track, autoplay: true) }
    if homeTracks.count - queue.index < 5, activeScene != nil || nav == .home {
      Task { await loadHome(reset: false) }
    }
  }

  func playPrevious() {
    guard let track = queue.previous() else { return }
    Task { await loadAndPlay(track, autoplay: true) }
  }

  private func handleTrackEnded() {
    if queue.mode == .repeatOne, let current = queue.current {
      Task { await loadAndPlay(current, autoplay: true) }
    } else {
      playNext(userInitiated: false)
    }
  }

  private func loadAndPlay(_ track: SodaTrack, autoplay: Bool) async {
    loadSeq += 1
    let seq = loadSeq
    player.present(track: track, isPlaying: false)
    setStatus("装载 \(track.title)…")
    updateAmbient(for: track)
    do {
      let fileURL = try await cachedOrDownload(track)
      guard seq == loadSeq else { return }
      player.play(fileURL: fileURL, track: track)
      if !autoplay {
        player.pause()
      }
      setStatus(autoplay ? "正在播放 \(track.title)" : "已就绪 \(track.title)")
      schedulePrefetch()
      await loadLyrics(for: track, seq: seq)
    } catch {
      guard seq == loadSeq else { return }
      setStatus(error.localizedDescription)
      print("[SodaPlus] play failed: \(error)")
    }
  }

  private func cacheURL(for track: SodaTrack) throws -> URL {
    let dir = try AppSettings.audioCacheDir()
    return dir.appendingPathComponent("\(track.id)-\(settings.qualityCacheTag).m4a")
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
    try await bridge.download(trackID: track.id, to: fileURL, settings: settings)
    return fileURL
  }

  /// 后台预取队列后续曲目（并发 1），切歌尽量走本地缓存。
  private func schedulePrefetch() {
    prefetchTask?.cancel()
    let ahead = Array(queue.upcoming.prefix(Self.prefetchAheadCount))
      .filter { !isCached($0) }
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

  private func loadLyrics(for track: SodaTrack, seq: UInt64) async {
    do {
      let raw = try await bridge.lyrics(trackID: track.id, settings: settings)
      guard seq == loadSeq else { return }
      lyricLines = LyricParser.parse(raw)
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
      setStatus("音乐人 · \(openArtist?.artist.name ?? nameHint)")
    } catch {
      detailError = error.localizedDescription
      setStatus(error.localizedDescription)
      print("[SodaPlus] artist failed: \(error)")
    }
  }

  private func loadAlbum(id: String, titleHint: String) async {
    detailLoading = true
    detailError = ""
    defer { detailLoading = false }
    do {
      openAlbum = try await bridge.album(id: id, settings: settings)
      setStatus("专辑 · \(openAlbum?.album.title ?? titleHint)")
    } catch {
      detailError = error.localizedDescription
      setStatus(error.localizedDescription)
      print("[SodaPlus] album failed: \(error)")
    }
  }

}
