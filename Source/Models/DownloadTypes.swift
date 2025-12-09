// DownloadTypes.swift - Download progress and state definitions
// Swift 6 Sendable compliant types for download management

import Foundation

/// Represents the progress and state of a background download operation
/// This struct is Sendable for use across concurrency boundaries
public struct DownloadProgress: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier for tracking this download
    public let id: UUID

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

    /// Download start time
    public let startTime: Date

    /// Download completion or failure time
    public let endTime: Date?

    /// Associated metadata for this download
    public let metadata: AudioMetadata?

    /// Error information if download failed
    public let error: AudioError?

    /// Creates new download progress information
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - remoteURL: Source URL for download
    ///   - localURL: Destination path when complete
    ///   - progress: Download progress (0.0 to 1.0)
    ///   - state: Current download state
    ///   - totalBytes: Expected download size
    ///   - downloadedBytes: Current downloaded amount
    ///   - startTime: When download began
    ///   - endTime: When download completed or failed
    ///   - metadata: Associated audio metadata
    ///   - error: Error information if failed
    public init(
        id: UUID = UUID(),
        remoteURL: URL,
        localURL: URL? = nil,
        progress: Double,
        state: DownloadState,
        totalBytes: Int64? = nil,
        downloadedBytes: Int64,
        startTime: Date = Date(),
        endTime: Date? = nil,
        metadata: AudioMetadata? = nil,
        error: AudioError? = nil
    ) {
        self.id = id
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.progress = max(0.0, min(1.0, progress)) // Clamp to valid range
        self.state = state
        self.totalBytes = totalBytes
        self.downloadedBytes = max(0, downloadedBytes)
        self.startTime = startTime
        self.endTime = endTime
        self.metadata = metadata
        self.error = error
    }

    /// Creates a copy with updated values
    /// - Parameters:
    ///   - localURL: Updated local URL
    ///   - progress: Updated progress
    ///   - state: Updated state
    ///   - totalBytes: Updated total bytes
    ///   - downloadedBytes: Updated downloaded bytes
    ///   - endTime: Updated end time
    ///   - error: Updated error
    /// - Returns: New progress instance with updated values
    public func updated(
        localURL: URL? = nil,
        progress: Double? = nil,
        state: DownloadState? = nil,
        totalBytes: Int64? = nil,
        downloadedBytes: Int64? = nil,
        endTime: Date? = nil,
        error: AudioError? = nil
    ) -> DownloadProgress {
        DownloadProgress(
            id: self.id,
            remoteURL: self.remoteURL,
            localURL: localURL ?? self.localURL,
            progress: progress ?? self.progress,
            state: state ?? self.state,
            totalBytes: totalBytes ?? self.totalBytes,
            downloadedBytes: downloadedBytes ?? self.downloadedBytes,
            startTime: self.startTime,
            endTime: endTime ?? self.endTime,
            metadata: self.metadata,
            error: error ?? self.error
        )
    }

    /// Download speed in bytes per second (if calculable)
    public var downloadSpeed: Double? {
        let elapsed = endTime?.timeIntervalSince(startTime) ?? Date().timeIntervalSince(startTime)
        guard elapsed > 0, downloadedBytes > 0 else { return nil }
        return Double(downloadedBytes) / elapsed
    }

    /// Estimated time remaining in seconds (if calculable)
    public var estimatedTimeRemaining: TimeInterval? {
        guard let speed = downloadSpeed,
              let totalBytes = totalBytes,
              speed > 0,
              downloadedBytes < totalBytes else { return nil }
        let remainingBytes = totalBytes - downloadedBytes
        return Double(remainingBytes) / speed
    }

    /// Formatted download speed string (e.g., "1.2 MB/s")
    public var formattedDownloadSpeed: String? {
        guard let speed = downloadSpeed else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file) + "/s"
    }

    /// Formatted progress percentage string (e.g., "75.5%")
    public var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }

    /// Formatted file size string (e.g., "12.5 MB / 50.0 MB")
    public var formattedFileSize: String {
        let downloadedString = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .file)
        if let totalBytes = totalBytes {
            let totalString = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
            return "\(downloadedString) / \(totalString)"
        } else {
            return downloadedString
        }
    }
}

