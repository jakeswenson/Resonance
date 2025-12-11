//
//  PodcastPlayer.swift
//  Resonance
//
//  Main public API for podcast playback.
//  Simple, episode-centric design for podcast apps.
//

@preconcurrency import AVFoundation
import Foundation

/// Podcast audio player with streaming, caching, downloads, and queue.
///
/// Simple 3-line usage:
/// ```swift
/// let player = PodcastPlayer()
/// try await player.play(episode)
/// ```
///
/// Features:
/// - Plays local files and remote streams seamlessly
/// - Automatic caching (stream once → replay offline)
/// - Background downloads
/// - Queue with auto-advance
/// - Playback speed (0.5x - 3.0x)
/// - Volume boost
/// - Smart silence trimming (speeds up silent portions)
@MainActor
public final class PodcastPlayer: Sendable {

    // MARK: - Reactive State

    /// Current playback state.
    public var state: AsyncCurrentValue<PlaybackState> { engine.state }

    /// Current playback time in seconds.
    public var currentTime: AsyncCurrentValue<TimeInterval> { engine.currentTime }

    /// Episode duration in seconds.
    public var duration: AsyncCurrentValue<TimeInterval> { engine.duration }

    /// Buffer progress (0.0 to 1.0) for streaming.
    public var bufferProgress: AsyncCurrentValue<Double> { engine.bufferProgress }

    /// Current queue.
    public let queue: AsyncCurrentValue<[Episode]>

    /// Download progress events.
    public let downloadProgress: AsyncPassthrough<DownloadEvent>

    /// Silence trimming statistics (time saved, etc.).
    public var silenceStats: AsyncCurrentValue<SilenceAnalyzer.Stats> { engine.silenceStats }

    // MARK: - Current Episode

    /// Currently loaded episode.
    public private(set) var currentEpisode: Episode?

    /// Whether an episode is loaded and ready.
    public var isLoaded: Bool { currentEpisode != nil }

    /// Whether currently playing.
    public var isPlaying: Bool { engine.isPlaying }

    // MARK: - Settings

    /// Playback speed (0.5 to 3.0, default 1.0).
    public var speed: Float {
        get { engine.speed }
        set { engine.speed = newValue }
    }

    /// Volume boost for quiet podcasts.
    public var boostVolume: Bool {
        get { engine.boostVolume }
        set { engine.boostVolume = newValue }
    }

    /// Trim silences automatically (speed up silent portions).
    ///
    /// When enabled, the player analyzes buffered audio ahead of playback
    /// to detect silent portions, then speeds up during those segments.
    /// Works with both streaming (analyzes buffered data) and local files.
    ///
    /// Use `silenceStats` to track time saved and silence statistics.
    public var trimSilence: Bool {
        get { engine.trimSilence }
        set { engine.trimSilence = newValue }
    }

    // MARK: - Internal

    private let engine: PlaybackEngine
    private let cache: EpisodeCache
    private let downloadManager: DownloadManager
    private var _queue: [Episode] = []
    private var queueIndex: Int = -1

    // MARK: - Init

    /// Creates a new podcast player.
    public init() {
        self.engine = PlaybackEngine()
        self.cache = EpisodeCache()
        self.downloadManager = DownloadManager()
        self.queue = AsyncCurrentValue([])
        self.downloadProgress = AsyncPassthrough()

        // Wire up download progress
        Task { [weak self] in
            guard let self = self else { return }
            await self.downloadManager.setProgressHandler { [weak self] episodeId, progress in
                self?.downloadProgress.send(DownloadEvent(
                    episodeId: episodeId,
                    progress: progress,
                    state: .downloading
                ))
            }
        }
    }

    // MARK: - Playback

    /// Plays an episode.
    ///
    /// Handles local files, cached files, and remote streaming automatically.
    ///
    /// - Parameters:
    ///   - episode: Episode to play
    ///   - startTime: Optional start position in seconds
    public func play(_ episode: Episode, from startTime: TimeInterval? = nil) async throws {
        currentEpisode = episode

        // Get best URL (cached if available)
        let url = await cache.playbackURL(for: episode)

        // Load and prepare
        try await engine.load(url: url, startTime: startTime)

        // Start playback
        try engine.play()
    }

    /// Pauses playback.
    public func pause() {
        engine.pause()
    }

    /// Resumes playback.
    public func resume() throws {
        try engine.play()
    }

    /// Stops playback.
    public func stop() {
        engine.stop()
    }

    /// Seeks to a specific time.
    public func seek(to time: TimeInterval) async {
        await engine.seek(to: time)
    }

