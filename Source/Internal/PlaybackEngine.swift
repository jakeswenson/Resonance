//
//  PlaybackEngine.swift
//  Resonance
//
//  Internal AVPlayer wrapper handling all playback operations.
//  Supports streaming, local files, speed control, and volume boost.
//

@preconcurrency import AVFoundation
import Foundation

/// Internal playback engine using AVPlayer.
///
/// Handles:
/// - Streaming from remote URLs
/// - Local file playback
/// - Playback speed with pitch correction
/// - Volume boost
/// - Silence trimming (smart speed)
/// - Time/duration observation
@MainActor
final class PlaybackEngine: Sendable {

    // MARK: - State

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var currentURL: URL?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    private var _isPlaying: Bool = false
    private var _speed: Float = 1.0
    private var _boostVolume: Bool = false
    private var _trimSilence: Bool = false

    // Silence analysis
    private let silenceAnalyzer = SilenceAnalyzer()
    private var analysisTask: Task<Void, Never>?

    // MARK: - Reactive State

    let state: AsyncCurrentValue<PlaybackState>
    let currentTime: AsyncCurrentValue<TimeInterval>
    let duration: AsyncCurrentValue<TimeInterval>
    let bufferProgress: AsyncCurrentValue<Double>
    let silenceStats: AsyncCurrentValue<SilenceAnalyzer.Stats>

    // MARK: - Init

    init() {
        self.state = AsyncCurrentValue(.idle)
        self.currentTime = AsyncCurrentValue(0)
        self.duration = AsyncCurrentValue(0)
        self.bufferProgress = AsyncCurrentValue(0)
        self.silenceStats = AsyncCurrentValue(SilenceAnalyzer.Stats(
            totalDurationAnalyzed: 0,
            silenceDuration: 0,
            segmentCount: 0
        ))
    }

    // MARK: - Playback Control

    /// Loads and prepares an episode for playback.
    /// - Parameters:
    ///   - url: Audio URL (local or remote)
    ///   - startTime: Optional start position in seconds
    func load(url: URL, startTime: TimeInterval? = nil) async throws {
        cleanup()

        state.send(.loading)
        currentURL = url

        // Reset silence analysis for new content
        await silenceAnalyzer.reset()

        // Create asset and player item
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        // Configure for speech (podcasts)
        item.audioTimePitchAlgorithm = .timeDomain

        playerItem = item

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = true
        player = avPlayer

        setupObservers(player: avPlayer, item: item)

        // Wait for ready
        try await waitForReady(item: item)

        // Seek to start time if provided
        if let start = startTime, start > 0 {
            await seek(to: start)
        }

        // Apply current settings
        applySpeed()
        applyVolumeBoost()

        state.send(.ready)
    }

    /// Starts or resumes playback.
    func play() throws {
        guard let player = player else {
            throw AudioError.internalError("No audio loaded")
        }

        player.play()
        applySpeed() // Ensure speed is applied
        _isPlaying = true
        state.send(.playing)
    }

    /// Pauses playback.
    func pause() {
        player?.pause()
        _isPlaying = false
        state.send(.paused)
    }