// MARK: - DownloadState

/// Enumeration of possible download states
/// This enum is Sendable for use across concurrency boundaries
public enum DownloadState: Sendable, Equatable, Hashable, CaseIterable {
    /// Download is queued but not yet started
    case pending

    /// Download is actively in progress
    case downloading

    /// Download is temporarily paused
    case paused

    /// Download completed successfully
    case completed

    /// Download failed with error
    case failed(AudioError)

    /// Download was cancelled by user
    case cancelled

    /// Whether the download is currently active
    public var isActive: Bool {
        switch self {
        case .downloading:
            return true
        case .pending, .paused, .completed, .failed, .cancelled:
            return false
        }
    }

    /// Whether the download can be resumed
    public var canResume: Bool {
        switch self {
        case .paused, .failed:
            return true
        case .pending, .downloading, .completed, .cancelled:
            return false
        }
    }

    /// Whether the download can be cancelled
    public var canCancel: Bool {
        switch self {
        case .pending, .downloading, .paused:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    /// Whether the download is in a final state
    public var isFinal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .downloading, .paused:
            return false
        }
    }

    /// Get the error if state is failed, nil otherwise
    public var error: AudioError? {
        if case .failed(let audioError) = self {
            return audioError
        }
        return nil
    }
}

// MARK: - DownloadInfo

/// Information about a completed download for management and display
/// This struct is Sendable for use across concurrency boundaries
public struct DownloadInfo: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier
    public let id: UUID

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

    /// Download duration (how long it took)
    public let downloadDuration: TimeInterval?

    /// Creates new download information
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - remoteURL: Original source URL
    ///   - localURL: Local file location
    ///   - downloadDate: When download completed
    ///   - metadata: Associated audio metadata
    ///   - fileSize: File size in bytes
    ///   - downloadDuration: How long download took
    public init(
        id: UUID = UUID(),
        remoteURL: URL,
        localURL: URL,
        downloadDate: Date,
        metadata: AudioMetadata? = nil,
        fileSize: Int64,
        downloadDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.downloadDate = downloadDate
        self.metadata = metadata
        self.fileSize = fileSize
        self.downloadDuration = downloadDuration
    }

    /// Display name for this download
    public var displayName: String {
        return metadata?.displayTitle ?? remoteURL.lastPathComponent
    }

    /// Formatted file size string
    public var formattedFileSize: String {
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Whether the local file still exists
    public var fileExists: Bool {
        return FileManager.default.fileExists(atPath: localURL.path)
    }
}

// MARK: - CustomStringConvertible

extension DownloadProgress: CustomStringConvertible {
    public var description: String {
        let name = metadata?.displayTitle ?? remoteURL.lastPathComponent
        return "DownloadProgress[\(name): \(state) \(formattedProgress)]"
    }
}

extension DownloadState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .pending:
            return "pending"
        case .downloading:
            return "downloading"
        case .paused:
            return "paused"
        case .completed:
            return "completed"
        case .failed(let error):
            return "failed(\(error.localizedDescription))"
        case .cancelled:
            return "cancelled"
        }
    }
}

extension DownloadInfo: CustomStringConvertible {
    public var description: String {
        return "DownloadInfo[\(displayName): \(formattedFileSize)]"
    }
}

// MARK: - Equatable Implementation for DownloadState

extension DownloadState {
    public static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
        switch (lhs, rhs) {
        case (.pending, .pending), (.downloading, .downloading), (.paused, .paused),
             (.completed, .completed), (.cancelled, .cancelled):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Hashable Implementation

extension DownloadState {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .pending:
            hasher.combine("pending")
        case .downloading:
            hasher.combine("downloading")
        case .paused:
            hasher.combine("paused")
        case .completed:
            hasher.combine("completed")
        case .failed(let error):
            hasher.combine("failed")
            hasher.combine(error)
        case .cancelled:
            hasher.combine("cancelled")
        }
    }
}

// MARK: - CaseIterable Implementation

extension DownloadState {
    public static var allCases: [DownloadState] {
        return [.pending, .downloading, .paused, .completed, .cancelled]
        // Note: .failed case excluded as it requires an associated value
    }
}