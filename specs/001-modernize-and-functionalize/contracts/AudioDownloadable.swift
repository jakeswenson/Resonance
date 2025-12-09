// AudioDownloadable.swift - Protocol for Background Download Capabilities
// Contract Test: Must verify download progress tracking and local file management

import Foundation
import Combine

/// Protocol for background audio downloading functionality
/// Enables offline podcast listening with progress tracking
public protocol AudioDownloadable {

    /// Start downloading audio for offline playback
    /// - Parameter url: Remote audio URL to download
    /// - Parameter metadata: Optional metadata to store with download
    /// - Returns: Publisher that emits download progress and completes with local URL
    func downloadAudio(from url: URL,
                      metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError>

    /// Cancel an active download
    /// - Parameter url: Remote URL of download to cancel
    /// - Returns: Publisher that completes when cancellation is confirmed
    func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError>

    /// Check if audio is already downloaded
    /// - Parameter url: Remote URL to check
    /// - Returns: Local URL if downloaded, nil otherwise
    func localURL(for remoteURL: URL) -> URL?

    /// Delete downloaded audio file
    /// - Parameter localURL: Local file URL to delete
    /// - Returns: Publisher that completes when deletion finishes
    func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError>

    /// Get all downloaded audio files
    /// - Returns: Array of download information
    func getAllDownloads() -> [DownloadInfo]

    /// Publisher for active download progress updates
    var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> { get }

    /// Whether cellular data should be used for downloads
    var allowsCellularDownloads: Bool { get set }
}

// MARK: - Supporting Types

public struct DownloadProgress {
    /// Remote URL being downloaded
    public let remoteURL: URL

    /// Local destination URL (available when complete)
    public let localURL: URL?

    /// Download progress (0.0 to 1.0)
    public let progress: Double

    /// Current download state
    public let state: DownloadState

    /// Total bytes to download (if known)
    public let totalBytes: Int64?

    /// Bytes downloaded so far
    public let downloadedBytes: Int64

    public init(remoteURL: URL,
                localURL: URL? = nil,
                progress: Double,
                state: DownloadState,
                totalBytes: Int64? = nil,
                downloadedBytes: Int64) {
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.progress = progress
        self.state = state
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
    }
}

public enum DownloadState: Equatable {
    case pending
    case downloading
    case paused
    case completed
    case failed(AudioError)
    case cancelled
}

public struct DownloadInfo {
    /// Original remote URL
    public let remoteURL: URL

    /// Local file URL
    public let localURL: URL

    /// Download completion date
    public let downloadDate: Date

    /// Associated metadata
    public let metadata: AudioMetadata?

    /// File size in bytes
    public let fileSize: Int64

    public init(remoteURL: URL,
                localURL: URL,
                downloadDate: Date,
                metadata: AudioMetadata? = nil,
                fileSize: Int64) {
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.downloadDate = downloadDate
        self.metadata = metadata
        self.fileSize = fileSize
    }
}