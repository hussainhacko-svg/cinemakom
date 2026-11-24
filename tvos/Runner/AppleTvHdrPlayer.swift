import AVFoundation
import AVKit
import CoreMedia
import Flutter
import UIKit

/// Native Apple TV (tvOS) HDR video player host for Cinemakom.
///
/// Renders directly through an `AVPlayerLayer` embedded via `FlutterPlatformView`
/// with **no** `AVPlayerItemVideoOutput` attached — keeping the hardware
/// 10-bit/12-bit VideoToolbox → CoreMedia → HDMI pipeline intact for HDR10, HLG,
/// and Dolby Vision while Flutter composites subtitles and controls above it.
///
/// Also drives `UIWindow.avDisplayManager.preferredDisplayCriteria` from the
/// active `AVAsset` so Apple TV's Match Dynamic Range (HDR10/HLG/Dolby Vision)
/// and Match Frame Rate settings engage automatically during playback and reset
/// cleanly to SDR when leaving the player.
final class AppleTvHdrPlayerPlugin: NSObject {
  static let methodChannelName = "io.github.sharon_xa.cinemakom/apple_tv_player"
  static let eventChannelPrefix = "io.github.sharon_xa.cinemakom/apple_tv_player/events/"
  static let viewType = "io.github.sharon_xa.cinemakom/apple_tv_player_view"

  private let messenger: FlutterBinaryMessenger
  private var nextPlayerId: Int64 = 1
  private var sessions: [Int64: AppleTvHdrPlayerSession] = [:]

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  @discardableResult
  static func register(with registrar: FlutterPluginRegistrar) -> AppleTvHdrPlayerPlugin {
    let messenger = registrar.messenger()
    let plugin = AppleTvHdrPlayerPlugin(messenger: messenger)

    let channel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak plugin] call, result in
      DispatchQueue.main.async {
        plugin?.handle(call, result: result)
      }
    }

    let factory = AppleTvHdrPlayerViewFactory(sessionProvider: { [weak plugin] playerId in
      plugin?.sessions[playerId]
    })
    registrar.register(factory, withId: viewType)

    return plugin
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]

    switch call.method {
    case "create":
      configureAudioSession()
      let playerId = nextPlayerId
      nextPlayerId += 1
      let session = AppleTvHdrPlayerSession(
        playerId: playerId,
        messenger: messenger,
        hasOtherActiveSessions: { [weak self] id in
          guard let self else { return false }
          return self.sessions.keys.contains { $0 != id }
        }
      )
      sessions[playerId] = session
      result(playerId)

    case "open":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId],
            let uri = args?["uri"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "Missing playerId or uri", details: nil))
        return
      }
      let headers = args?["headers"] as? [String: String] ?? [:]
      let startMs = int64Arg(args, "startMs") ?? 0
      let play = (args?["play"] as? Bool) ?? true
      let rate = (args?["rate"] as? NSNumber)?.doubleValue ?? 1.0
      let volume = (args?["volume"] as? NSNumber)?.doubleValue ?? 100.0
      let fit = (args?["fit"] as? String) ?? "contain"
      session.open(
        uri: uri,
        headers: headers,
        startMs: startMs,
        play: play,
        rate: rate,
        volume: volume,
        fit: fit
      )
      result(nil)

    case "play":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId]
      else {
        result(nil)
        return
      }
      session.play()
      result(nil)

    case "pause":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId]
      else {
        result(nil)
        return
      }
      session.pause()
      result(nil)

    case "seek":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId],
            let positionMs = int64Arg(args, "positionMs")
      else {
        result(nil)
        return
      }
      session.seek(toMs: positionMs) {
        result(nil)
      }

    case "setRate":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId],
            let rate = (args?["rate"] as? NSNumber)?.doubleValue
      else {
        result(nil)
        return
      }
      session.setRate(rate)
      result(nil)

    case "setVolume":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId],
            let volume = (args?["volume"] as? NSNumber)?.doubleValue
      else {
        result(nil)
        return
      }
      session.setVolume(volume)
      result(nil)

    case "setFit":
      guard let playerId = int64Arg(args, "playerId"),
            let session = sessions[playerId],
            let fit = args?["fit"] as? String
      else {
        result(nil)
        return
      }
      session.setFit(fit)
      result(nil)

    case "dispose":
      if let playerId = int64Arg(args, "playerId"),
         let session = sessions.removeValue(forKey: playerId) {
        session.dispose()
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func configureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .moviePlayback, options: [])
      try audioSession.setActive(true)
    } catch {
      NSLog("[AppleTvHdrPlayer] AVAudioSession setup failed: %@", error.localizedDescription)
    }
  }

  private func int64Arg(_ args: [String: Any]?, _ key: String) -> Int64? {
    (args?[key] as? NSNumber)?.int64Value
  }
}