    /// Skips forward (default 30 seconds).
    public func skipForward(_ seconds: TimeInterval = 30) async {
        await engine.skipForward(seconds)
    }

    /// Skips backward (default 15 seconds).
    public func skipBackward(_ seconds: TimeInterval = 15) async {
        await engine.skipBackward(seconds)
    }

    // MARK: - Queue

    /// Adds an episode to the end of the queue.
    public func addToQueue(_ episode: Episode) {
        _queue.append(episode)
        queue.send(_queue)
    }

    /// Inserts an episode to play next.
    public func playNext(_ episode: Episode) {
        let insertIndex = queueIndex + 1
        if insertIndex < _queue.count {
            _queue.insert(episode, at: insertIndex)
        } else {
            _queue.append(episode)
        }
        queue.send(_queue)
    }

    /// Removes an episode from the queue.
    public func removeFromQueue(_ episode: Episode) {
        if let index = _queue.firstIndex(of: episode) {
            _queue.remove(at: index)
            if index <= queueIndex {
                queueIndex -= 1
            }
            queue.send(_queue)
        }
    }

    /// Clears the queue.
    public func clearQueue() {
        _queue.removeAll()
        queueIndex = -1
        queue.send(_queue)
    }

    /// Skips to the next episode in queue.
    public func skipToNext() async throws {
        guard queueIndex + 1 < _queue.count else {
            throw AudioError.internalError("No next episode in queue")
        }
        queueIndex += 1
        try await play(_queue[queueIndex])
    }

    /// Skips to the previous episode in queue.
    public func skipToPrevious() async throws {
        guard queueIndex > 0 else {
            throw AudioError.internalError("No previous episode in queue")
        }
        queueIndex -= 1
        try await play(_queue[queueIndex])
    }

    // MARK: - Cache

    /// Checks if an episode is cached.
    public func isCached(_ episode: Episode) async -> Bool {
        await cache.isCached(episode)
    }

    /// Clears the episode cache.
    public func clearCache() async {
        await cache.clearAll()
    }

    /// Cache size in bytes.
    public func cacheSize() async -> Int64 {
        await cache.totalSize
    }

    // MARK: - Downloads

    /// Downloads an episode for offline playback.
    ///
    /// Progress is reported via `downloadProgress` stream.
    ///
    /// - Parameter episode: Episode to download
    /// - Returns: Local file URL when complete
    @discardableResult
    public func download(_ episode: Episode) async throws -> URL {
        downloadProgress.send(DownloadEvent(episodeId: episode.id, progress: 0, state: .downloading))

        let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Resonance/Downloads", isDirectory: true)

        do {
            let destURL = try await downloadManager.download(episode: episode, to: downloads)

            // Also add to cache
            try await cache.cache(episode: episode, fileURL: destURL)

            downloadProgress.send(DownloadEvent(episodeId: episode.id, progress: 1.0, state: .completed))
            return destURL
        } catch is CancellationError {
            downloadProgress.send(DownloadEvent(episodeId: episode.id, progress: 0, state: .cancelled))
            throw AudioError.cancelled
        } catch {
            downloadProgress.send(DownloadEvent(episodeId: episode.id, progress: 0, state: .failed(error.localizedDescription)))
            throw error
        }
    }

    /// Cancels a download in progress.
    public func cancelDownload(_ episode: Episode) async {
        await downloadManager.cancel(episodeId: episode.id)
    }

    /// Whether an episode is currently downloading.
    public func isDownloading(_ episode: Episode) async -> Bool {
        await downloadManager.isDownloading(episode.id)
    }

    /// Checks if an episode is downloaded.
    public func isDownloaded(_ episode: Episode) -> Bool {
        let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Resonance/Downloads", isDirectory: true)
        let ext = episode.url.pathExtension.isEmpty ? "mp3" : episode.url.pathExtension
        let fileURL = downloads.appendingPathComponent("\(episode.id).\(ext)")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Deletes a downloaded episode.
    public func deleteDownload(_ episode: Episode) throws {
        let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Resonance/Downloads", isDirectory: true)
        let ext = episode.url.pathExtension.isEmpty ? "mp3" : episode.url.pathExtension
        let fileURL = downloads.appendingPathComponent("\(episode.id).\(ext)")
        try FileManager.default.removeItem(at: fileURL)
    }

    /// Returns all downloaded episodes' file URLs.
    public func downloadedFiles() -> [URL] {
        let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Resonance/Downloads", isDirectory: true)
        let files = try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: nil)
        return files ?? []
    }

    // MARK: - Clip Extraction

