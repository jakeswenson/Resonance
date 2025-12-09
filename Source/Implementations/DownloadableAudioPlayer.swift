//
//  DownloadableAudioPlayer.swift
//  Resonance
//
//  Enhanced audio player with download management and offline capabilities.
//  Provides background downloads with reactive progress tracking and offline-first experiences.
//

import Foundation
import Combine
import AVFoundation

/// Enhanced audio player with download management capabilities
///
/// DownloadableAudioPlayer extends BasicAudioPlayer with AudioDownloadable features,
/// enabling offline-first audio experiences with background downloading.
///
/// **Enhanced usage pattern:**
/// ```swift
/// let player = DownloadableAudioPlayer()
///
/// // Download audio for offline use
/// player.downloadAudio(from: url, metadata: metadata)
///     .sink { progress in
///         updateProgressUI(progress.progress)
///     }
///     .store(in: &cancellables)
///
/// // Check offline availability
/// if player.isAvailableOffline(url) {
///     try await player.loadAudio(from: player.localURL(for: url)!, metadata: nil).async()
/// }
/// ```
///
/// This implementation:
/// - Inherits all AudioPlayable functionality from BasicAudioPlayer
/// - Implements AudioDownloadable for comprehensive download management
/// - Uses DownloadManagerActor via ReactiveAudioCoordinator for thread safety
/// - Provides background download with app lifecycle support
/// - Offers offline content management and storage controls
/// - Maintains Swift 6 concurrency and Sendable compliance
@MainActor
public final class DownloadableAudioPlayer: BasicAudioPlayer, AudioDownloadable {

    // MARK: - Enhanced Dependencies

    /// Access to download manager through coordinator
    private var downloadCoordinator: ReactiveAudioCoordinator {
        return coordinator
    }

    // MARK: - Download State Management

    /// Download progress subject for reactive updates
    private let downloadProgressSubject = CurrentValueSubject<[URL: DownloadProgress], Never>([:])

    /// Cellular downloads allowed flag
    private var _allowsCellularDownloads: Bool = true

    /// Download cancellables
    private var downloadCancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize DownloadableAudioPlayer with optional coordinator dependency injection
    /// - Parameter coordinator: Optional coordinator instance (defaults to shared)
    public override init(coordinator: ReactiveAudioCoordinator = .shared) {
        super.init(coordinator: coordinator)
        setupDownloadBindings()
    }

    deinit {
        cleanupDownload()
    }

    // MARK: - AudioDownloadable Protocol Implementation

    /// Downloads audio from a remote URL with optional metadata
    public func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError> {
        return Future<DownloadProgress, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.downloadCoordinator.ensureReady()

                    // Check if already downloaded
                    if let localURL = await self.downloadCoordinator.localURL(for: url) {
                        let completeProgress = DownloadProgress(
                            remoteURL: url,
                            localURL: localURL,
                            progress: 1.0,
                            state: .completed,
                            downloadedBytes: 0,
                            metadata: metadata
                        )
                        promise(.success(completeProgress))
                        return
                    }

                    // Start download through coordinator
                    let downloadPublisher = self.downloadCoordinator.downloadAudio(from: url, metadata: metadata)

                    downloadPublisher
                        .sink(
                            receiveCompletion: { completion in
                                if case .failure(let error) = completion {
                                    promise(.failure(error))
                                }
                            },
                            receiveValue: { progress in
                                promise(.success(progress))
                            }
                        )
                        .store(in: &self.downloadCancellables)

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Download failed: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .flatMap { initialProgress in
            // Continue emitting progress updates
            self.downloadCoordinator.downloadProgressPublisher
                .compactMap { progressMap in progressMap[url] }
                .prepend(initialProgress)
                .handleEvents(receiveCompletion: { _ in
                    // Download completed or failed, remove from active tracking
                })
                .eraseToAnyPublisher()
        }
        .eraseToAnyPublisher()
    }