    /// Stops playback and resets.
    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        _isPlaying = false
        currentTime.send(0)
        state.send(.ready)
    }

    /// Seeks to a specific time.
    func seek(to time: TimeInterval) async {
        guard let player = player else { return }

        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        await player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime.send(time)
    }

    /// Skips forward by seconds.
    func skipForward(_ seconds: TimeInterval) async {
        let target = currentTime.value + seconds
        let clamped = min(target, duration.value)
        await seek(to: clamped)
    }

    /// Skips backward by seconds.
    func skipBackward(_ seconds: TimeInterval) async {
        let target = currentTime.value - seconds
        let clamped = max(target, 0)
        await seek(to: clamped)
    }

    // MARK: - Settings

    /// Playback speed (0.5 to 3.0).
    var speed: Float {
        get { _speed }
        set {
            _speed = max(0.5, min(3.0, newValue))
            applySpeed()
        }
    }

    /// Volume boost for quiet audio.
    var boostVolume: Bool {
        get { _boostVolume }
        set {
            _boostVolume = newValue
            applyVolumeBoost()
        }
    }

    /// Trim silence (speed up silent portions).
    var trimSilence: Bool {
        get { _trimSilence }
        set {
            _trimSilence = newValue
            if newValue {
                startSilenceAnalysis()
            } else {
                stopSilenceAnalysis()
                applySpeed()  // Reset to normal user speed
            }
        }
    }

    /// Current playback state.
    var isPlaying: Bool { _isPlaying }

    // MARK: - Private

    private func applySpeed() {
        guard let player = player, _isPlaying else { return }
        player.rate = _speed
    }

    private func applyVolumeBoost() {
        // Volume boost: increase to 1.5x when enabled
        player?.volume = _boostVolume ? 1.5 : 1.0
    }

    private func setupObservers(player: AVPlayer, item: AVPlayerItem) {
        // Time observer (every 0.1 seconds for responsive silence trimming)
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, time.isValid && !time.isIndefinite else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.currentTime.send(time.seconds)

                // Apply silence-aware speed if enabled
                if self._trimSilence && self._isPlaying {
                    await self.applySilenceAwareSpeed(at: time.seconds)
                }
            }
        }

        // Duration observer
        durationObserver = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            guard item.duration.isValid && !item.duration.isIndefinite else { return }
            self?.duration.send(item.duration.seconds)
        }

        // Buffer observer
        bufferObserver = item.observe(\.loadedTimeRanges, options: [.new]) { [weak self] item, _ in
            guard let range = item.loadedTimeRanges.first?.timeRangeValue else { return }
            let buffered = range.start.seconds + range.duration.seconds
            let total = item.duration.isValid ? item.duration.seconds : buffered
            let progress = total > 0 ? buffered / total : 0
            let isLikelyToKeepUp = item.isPlaybackLikelyToKeepUp

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.bufferProgress.send(progress)

                // Update state for buffering
                if !isLikelyToKeepUp && self._isPlaying && self.state.value == .playing {
                    self.state.send(.buffering)
                } else if isLikelyToKeepUp && self._isPlaying && self.state.value == .buffering {
                    self.state.send(.playing)
                }
            }
        }

        // Status observer
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            if item.status == .failed {
                self?.state.send(.error(.internalError(item.error?.localizedDescription ?? "Playback failed")))
            }
        }

        // Rate observer for detecting end of playback
        rateObserver = player.observe(\.rate, options: [.new]) { [weak self] player, change in
            // Get rate from change dictionary to avoid MainActor isolation warning
            guard let rate = change.newValue else { return }

            // Capture other values
            let currentTime = player.currentTime().seconds
            let duration: Double? = {
                guard let item = player.currentItem,
                      item.duration.isValid && !item.duration.isIndefinite else { return nil }
                return item.duration.seconds
            }()

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // If rate drops to 0 and we were playing, check if completed
                if rate == 0 && self._isPlaying {
                    if let total = duration, currentTime >= total - 0.5 {
                        self._isPlaying = false
                        self.state.send(.completed)
                    }
                }
            }
        }
    }

    private func waitForReady(item: AVPlayerItem) async throws {
        for _ in 0..<100 { // Max 10 seconds
            switch item.status {
            case .readyToPlay:
                return
            case .failed:
                throw AudioError.internalError(item.error?.localizedDescription ?? "Failed to load")
            case .unknown:
                try await Task.sleep(nanoseconds: 100_000_000)
            @unknown default:
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        throw AudioError.internalError("Timeout loading audio")
    }

    private func cleanup() {
        // Stop silence analysis
        stopSilenceAnalysis()

        statusObserver?.invalidate()
        statusObserver = nil

        durationObserver?.invalidate()
        durationObserver = nil

        bufferObserver?.invalidate()
        bufferObserver = nil

        rateObserver?.invalidate()
        rateObserver = nil

        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil

        player?.pause()
        player = nil
        playerItem = nil
        currentURL = nil
        _isPlaying = false

        currentTime.send(0)
        duration.send(0)
        bufferProgress.send(0)
    }

    // MARK: - Silence Trimming

    private func startSilenceAnalysis() {
        guard let url = currentURL else { return }

        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                let currentPos = self.currentTime.value
                let bufferedEnd = self.bufferProgress.value * self.duration.value
                let totalDuration = self.duration.value

                // For local files, bufferedEnd might be 0, so use duration
                let analysisEnd = bufferedEnd > 0 ? bufferedEnd : totalDuration

                // Analyze up to 60 seconds ahead (or whatever is buffered)
                let lookAhead = min(60, analysisEnd - currentPos)

                if lookAhead > 5 {  // Only analyze if we have at least 5 seconds ahead
                    _ = await self.silenceAnalyzer.analyze(
                        url: url,
                        from: currentPos,
                        duration: lookAhead,
                        bufferedEnd: analysisEnd
                    )

                    // Update stats
                    let stats = await self.silenceAnalyzer.stats()
                    self.silenceStats.send(stats)
                }

                // Re-analyze every 5 seconds
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func stopSilenceAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
    }

    private func applySilenceAwareSpeed(at time: TimeInterval) async {
        guard let player = player, _isPlaying else { return }

        let effectiveRate = await silenceAnalyzer.rate(at: time, baseRate: _speed)

        // Only update if rate actually changed (avoid unnecessary changes)
        if abs(player.rate - effectiveRate) > 0.01 {
            player.rate = effectiveRate
        }
    }

    deinit {
        // Note: cleanup() should be called before deinit
    }
}
