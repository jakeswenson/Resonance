// AudioDownloadable.swift - Protocol for background audio download capabilities
// Provides offline-first audio experiences with background downloading

import Foundation
import Combine

/// Protocol defining background download and offline capabilities for audio content.
/// Enables offline-first audio experiences with progress tracking and download management.
///
/// This protocol provides:
/// - Background download management (start, pause, cancel, resume)
/// - Real-time download progress tracking via Combine publishers
/// - Downloaded content management and cleanup
/// - Offline playback capabilities
/// - Network usage controls (cellular data management)
/// - Swift 6 Sendable compliance for concurrent operations
///
/// ## Usage Example
/// ```swift
/// // Start a background download
/// downloader.downloadAudio(from: remoteURL, metadata: audioMetadata)
///     .sink(
///         receiveCompletion: { completion in
///             // Handle completion or errors
///         },
///         receiveValue: { progress in
///             // Update UI with download progress
///             updateProgressBar(progress.progress)
///         }
///     )
///     .store(in: &cancellables)
///
/// // Track all active downloads
/// downloader.downloadProgress
///     .sink { allDownloads in
///         // Update UI with all download states
///         updateDownloadsList(allDownloads)
///     }
///     .store(in: &cancellables)
/// ```
public protocol AudioDownloadable: Sendable {

    // MARK: - Download Management

    /// Downloads audio from a remote URL with optional metadata.
    /// The download runs in the background and can continue even when the app is suspended.
    ///
    /// - Parameters:
    ///   - url: Remote URL to download from
    ///   - metadata: Optional audio metadata to associate with the download
    /// - Returns: Publisher that emits download progress updates and completes when finished
    /// - Note: The publisher will emit multiple DownloadProgress values as the download progresses
    func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError>

    /// Cancels an active download for the specified URL.
    /// This immediately stops the download and removes any temporary files.
    ///
    /// - Parameter url: Remote URL of the download to cancel
    /// - Returns: Publisher that completes when the cancellation is finished
    /// - Note: Cancelling a completed download has no effect
    func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError>

    /// Pauses an active download for the specified URL.
    /// The download can be resumed later using resumeDownload(for:).
    ///
    /// - Parameter url: Remote URL of the download to pause
    /// - Returns: Publisher that completes when the download is paused
    /// - Note: Pausing a non-active download has no effect
    func pauseDownload(for url: URL) -> AnyPublisher<Void, AudioError>

    /// Resumes a paused download for the specified URL.
    /// This continues the download from where it was paused.
    ///
    /// - Parameter url: Remote URL of the download to resume
    /// - Returns: Publisher that emits progress updates as the download continues
    /// - Note: Resuming a non-paused download has no effect
    func resumeDownload(for url: URL) -> AnyPublisher<DownloadProgress, AudioError>

    // MARK: - Content Management

    /// Returns the local URL for a downloaded audio file, if it exists.
    /// This can be used to check if content is available offline.
    ///
    /// - Parameter remoteURL: The original remote URL
    /// - Returns: Local file URL if downloaded, nil otherwise
    /// - Note: This only returns URLs for completed downloads
    func localURL(for remoteURL: URL) -> URL?

    /// Deletes a downloaded audio file from local storage.
    /// This permanently removes the file and cannot be undone.
    ///
    /// - Parameter localURL: Local file URL to delete
    /// - Returns: Publisher that completes when the file is deleted
    /// - Note: Attempting to delete a non-existent file will complete successfully
    func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError>

    /// Returns information about all downloaded audio files.
    /// This includes metadata, file sizes, and download dates.
    ///
    /// - Returns: Array of download information for all locally stored audio files
    /// - Note: The array is sorted by download date (most recent first)
    func getAllDownloads() -> [DownloadInfo]

    /// Clears all downloaded audio content and associated metadata.
    /// This is useful for implementing storage management features.
    ///
    /// - Returns: Publisher that completes when all downloads are cleared
    /// - Warning: This operation cannot be undone
    func clearAllDownloads() -> AnyPublisher<Void, AudioError>

    // MARK: - Progress Tracking

    /// Publisher that emits real-time download progress for all active downloads.
    /// The dictionary keys are remote URLs, values are current progress information.
    ///
    /// This publisher:
    /// - Emits immediately with current state when subscribed
    /// - Updates in real-time as downloads progress
    /// - Removes entries when downloads complete or are cancelled
    /// - Is thread-safe and can be observed from any queue
    ///
    /// ## Usage Example
    /// ```swift
    /// downloader.downloadProgress
    ///     .sink { progressDict in
    ///         for (url, progress) in progressDict {
    ///             updateProgressUI(for: url, progress: progress)
    ///         }
    ///     }
    ///     .store(in: &cancellables)
    /// ```
    var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> { get }

    // MARK: - Network Controls

    /// Controls whether downloads are allowed over cellular data connections.
    /// When false, downloads will pause when on cellular and resume on WiFi.
    ///
    /// Default value should be true for backwards compatibility.
    /// Apps should provide user controls for this setting.
    var allowsCellularDownloads: Bool { get set }

    // MARK: - Storage Management

    /// Returns the total size of all downloaded audio content in bytes.
    /// This is useful for implementing storage usage displays and cleanup features.
    ///
    /// - Returns: Total bytes used by downloaded audio files
    func totalDownloadedSize() -> Int64

    /// Returns available storage space for downloads in bytes.
    /// This considers both device storage and any app-specific limits.
    ///
    /// - Returns: Available bytes for new downloads, or nil if unlimited
    func availableDownloadSpace() -> Int64?