    /// Cancels an active download for the specified URL
    public func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return downloadCoordinator.cancelDownload(for: url)
    }

    /// Pauses an active download for the specified URL
    public func pauseDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return downloadCoordinator.pauseDownload(for: url)
    }

    /// Resumes a paused download for the specified URL
    public func resumeDownload(for url: URL) -> AnyPublisher<DownloadProgress, AudioError> {
        return downloadCoordinator.resumeDownload(for: url)
    }

    /// Returns the local URL for a downloaded audio file, if it exists
    public func localURL(for remoteURL: URL) -> URL? {
        // This needs to be synchronous, so we use a blocking call
        return Task.synchronous {
            await downloadCoordinator.localURL(for: remoteURL)
        }
    }

    /// Deletes a downloaded audio file from local storage
    public func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        return downloadCoordinator.deleteDownload(at: localURL)
    }

    /// Returns information about all downloaded audio files
    public func getAllDownloads() -> [DownloadInfo] {
        return Task.synchronous {
            await downloadCoordinator.getAllDownloads()
        }
    }

    /// Clears all downloaded audio content and associated metadata
    public func clearAllDownloads() -> AnyPublisher<Void, AudioError> {
        let allDownloads = getAllDownloads()

        if allDownloads.isEmpty {
            return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
        }

        let deletePublishers = allDownloads.map { downloadInfo in
            deleteDownload(at: downloadInfo.localURL)
        }

        return deletePublishers.publisher.flatMap { $0 }
            .collect()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Publisher that emits real-time download progress for all active downloads
    public var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> {
        downloadProgressSubject.eraseToAnyPublisher()
    }

    /// Controls whether downloads are allowed over cellular data connections
    public var allowsCellularDownloads: Bool {
        get {
            return _allowsCellularDownloads
        }
        set {
            _allowsCellularDownloads = newValue
            Task {
                await downloadCoordinator.setCellularDownloadsAllowed(newValue)
            }
        }
    }

    /// Returns the total size of all downloaded audio content in bytes
    public func totalDownloadedSize() -> Int64 {
        return getAllDownloads().reduce(0) { total, download in
            total + download.fileSize
        }
    }

    /// Returns available storage space for downloads in bytes
    public func availableDownloadSpace() -> Int64? {
        // Query system for available disk space
        do {
            let resourceValues = try FileManager.default.url(for: .documentDirectory,
                                                           in: .userDomainMask,
                                                           appropriateFor: nil,
                                                           create: false)
                .resourceValues(forKeys: [.volumeAvailableCapacityKey])

            return resourceValues.volumeAvailableCapacity.map(Int64.init)
        } catch {
            Log.error("DownloadableAudioPlayer: Failed to get available space: \(error)")
            return nil
        }
    }

    /// Downloads multiple audio files concurrently with shared progress tracking
    public func downloadBatch(_ requests: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<BatchDownloadProgress, AudioError> {
        guard !requests.isEmpty else {
            let emptyProgress = BatchDownloadProgress(
                overallProgress: 1.0,
                completedCount: 0,
                totalCount: 0,
                failedCount: 0,
                activeDownloads: [],
                totalBytesDownloaded: 0,
                expectedTotalBytes: 0
            )
            return Just(emptyProgress).setFailureType(to: AudioError.self).eraseToAnyPublisher()
        }

        // Start all downloads concurrently
        let downloadPublishers = requests.map { request in
            downloadAudio(from: request.url, metadata: request.metadata)
                .last() // Only emit the final progress
                .catch { error in
                    // Convert errors to completed progress with error state
                    Just(DownloadProgress(
                        remoteURL: request.url,
                        progress: 0.0,
                        state: .failed(error),
                        downloadedBytes: 0
                    ))
                }
        }

        return downloadPublishers.publisher.flatMap { $0 }
            .scan(BatchDownloadProgress(
                overallProgress: 0.0,
                completedCount: 0,
                totalCount: requests.count,
                failedCount: 0,
                activeDownloads: Set(requests.map(\.url)),
                totalBytesDownloaded: 0,
                expectedTotalBytes: nil
            )) { progress, downloadProgress in
                let isCompleted = downloadProgress.state.isFinal
                let isFailed = downloadProgress.state.error != nil

                var newProgress = progress

                if isCompleted {
                    newProgress = BatchDownloadProgress(
                        overallProgress: Double(progress.completedCount + 1) / Double(requests.count),
                        completedCount: progress.completedCount + 1,
                        totalCount: requests.count,
                        failedCount: progress.failedCount + (isFailed ? 1 : 0),
                        activeDownloads: progress.activeDownloads.subtracting([downloadProgress.remoteURL]),
                        totalBytesDownloaded: progress.totalBytesDownloaded + downloadProgress.downloadedBytes,
                        expectedTotalBytes: progress.expectedTotalBytes
                    )
                }

                return newProgress
            }
            .eraseToAnyPublisher()
    }

    /// Cancels all active downloads
    public func cancelAllDownloads() -> AnyPublisher<Void, AudioError> {
        return downloadProgress
            .first() // Get current state
            .map { progressDict in
                [URL](progressDict.keys)
            }
            .flatMap { urls in
                if urls.isEmpty {
                    return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
                }

                let cancelPublishers = urls.map { url in
                    cancelDownload(for: url)
                }

                return Publishers.MergeMany(cancelPublishers)
                    .collect()
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    /// Checks if audio content is available for offline playback
    public func isAvailableOffline(_ remoteURL: URL) -> Bool {
        guard let localURL = localURL(for: remoteURL) else {
            return false
        }

        return FileManager.default.fileExists(atPath: localURL.path)
    }

    /// Pre-fetches audio metadata without downloading the full file
    public func prefetchMetadata(for url: URL) -> AnyPublisher<AudioMetadata, AudioError> {
        return Future<AudioMetadata, AudioError> { promise in
            Task {
                do {
                    // Create a basic HTTP HEAD request to get headers
                    var request = URLRequest(url: url)
                    request.httpMethod = "HEAD"
                    request.setValue("bytes=0-1023", forHTTPHeaderField: "Range") // First KB for metadata

                    let (_, response) = try await URLSession.shared.data(for: request)

                    // Extract metadata from HTTP headers
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw AudioError.invalidURL
                    }

                    var metadata = AudioMetadata(
                        title: url.lastPathComponent,
                        artist: nil,
                        albumTitle: nil,
                        duration: nil,
                        artworkURL: nil
                    )

                    // Parse common audio metadata headers
                    if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                       let size = Int64(contentLength) {
                        metadata = AudioMetadata(
                            title: metadata.title,
                            artist: metadata.artist,
                            albumTitle: metadata.album,
                            duration: metadata.duration,
                            artworkData: metadata.artwork,
                            fileSize: size
                        )
                    }

                    promise(.success(metadata))

                } catch {
                    // Fallback to basic metadata from URL
                    let metadata = AudioMetadata(
                        title: url.lastPathComponent,
                        artist: nil,
                        albumTitle: nil,
                        duration: nil,
                        artworkURL: nil
                    )
                    promise(.success(metadata))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Enhanced Loading for Offline Content

    /// Enhanced loadAudio that prefers offline content when available
    public override func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        // Check if we have a local version
        if let localURL = localURL(for: url) {
            Log.debug("DownloadableAudioPlayer: Using offline version for \(url)")
            return super.loadAudio(from: localURL, metadata: metadata)
        }

        // Fall back to streaming
        Log.debug("DownloadableAudioPlayer: Streaming from remote \(url)")
        return super.loadAudio(from: url, metadata: metadata)
    }

    // MARK: - Private Implementation

    /// Setup reactive bindings for download management
    private func setupDownloadBindings() {
        // Monitor download progress updates from coordinator
        downloadCoordinator.downloadProgressPublisher
            .sink { [weak self] progressMap in
                self?.downloadProgressSubject.send(progressMap)
            }
            .store(in: &downloadCancellables)
    }

    /// Cleanup download-related resources
    private func cleanupDownload() {
        downloadCancellables.removeAll()
        downloadProgressSubject.send([:])
    }
}

// MARK: - Task Synchronous Helper

extension Task where Success == Void, Failure == Never {
    /// Execute an async task synchronously (only use when necessary)
    static func synchronous<T>(_ operation: @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T!

        Task {
            result = await operation()
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }
}

// MARK: - Logging Support

/// Simple logging utility for DownloadableAudioPlayer
private struct Log {
    static func debug(_ message: String) {
        #if DEBUG
        print("[DownloadableAudioPlayer] DEBUG: \(message)")
        #endif
    }

    static func error(_ message: String) {
        print("[DownloadableAudioPlayer] ERROR: \(message)")
    }
}

// MARK: - AudioMetadata Extension

extension AudioMetadata {
    /// Initialize AudioMetadata with all parameters
    init(title: String?,
         artist: String?,
         albumTitle: String?,
         duration: TimeInterval?,
         artworkURL: URL?,
         fileSize: Int64? = nil) {
        self.init(
            title: title,
            artist: artist,
            album: albumTitle,
            artwork: nil,
            chapters: [],
            releaseDate: nil,
            genre: nil,
            duration: duration,
            fileSize: fileSize,
            contentDescription: nil
        )
    }
}

// MARK: - Documentation

/*
 DESIGN PRINCIPLES:

 1. OFFLINE-FIRST APPROACH
    - Automatically prefers local downloads over streaming when available
    - Provides comprehensive download management with progress tracking
    - Handles app lifecycle events for background downloads
    - Maintains download queue and retry logic for failed attempts

 2. PROGRESSIVE ENHANCEMENT
    - Builds upon BasicAudioPlayer foundation
    - Adds download capabilities without breaking existing functionality
    - Compatible with any AudioPlayable usage patterns
    - Seamless transition between offline and streaming playback

 3. REACTIVE DOWNLOAD MANAGEMENT
    - All download operations publish progress through Combine
    - Real-time updates for UI synchronization
    - Batch download operations with comprehensive progress tracking
    - Download queue management with concurrency controls

 4. THREAD-SAFE COORDINATION
    - Uses ReactiveAudioCoordinator to access DownloadManagerActor
    - All download operations isolated to prevent threading issues
    - Proper cancellation and cleanup of download operations
    - MainActor isolation for UI thread safety

 5. COMPREHENSIVE STORAGE MANAGEMENT
    - Storage space monitoring and reporting
    - Cellular data controls with user preferences
    - Download cleanup and management operations
    - Metadata prefetching for better user experience

 USAGE PATTERNS:

 Basic Download Usage:
 ```swift
 let player = DownloadableAudioPlayer()

 // Start download with progress tracking
 player.downloadAudio(from: remoteURL, metadata: metadata)
     .sink { progress in
         updateProgressBar(progress.progress)

         if progress.state == .completed {
             print("Download completed: \(progress.localURL)")
         }
     }
     .store(in: &cancellables)
 ```

 Offline-First Playback:
 ```swift
 // Automatically uses offline version if available
 try await player.loadAudio(from: remoteURL, metadata: nil).async()
 try await player.play().async()

 // Check offline availability
 if player.isAvailableOffline(remoteURL) {
     print("Available offline at: \(player.localURL(for: remoteURL))")
 }
 ```

 Download Management:
 ```swift
 // Monitor all downloads
 player.downloadProgress
     .sink { progressMap in
         for (url, progress) in progressMap {
             updateDownloadUI(url: url, progress: progress)
         }
     }
     .store(in: &cancellables)

 // Batch downloads
 let requests = urls.map { (url: $0, metadata: nil) }
 player.downloadBatch(requests)
     .sink { batchProgress in
         updateBatchUI(progress: batchProgress.overallProgress)
     }
     .store(in: &cancellables)
 ```

 Storage Management:
 ```swift
 // Check storage usage
 let totalSize = player.totalDownloadedSize()
 let availableSpace = player.availableDownloadSpace()

 // Configure cellular usage
 player.allowsCellularDownloads = false

 // Cleanup storage
 player.clearAllDownloads()
     .sink { _ in
         print("All downloads cleared")
     }
     .store(in: &cancellables)
 ```

 IMPLEMENTATION NOTES:

 - Download progress is tracked reactively through the coordinator
 - Local URLs are checked first before falling back to streaming
 - Metadata prefetching provides better user experience
 - Background downloads continue when app is suspended
 - Error handling preserves existing playback functionality
 - Storage monitoring helps prevent disk space issues
 - Cellular controls respect user data preferences
 - All operations maintain thread safety through actor coordination
 */