// MARK: - Platform View Factory & View

private final class AppleTvHdrPlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  private let sessionProvider: (Int64) -> AppleTvHdrPlayerSession?

  init(sessionProvider: @escaping (Int64) -> AppleTvHdrPlayerSession?) {
    self.sessionProvider = sessionProvider
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let dict = args as? [String: Any]
    let playerId = (dict?["playerId"] as? NSNumber)?.int64Value
    let fit = dict?["fit"] as? String
    let session = playerId.flatMap { sessionProvider($0) }
    return AppleTvHdrPlatformView(frame: frame, session: session, initialFit: fit)
  }
}

private final class AppleTvPlayerLayerView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  var onWindowChanged: (() -> Void)?

  override var canBecomeFocused: Bool { false }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    isUserInteractionEnabled = false
    playerLayer.videoGravity = .resizeAspect
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onWindowChanged?()
  }
}

private final class AppleTvHdrPlatformView: NSObject, FlutterPlatformView {
  private let layerView: AppleTvPlayerLayerView

  init(frame: CGRect, session: AppleTvHdrPlayerSession?, initialFit: String?) {
    layerView = AppleTvPlayerLayerView(frame: frame)
    super.init()
    if let initialFit {
      layerView.playerLayer.videoGravity = AppleTvHdrPlayerSession.videoGravity(for: initialFit)
    }
    session?.attach(view: layerView)
  }

  func view() -> UIView {
    layerView
  }
}

// MARK: - Player Session

private final class AppleTvHdrPlayerSession: NSObject, FlutterStreamHandler {
  let playerId: Int64
  let player: AVPlayer

  private let eventChannel: FlutterEventChannel
  private let hasOtherActiveSessions: (Int64) -> Bool

  private weak var attachedView: AppleTvPlayerLayerView?
  private var eventSink: FlutterEventSink?
  private var pendingEvents: [[String: Any]] = []

  private var playerObservations: [NSKeyValueObservation] = []
  private var itemObservations: [NSKeyValueObservation] = []
  private var itemNotificationTokens: [NSObjectProtocol] = []
  private var timeObserverToken: Any?
  private var criteriaTask: Task<Void, Never>?

  private var openGeneration: Int = 0
  private var currentDisplayCriteria: AVDisplayCriteria?
  private var currentGravity: AVLayerVideoGravity = .resizeAspect

  private var wantsToPlay: Bool = false
  private var targetRate: Float = 1.0
  private var pendingStartMs: Int64 = 0
  private var itemReady: Bool = false
  private var disposed: Bool = false

  private var lastEmittedPositionMs: Int64?
  private var lastEmittedDurationMs: Int64?
  private var lastEmittedBufferedMs: Int64?
  private var lastEmittedPlaying: Bool?
  private var lastEmittedBuffering: Bool?
  private var lastEmittedWidth: Double?
  private var lastEmittedHeight: Double?

  init(
    playerId: Int64,
    messenger: FlutterBinaryMessenger,
    hasOtherActiveSessions: @escaping (Int64) -> Bool
  ) {
    self.playerId = playerId
    self.hasOtherActiveSessions = hasOtherActiveSessions
    self.player = AVPlayer()
    self.player.actionAtItemEnd = .pause
    self.player.preventsDisplaySleepDuringVideoPlayback = true
    self.eventChannel = FlutterEventChannel(
      name: "\(AppleTvHdrPlayerPlugin.eventChannelPrefix)\(playerId)",
      binaryMessenger: messenger
    )
    super.init()

    eventChannel.setStreamHandler(self)
    observePlayer()
  }

  func attach(view: AppleTvPlayerLayerView) {
    attachedView = view
    view.playerLayer.player = player
    view.playerLayer.videoGravity = currentGravity
    view.onWindowChanged = { [weak self] in
      self?.syncDisplayCriteria()
    }
    syncDisplayCriteria()
  }