    // MARK: - Batch Operations

    /// Downloads multiple audio files concurrently with shared progress tracking.
    /// This is more efficient than starting individual downloads.
    ///
    /// - Parameter requests: Array of download requests (URL + metadata pairs)
    /// - Returns: Publisher that emits overall batch progress
    /// - Note: Individual file progress is still available via downloadProgress publisher
    func downloadBatch(_ requests: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<BatchDownloadProgress, AudioError>

    /// Cancels all active downloads.
    /// This is useful for implementing "cancel all" features.
    ///
    /// - Returns: Publisher that completes when all downloads are cancelled
    func cancelAllDownloads() -> AnyPublisher<Void, AudioError>

    // MARK: - Offline Capabilities

    /// Checks if audio content is available for offline playback.
    /// This verifies both that the file exists and is playable.
    ///
    /// - Parameter remoteURL: Original remote URL to check
    /// - Returns: True if content is available offline and playable
    func isAvailableOffline(_ remoteURL: URL) -> Bool

    /// Pre-fetches audio metadata without downloading the full file.
    /// This is useful for displaying track information before download.
    ///
    /// - Parameter url: Remote URL to fetch metadata from
    /// - Returns: Publisher that emits the extracted metadata
    func prefetchMetadata(for url: URL) -> AnyPublisher<AudioMetadata, AudioError>
}

// MARK: - Supporting Types

/// Represents progress for batch download operations
public struct BatchDownloadProgress: Sendable, Equatable {
    /// Overall progress across all files (0.0 to 1.0)
    public let overallProgress: Double

    /// Number of files completed
    public let completedCount: Int

    /// Total number of files in the batch
    public let totalCount: Int

    /// Number of files that failed to download
    public let failedCount: Int

    /// URLs of files that are currently downloading
    public let activeDownloads: Set<URL>

    /// Total bytes downloaded across all files
    public let totalBytesDownloaded: Int64

    /// Expected total bytes for the entire batch (if known)
    public let expectedTotalBytes: Int64?

    public init(
        overallProgress: Double,
        completedCount: Int,
        totalCount: Int,
        failedCount: Int,
        activeDownloads: Set<URL>,
        totalBytesDownloaded: Int64,
        expectedTotalBytes: Int64?
    ) {
        self.overallProgress = max(0.0, min(1.0, overallProgress))
        self.completedCount = completedCount
        self.totalCount = totalCount
        self.failedCount = failedCount
        self.activeDownloads = activeDownloads
        self.totalBytesDownloaded = totalBytesDownloaded
        self.expectedTotalBytes = expectedTotalBytes
    }
}

// MARK: - Default Implementations

public extension AudioDownloadable {

    /// Default implementation for pause functionality
    func pauseDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        // Default implementation cancels the download
        // Concrete implementations can override for true pause/resume support
        return cancelDownload(for: url)
    }

    /// Default implementation for resume functionality
    func resumeDownload(for url: URL) -> AnyPublisher<DownloadProgress, AudioError> {
        // Default implementation starts a new download
        // Concrete implementations can override for true pause/resume support
        return downloadAudio(from: url, metadata: nil)
    }

    /// Default implementation for clearing all downloads
    func clearAllDownloads() -> AnyPublisher<Void, AudioError> {
        let allDownloads = getAllDownloads()

        if allDownloads.isEmpty {
            return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
        }

        let deletePublishers = allDownloads.map { downloadInfo in
            deleteDownload(at: downloadInfo.localURL)
        }

        return deletePublishers.publisher
            .flatMap { $0 }
            .collect()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Default implementation for total downloaded size
    func totalDownloadedSize() -> Int64 {
        return getAllDownloads().reduce(0) { total, download in
            total + download.fileSize
        }
    }

    /// Default implementation for available space (unlimited)
    func availableDownloadSpace() -> Int64? {
        return nil // Unlimited by default
    }

    /// Default implementation for batch downloads
    func downloadBatch(_ requests: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<BatchDownloadProgress, AudioError> {
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

        return downloadPublishers.publisher
            .flatMap { $0 }
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
            .setFailureType(to: AudioError.self)
            .eraseToAnyPublisher()
    }

    /// Default implementation for cancelling all downloads
    func cancelAllDownloads() -> AnyPublisher<Void, AudioError> {
        return downloadProgress
            .first() // Get current state
            .map { progressDict -> [URL] in
                Array(progressDict.keys)
            }
            .flatMap { urls in
                if urls.isEmpty {
                    return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
                }

                let cancelPublishers = urls.map { url in
                    cancelDownload(for: url)
                }

                return cancelPublishers.publisher.flatMap { $0 }
                    .collect()
                    .map { _ in () }
                    .eraseToAnyPublisher()
            }
            .eraseToAnyPublisher()
    }

    /// Default implementation for offline availability check
    func isAvailableOffline(_ remoteURL: URL) -> Bool {
        guard let localURL = localURL(for: remoteURL) else {
            return false
        }

        return FileManager.default.fileExists(atPath: localURL.path)
    }

    /// Default implementation for metadata prefetching
    func prefetchMetadata(for url: URL) -> AnyPublisher<AudioMetadata, AudioError> {
        // Default implementation returns minimal metadata from URL
        let metadata = AudioMetadata(
            title: url.lastPathComponent,
            artist: nil,
            albumTitle: nil,
            duration: nil,
            artworkURL: nil
        )

        return Just(metadata)
            .setFailureType(to: AudioError.self)
            .eraseToAnyPublisher()
    }
}