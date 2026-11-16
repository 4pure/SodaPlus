import AVFoundation
import Combine
import Foundation
import MediaPlayer

@MainActor
final class PlayerController: ObservableObject {
  @Published private(set) var current: SodaTrack?
  @Published private(set) var isPlaying = false
  @Published private(set) var position: Double = 0
  @Published private(set) var duration: Double = 0
  @Published var volume: Float = 1 {
    didSet { player.volume = volume }
  }

  /// AVPlayer 是否已装载与 `current` 对应的 item（`present` 仅挂元数据时为 false）。
  private(set) var hasLoadedItem = false

  var onTrackEnded: (() -> Void)?
  var onRemotePlay: (() -> Void)?
  var onRemotePause: (() -> Void)?
  var onRemoteToggle: (() -> Void)?
  var onRemoteNext: (() -> Void)?
  var onRemotePrevious: (() -> Void)?

  private let player = AVPlayer()
  private var endObserver: NSObjectProtocol?
  private var timeObserver: Any?
  private var statusObservation: NSKeyValueObservation?

  /// 对齐 SodaM：元数据与播放态分开按变化发布，避免 macOS 整块替换 nowPlayingInfo。
  private var publishedTrackID: String?
  private var publishedPlaying: Bool?
  private var publishedElapsed: Double = -1
  private static let positionJumpSeconds: Double = 2.5

  init() {
    configureAudioSession()
    configureRemoteCommands()
    player.volume = volume

    endObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.isPlaying = false
        self?.publishPlayback(isPlaying: false)
        self?.onTrackEnded?()
      }
    }

    timeObserver = player.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
      queue: .main
    ) { [weak self] time in
      Task { @MainActor in
        guard let self else { return }
        let seconds = CMTimeGetSeconds(time)
        if seconds.isFinite {
          self.position = seconds
        }
        if let item = self.player.currentItem {
          let total = CMTimeGetSeconds(item.duration)
          if total.isFinite, total > 0 {
            self.duration = total
          }
        }
        self.publishElapsedIfNeeded()
      }
    }
  }

  deinit {
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    if let timeObserver {
      player.removeTimeObserver(timeObserver)
    }
  }

  /// 只挂 Now Playing 元数据（paused/playing），不要求 AVPlayer 已有 item。
  func present(track: SodaTrack, isPlaying playing: Bool) {
    if current?.id != track.id {
      // 换曲后旧 AVPlayerItem 不能再当「已装载」resume。
      hasLoadedItem = false
      position = 0
      duration = Double(track.durationMs) / 1000.0
    }
    current = track
    isPlaying = playing
    publishMetadata(for: track)
    publishPlayback(isPlaying: playing)
  }

  func play(fileURL: URL, track: SodaTrack) {
    statusObservation?.invalidate()
    current = track
    hasLoadedItem = true
    let item = AVPlayerItem(url: fileURL)
    player.replaceCurrentItem(with: item)
    duration = Double(track.durationMs) / 1000.0
    position = 0
    player.play()
    isPlaying = true
    publishMetadata(for: track)
    publishPlayback(isPlaying: true, forceElapsed: true)

    statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      Task { @MainActor in
        guard let self else { return }
        if item.status == .readyToPlay {
          let total = CMTimeGetSeconds(item.duration)
          if total.isFinite, total > 0 {
            self.duration = total
            self.patchNowPlayingDuration(total)
          }
        } else if item.status == .failed {
          print("[SodaPlus] AVPlayerItem failed: \(String(describing: item.error))")
          self.isPlaying = false
          self.hasLoadedItem = false
          self.publishPlayback(isPlaying: false)
        }
      }
    }
  }

  func pause() {
    if hasLoadedItem {
      player.pause()
    }
    isPlaying = false
    publishPlayback(isPlaying: false)
  }

  func resume() {
    guard current != nil, hasLoadedItem else { return }
    player.play()
    isPlaying = true
    publishPlayback(isPlaying: true)
  }

  func stop() {
    player.pause()
    player.replaceCurrentItem(with: nil)
    isPlaying = false
    hasLoadedItem = false
    current = nil
    position = 0
    duration = 0
    clearNowPlaying()
  }

  func seek(to seconds: Double) {
    let clamped = max(0, seconds)
    if hasLoadedItem {
      let time = CMTime(seconds: clamped, preferredTimescale: 600)
      player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    position = clamped
    publishElapsedIfNeeded(force: true)
  }

  private func configureAudioSession() {
    #if os(macOS)
      // AVAudioSession is iOS-only; macOS uses system default output.
    #else
      do {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
      } catch {
        print("[SodaPlus] audio session error: \(error)")
      }
    #endif
  }

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onRemotePlay?() }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onRemotePause?() }
      return .success
    }
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onRemoteToggle?() }
      return .success
    }
    center.nextTrackCommand.isEnabled = true
    center.nextTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onRemoteNext?() }
      return .success
    }
    center.previousTrackCommand.isEnabled = true
    center.previousTrackCommand.addTarget { [weak self] _ in
      Task { @MainActor in self?.onRemotePrevious?() }
      return .success
    }
    center.changePlaybackPositionCommand.isEnabled = true
    center.changePlaybackPositionCommand.addTarget { [weak self] event in
      guard let event = event as? MPChangePlaybackPositionCommandEvent else {
        return .commandFailed
      }
      Task { @MainActor in self?.seek(to: event.positionTime) }
      return .success
    }
  }

  private func publishMetadata(for track: SodaTrack) {
    if publishedTrackID == track.id { return }
    publishedTrackID = track.id
    publishedPlaying = nil
    publishedElapsed = -1

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: track.title,
      MPMediaItemPropertyArtist: track.artist,
      MPMediaItemPropertyAlbumTitle: track.album,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
    ]
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    } else if track.durationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = Double(track.durationMs) / 1000.0
    }

    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = info
    center.playbackState = isPlaying ? .playing : .paused
  }

  private func publishPlayback(isPlaying playing: Bool, forceElapsed: Bool = false) {
    guard current != nil else {
      clearNowPlaying()
      return
    }
    if publishedPlaying == playing, !forceElapsed { return }
    publishedPlaying = playing

    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    center.nowPlayingInfo = info
    center.playbackState = playing ? .playing : .paused
    publishedElapsed = position
  }

  private func publishElapsedIfNeeded(force: Bool = false) {
    guard current != nil else { return }
    if !force, abs(position - publishedElapsed) < Self.positionJumpSeconds {
      return
    }
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [:]
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position
    info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
    if duration > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = duration
    }
    center.nowPlayingInfo = info
    publishedElapsed = position
  }

  private func patchNowPlayingDuration(_ total: Double) {
    let center = MPNowPlayingInfoCenter.default()
    var info = center.nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyPlaybackDuration] = total
    center.nowPlayingInfo = info
  }

  private func clearNowPlaying() {
    publishedTrackID = nil
    publishedPlaying = nil
    publishedElapsed = -1
    let center = MPNowPlayingInfoCenter.default()
    center.nowPlayingInfo = nil
    center.playbackState = .stopped
  }
}