  func open(
    uri: String,
    headers: [String: String],
    startMs: Int64,
    play: Bool,
    rate: Double,
    volume: Double,
    fit: String
  ) {
    guard !disposed else { return }

    openGeneration += 1
    let generation = openGeneration
    clearItemObservers()
    criteriaTask?.cancel()

    itemReady = false
    wantsToPlay = play
    targetRate = Float(max(rate, 0.01))
    pendingStartMs = max(startMs, 0)
    lastEmittedPositionMs = nil
    lastEmittedDurationMs = nil
    lastEmittedBufferedMs = nil
    lastEmittedPlaying = nil
    lastEmittedBuffering = nil
    lastEmittedWidth = nil
    lastEmittedHeight = nil

    setFit(fit)
    setVolume(volume)

    emit(["type": "completed", "value": false])
    emitPlaying(false)
    emitBuffering(true)

    guard let url = URL(string: uri) else {
      emitError("Failed to load video: Invalid URI")
      return
    }

    let assetOptions: [String: Any]? =
      headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
    let asset = AVURLAsset(url: url, options: assetOptions)
    // Intentionally do NOT add an AVPlayerItemVideoOutput: keeping outputs empty
    // preserves VideoToolbox's direct 10-bit/12-bit HDR10, HLG, and Dolby Vision
    // path to AVPlayerLayer on Apple TV.
    let item = AVPlayerItem(asset: asset)

    observeItem(item, generation: generation)
    player.replaceCurrentItem(with: item)
    loadDisplayCriteriaAndHdrInfo(for: asset, generation: generation)
  }

  func play() {
    guard !disposed else { return }
    wantsToPlay = true
    applyPlaybackState()
  }

  func pause() {
    guard !disposed else { return }
    wantsToPlay = false
    player.pause()
  }

  func seek(toMs positionMs: Int64, completion: @escaping () -> Void) {
    guard !disposed else {
      completion()
      return
    }
    let clampedMs = max(positionMs, 0)
    guard itemReady, let item = player.currentItem else {
      pendingStartMs = clampedMs
      completion()
      return
    }
    performSeek(on: item, toMs: clampedMs, completion: completion)
  }

  func setRate(_ rate: Double) {
    guard !disposed else { return }
    targetRate = Float(max(rate, 0.01))
    if wantsToPlay && itemReady {
      applyPlaybackRate()
    }
  }

  func setVolume(_ volume: Double) {
    guard !disposed else { return }
    let normalized = Float(min(max(volume / 100.0, 0.0), 1.0))
    player.volume = normalized
  }