    /// Extracts an audio clip from an episode using absolute time range.
    ///
    /// The episode must be downloaded or cached locally.
    /// Export takes 1-5 seconds depending on clip length.
    ///
    /// - Parameters:
    ///   - episode: Source episode (must be cached or downloaded)
    ///   - start: Start time in seconds
    ///   - end: End time in seconds
    ///   - format: Output format (.m4a for sharing, .wav for transcription)
    /// - Returns: AudioClip with file URL
    /// - Throws: AudioError if episode not available locally or export fails
    public func extractClip(
        from episode: Episode,
        start: TimeInterval,
        end: TimeInterval,
        format: ClipFormat = .m4a
    ) async throws -> AudioClip {
        // Get local URL (must be downloaded or cached)
        let sourceURL = try await getLocalURL(for: episode)

        // Create asset
        let asset = AVURLAsset(url: sourceURL)

        // Determine export preset based on format
        let presetName: String
        let outputFileType: AVFileType

        switch format {
        case .m4a:
            presetName = AVAssetExportPresetAppleM4A
            outputFileType = .m4a
        case .wav:
            presetName = AVAssetExportPresetPassthrough
            outputFileType = .wav
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw AudioError.internalError("Cannot create export session")
        }

        // Configure time range
        let startCMTime = CMTime(seconds: start, preferredTimescale: 600)
        let endCMTime = CMTime(seconds: end, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)

        // Configure output
        let outputURL = clipOutputURL(episodeId: episode.id, start: start, format: format)

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType

        // Export (async - this takes time)
        await exportSession.export()

        guard exportSession.status == .completed else {
            let errorMsg = exportSession.error?.localizedDescription ?? "unknown error"
            throw AudioError.internalError("Export failed: \(errorMsg)")
        }

        return AudioClip(
            episode: episode,
            startTime: start,
            endTime: end,
            fileURL: outputURL
        )
    }

    /// Extracts an audio clip relative to the current playback position.
    ///
    /// Useful for capturing "what was just said" moments.
    /// The episode must be downloaded or cached locally.
    ///
    /// - Parameters:
    ///   - lookback: How far back from current position in seconds
    ///   - duration: Length of clip in seconds
    ///   - format: Output format (.m4a for sharing, .wav for transcription)
    /// - Returns: AudioClip with file URL
    /// - Throws: AudioError if no episode playing or export fails
    ///
    /// ```swift
    /// // Capture the last 30 seconds
    /// let clip = try await player.extractClip(lookback: 30, duration: 30)
    /// ```
    public func extractClip(
        lookback: TimeInterval,
        duration: TimeInterval,
        format: ClipFormat = .m4a
    ) async throws -> AudioClip {
        guard let episode = currentEpisode else {
            throw AudioError.internalError("No episode playing")
        }

        let currentPos = currentTime.value
        let totalDuration = self.duration.value

        // Calculate start/end times
        let start = max(0, currentPos - lookback)
        let end = min(start + duration, totalDuration)

        return try await extractClip(from: episode, start: start, end: end, format: format)
    }

    /// Deletes a clip file.
    ///
    /// Clips are stored in the temporary directory and may be cleaned up
    /// by the system, but you can delete them explicitly when done.
    public func deleteClip(_ clip: AudioClip) throws {
        if FileManager.default.fileExists(atPath: clip.fileURL.path) {
            try FileManager.default.removeItem(at: clip.fileURL)
        }
    }

    // MARK: - Private Helpers

    private func getLocalURL(for episode: Episode) async throws -> URL {
        // Check downloads first
        if isDownloaded(episode) {
            return downloadedFileURL(for: episode)
        }

        // Check cache
        if await isCached(episode) {
            return await cache.playbackURL(for: episode)
        }

        throw AudioError.internalError("Episode must be downloaded or cached for clip extraction")
    }

    private func downloadedFileURL(for episode: Episode) -> URL {
        let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Resonance/Downloads", isDirectory: true)
        let ext = episode.url.pathExtension.isEmpty ? "mp3" : episode.url.pathExtension
        return downloads.appendingPathComponent("\(episode.id).\(ext)")
    }

    private func clipOutputURL(episodeId: String, start: TimeInterval, format: ClipFormat) -> URL {
        let filename = "\(episodeId)-\(Int(start)).\(format.fileExtension)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}

// MARK: - Download Event

/// Download progress event.
public struct DownloadEvent: Sendable {
    public let episodeId: String
    public let progress: Double
    public let state: DownloadState

    public enum DownloadState: Sendable {
        case pending
        case downloading
        case completed
        case failed(String)
        case cancelled
    }
}