  func setFit(_ fit: String) {
    currentGravity = Self.videoGravity(for: fit)
    attachedView?.playerLayer.videoGravity = currentGravity
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    openGeneration += 1

    criteriaTask?.cancel()
    criteriaTask = nil
    clearItemObservers()

    if let token = timeObserverToken {
      player.removeTimeObserver(token)
      timeObserverToken = nil
    }
    playerObservations.removeAll()

    player.pause()
    player.replaceCurrentItem(with: nil)
    attachedView?.playerLayer.player = nil
    attachedView?.onWindowChanged = nil
    attachedView = nil

    currentDisplayCriteria = nil
    if !hasOtherActiveSessions(playerId) {
      resetDisplayCriteria()
    }

    eventChannel.setStreamHandler(nil)
    eventSink = nil
    pendingEvents.removeAll()
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    if !pendingEvents.isEmpty {
      let queued = pendingEvents
      pendingEvents.removeAll()
      for event in queued {
        events(event)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Display Criteria (Match Dynamic Range & Match Frame Rate)

  private func loadDisplayCriteriaAndHdrInfo(for asset: AVAsset, generation: Int) {
    criteriaTask?.cancel()
    criteriaTask = Task { @MainActor [weak self] in
      guard let self, !self.disposed, self.openGeneration == generation else { return }

      var criteria: AVDisplayCriteria?
      do {
        criteria = try await asset.load(.preferredDisplayCriteria)
      } catch {
        criteria = nil
      }

      var detectedHdrFormat = "sdr"
      var trackSize: CGSize?
      if let videoTrack = try? await asset.loadTracks(withMediaType: .video).first {
        if let descriptions = try? await videoTrack.load(.formatDescriptions),
           let firstDesc = descriptions.first {
          detectedHdrFormat = Self.detectHdrFormat(from: firstDesc)
          if criteria == nil, #available(tvOS 17.0, *) {
            let fps = (try? await videoTrack.load(.nominalFrameRate)) ?? 0
            criteria = AVDisplayCriteria(
              refreshRate: fps > 0 ? fps : 0,
              formatDescription: firstDesc
            )
          }
        }
        if let naturalSize = try? await videoTrack.load(.naturalSize),
           let transform = try? await videoTrack.load(.preferredTransform) {
          let transformed = naturalSize.applying(transform)
          let width = abs(transformed.width)
          let height = abs(transformed.height)
          if width > 0 && height > 0 {
            trackSize = CGSize(width: width, height: height)
          }
        }
      }

      guard !Task.isCancelled, !self.disposed, self.openGeneration == generation else { return }

      self.currentDisplayCriteria = criteria
      self.syncDisplayCriteria()
      self.emit(["type": "hdr", "format": detectedHdrFormat])
      if let trackSize, self.lastEmittedWidth == nil {
        self.emitSize(trackSize)
      }
    }
  }

  private func syncDisplayCriteria() {
    guard !disposed, let window = activeWindow() else { return }
    _ = AVDisplayManager.self
    guard window.responds(to: Selector(("avDisplayManager"))) else { return }
    window.avDisplayManager.preferredDisplayCriteria = currentDisplayCriteria
  }

  private func resetDisplayCriteria() {
    guard let window = activeWindow() else { return }
    _ = AVDisplayManager.self
    guard window.responds(to: Selector(("avDisplayManager"))) else { return }
    window.avDisplayManager.preferredDisplayCriteria = nil
  }

  private func activeWindow() -> UIWindow? {
    if let viewWindow = attachedView?.window {
      return viewWindow
    }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let foreground = scenes.first(where: { $0.activationState == .foregroundActive }) {
      return foreground.windows.first(where: \.isKeyWindow) ?? foreground.windows.first
    }
    return scenes.flatMap(\.windows).first
  }

  private static func detectHdrFormat(from description: CMFormatDescription) -> String {
    let subType = CMFormatDescriptionGetMediaSubType(description)
    // Dolby Vision FourCCs: dvh1, dvhe, dav1, dvc1, dvav
    let dvFourCCs: Set<FourCharCode> = [
      0x64766831,  // 'dvh1'
      0x64766865,  // 'dvhe'
      0x64617631,  // 'dav1'
      0x64766331,  // 'dvc1'
      0x64766176,  // 'dvav'
    ]
    if dvFourCCs.contains(subType) {
      return "dolbyVision"
    }

    if let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] {
      // Dolby Vision configuration box (dvcC / dvvC) on HEVC/AV1 tracks
      if let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String]
        as? [String: Any],
        atoms["dvcC"] != nil || atoms["dvvC"] != nil
      {
        return "dolbyVision"
      }

      let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction as String] as? String
      let altTransfer =
        extensions[kCMFormatDescriptionExtension_AlternativeTransferCharacteristics as String]
        as? String
      let pq = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String
      let hlg = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String

      if transfer == pq || altTransfer == pq {
        return "hdr10"
      }
      if transfer == hlg || altTransfer == hlg {
        return "hlg"
      }
    }
    return "sdr"
  }

  // MARK: - Observers

  private func observePlayer() {
    playerObservations.append(
      player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
        DispatchQueue.main.async {
          self?.handleTimeControlStatus(player.timeControlStatus)
        }
      }
    )

    playerObservations.append(
      player.observe(\.rate, options: [.new]) { [weak self] player, _ in
        DispatchQueue.main.async {
          guard let self, !self.disposed, self.itemReady else { return }
          self.emitPlaying(player.rate > 0)
        }
      }
    )

    timeObserverToken = player.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 10),
      queue: .main
    ) { [weak self] time in
      guard let self, !self.disposed, self.itemReady else { return }
      if let ms = Self.millis(from: time) {
        self.emitPosition(ms)
      }
    }
  }

  private func observeItem(_ item: AVPlayerItem, generation: Int) {
    itemObservations.append(
      item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
        DispatchQueue.main.async {
          self?.handleItemStatus(observedItem, generation: generation)
        }
      }
    )

    itemObservations.append(
      item.observe(\.duration, options: [.new]) { [weak self] observedItem, _ in
        DispatchQueue.main.async {
          guard let self, !self.disposed, self.openGeneration == generation else { return }
          self.emitDurationIfValid(for: observedItem)
        }
      }
    )

    itemObservations.append(
      item.observe(\.presentationSize, options: [.initial, .new]) { [weak self] observedItem, _ in
        DispatchQueue.main.async {
          guard let self, !self.disposed, self.openGeneration == generation else { return }
          self.emitSize(observedItem.presentationSize)
        }
      }
    )

    itemObservations.append(
      item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] observedItem, _ in
        DispatchQueue.main.async {
          guard let self, !self.disposed, self.openGeneration == generation else { return }
          self.emitBufferedEnd(for: observedItem)
        }
      }
    )

    itemObservations.append(
      item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
        DispatchQueue.main.async {
          guard let self, !self.disposed, self.openGeneration == generation, self.itemReady else {
            return
          }
          self.updateBufferingState(for: observedItem)
        }
      }
    )

    itemObservations.append(
      item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] observedItem, _ in
        DispatchQueue.main.async {
          guard let self, !self.disposed, self.openGeneration == generation, self.itemReady else {
            return
          }
          self.updateBufferingState(for: observedItem)
        }
      }
    )

    let center = NotificationCenter.default
    itemNotificationTokens.append(
      center.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] _ in
        guard let self, !self.disposed, self.openGeneration == generation else { return }
        self.wantsToPlay = false
        self.emitPlaying(false)
        self.emitBuffering(false)
        self.emit(["type": "completed", "value": true])
      }
    )

    itemNotificationTokens.append(
      center.addObserver(
        forName: .AVPlayerItemFailedToPlayToEndTime,
        object: item,
        queue: .main
      ) { [weak self] notification in
        guard let self, !self.disposed, self.openGeneration == generation else { return }
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
        self.emitError(Self.describeError(error, item: item))
      }
    )
  }

  private func clearItemObservers() {
    itemObservations.removeAll()
    for token in itemNotificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
    itemNotificationTokens.removeAll()
  }

  private func handleItemStatus(_ item: AVPlayerItem, generation: Int) {
    guard !disposed, openGeneration == generation else { return }
    switch item.status {
    case .unknown:
      break
    case .failed:
      emitError(Self.describeError(item.error as NSError?, item: item))
    case .readyToPlay:
      guard !itemReady else { return }
      itemReady = true
      emitDurationIfValid(for: item)
      emitSize(item.presentationSize)
      emitBufferedEnd(for: item)

      let startMs = pendingStartMs
      pendingStartMs = 0
      if startMs > 0 {
        performSeek(on: item, toMs: startMs) { [weak self] in
          guard let self, !self.disposed, self.openGeneration == generation else { return }
          self.applyPlaybackState()
          self.updateBufferingState(for: item)
        }
      } else {
        applyPlaybackState()
        updateBufferingState(for: item)
      }
    @unknown default:
      break
    }
  }

  private func handleTimeControlStatus(_ status: AVPlayer.TimeControlStatus) {
    guard !disposed, itemReady else { return }
    switch status {
    case .playing:
      emitPlaying(true)
      emitBuffering(false)
    case .paused:
      emitPlaying(false)
      emitBuffering(false)
    case .waitingToPlayAtSpecifiedRate:
      emitBuffering(true)
    @unknown default:
      break
    }
  }

  private func updateBufferingState(for item: AVPlayerItem) {
    guard itemReady else { return }
    if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
      emitBuffering(true)
    } else if !wantsToPlay {
      emitBuffering(false)
    } else {
      emitBuffering(!item.isPlaybackLikelyToKeepUp && item.isPlaybackBufferEmpty)
    }
  }

  private func applyPlaybackState() {
    guard itemReady else { return }
    if wantsToPlay {
      applyPlaybackRate()
    } else {
      player.pause()
      emitPlaying(false)
    }
  }

  private func applyPlaybackRate() {
    var rate = targetRate
    if let item = player.currentItem {
      if rate > 2.0 && !item.canPlayFastForward {
        rate = 2.0
      } else if rate < 1.0 && !item.canPlaySlowForward {
        rate = 1.0
      }
    }
    if abs(rate - 1.0) < 0.001 {
      player.play()
    } else {
      player.rate = rate
    }
  }

  private func performSeek(
    on item: AVPlayerItem,
    toMs positionMs: Int64,
    completion: @escaping () -> Void
  ) {
    let durationMs = Self.durationMillis(for: item)
    let clampedMs = durationMs.map { min(positionMs, $0) } ?? positionMs
    let target = CMTime(value: clampedMs, timescale: 1000)
    // Add 1 ms tolerance at exact duration to avoid AVPlayer seekToTime hanging
    // at end-of-file (Apple radar / Flutter #124475).
    let atEnd = durationMs != nil && clampedMs >= durationMs!
    let tolerance = atEnd ? CMTime(value: 1, timescale: 1000) : .zero

    player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) {
      [weak self] _ in
      DispatchQueue.main.async {
        if let self, !self.disposed, let currentMs = Self.millis(from: self.player.currentTime()) {
          self.emitPosition(currentMs)
        }
        completion()
      }
    }
  }

  // MARK: - Event Emission

  private func emit(_ payload: [String: Any]) {
    guard !disposed else { return }
    if let sink = eventSink {
      sink(payload)
    } else {
      pendingEvents.append(payload)
    }
  }

  private func emitPosition(_ ms: Int64) {
    let clamped = max(ms, 0)
    guard lastEmittedPositionMs != clamped else { return }
    lastEmittedPositionMs = clamped
    emit(["type": "position", "ms": clamped])
  }

  private func emitDurationIfValid(for item: AVPlayerItem) {
    guard let ms = Self.durationMillis(for: item), ms > 0 else { return }
    guard lastEmittedDurationMs != ms else { return }
    lastEmittedDurationMs = ms
    emit(["type": "duration", "ms": ms])
  }

  private func emitSize(_ size: CGSize) {
    guard size.width > 0 && size.height > 0 else { return }
    let w = Double(size.width)
    let h = Double(size.height)
    guard lastEmittedWidth != w || lastEmittedHeight != h else { return }
    lastEmittedWidth = w
    lastEmittedHeight = h
    emit(["type": "size", "width": w, "height": h])
  }

  private func emitBufferedEnd(for item: AVPlayerItem) {
    let currentMs = Self.millis(from: player.currentTime()) ?? 0
    var endMs: Int64 = 0
    for rangeValue in item.loadedTimeRanges {
      let range = rangeValue.timeRangeValue
      guard let start = Self.millis(from: range.start),
            let dur = Self.millis(from: range.duration)
      else { continue }
      let rangeEnd = start + dur
      if start <= currentMs + 500 && rangeEnd > endMs {
        endMs = rangeEnd
      }
    }
    guard lastEmittedBufferedMs != endMs else { return }
    lastEmittedBufferedMs = endMs
    emit(["type": "buffered", "ms": endMs])
  }

  private func emitPlaying(_ value: Bool) {
    guard lastEmittedPlaying != value else { return }
    lastEmittedPlaying = value
    emit(["type": "playing", "value": value])
  }

  private func emitBuffering(_ value: Bool) {
    guard lastEmittedBuffering != value else { return }
    lastEmittedBuffering = value
    emit(["type": "buffering", "value": value])
  }

  private func emitError(_ message: String) {
    emit(["type": "error", "message": message])
  }

  // MARK: - Helpers

  static func videoGravity(for fit: String) -> AVLayerVideoGravity {
    switch fit {
    case "cover":
      return .resizeAspectFill
    case "fill":
      return .resize
    default:
      return .resizeAspect
    }
  }

  private static func durationMillis(for item: AVPlayerItem) -> Int64? {
    if let itemMs = millis(from: item.duration), itemMs > 0 {
      return itemMs
    }
    if let assetMs = millis(from: item.asset.duration), assetMs > 0 {
      return assetMs
    }
    return nil
  }

  private static func millis(from time: CMTime) -> Int64? {
    guard time.isValid && !time.isIndefinite && !time.isNegativeInfinity && !time.isPositiveInfinity
    else {
      return nil
    }
    let seconds = CMTimeGetSeconds(time)
    guard seconds.isFinite else { return nil }
    return Int64((seconds * 1000.0).rounded())
  }

  private static func describeError(_ error: NSError?, item: AVPlayerItem) -> String {
    var parts: [String] = ["Failed to load video"]
    if let desc = error?.localizedDescription, !desc.isEmpty {
      parts.append(desc)
    }
    if let reason = error?.localizedFailureReason, !reason.isEmpty, !parts.contains(reason) {
      parts.append(reason)
    }
    if let underlying = error?.userInfo[NSUnderlyingErrorKey] as? NSError {
      let detail = underlying.localizedDescription
      if !detail.isEmpty && !parts.contains(detail) {
        parts.append(detail)
      }
    }
    if let logEvent = item.errorLog()?.events.last,
       let comment = logEvent.errorComment,
       !comment.isEmpty,
       !parts.contains(comment) {
      parts.append(comment)
    }
    return parts.joined(separator: ": ")
  }
}
