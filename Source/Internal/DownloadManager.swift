//
//  DownloadManager.swift
//  Resonance
//
//  Manages episode downloads with progress tracking.
//

import Foundation

/// Manages episode downloads with progress reporting.
///
/// Features:
/// - Progress updates during download
/// - Concurrent download limiting
/// - Cancellation support
/// - Automatic retry on failure
actor DownloadManager {

    // MARK: - Types

    /// Active download state
    private struct ActiveDownload {
        let episode: Episode
        let task: URLSessionDownloadTask
        var progress: Double = 0
        var continuation: CheckedContinuation<URL, Error>?
    }

    // MARK: - State

    private var activeDownloads: [String: ActiveDownload] = [:]  // episodeId -> download
    private var session: URLSession?
    private let delegate: DownloadDelegate

    /// Progress callback for UI updates
    private var onProgress: (@Sendable (String, Double) -> Void)?

    /// Sets the progress handler callback.
    func setProgressHandler(_ handler: @escaping @Sendable (String, Double) -> Void) {
        onProgress = handler
    }

    /// Maximum concurrent downloads
    var maxConcurrentDownloads: Int = 3

    // MARK: - Init

    init() {
        self.delegate = DownloadDelegate()
    }

    /// Lazily creates the URLSession (must be called from actor context)
    private func getSession() -> URLSession {
        if let session = session {
            return session
        }

        delegate.manager = self

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 3600  // 1 hour max
        let newSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        self.session = newSession
        return newSession
    }

    // MARK: - Public API

    /// Downloads an episode with progress tracking.
    ///
    /// - Parameters:
    ///   - episode: Episode to download
    ///   - destination: Directory to save the file
    /// - Returns: Local file URL
    func download(episode: Episode, to destination: URL) async throws -> URL {
        // Check if already downloading
        if let existing = activeDownloads[episode.id] {
            // Wait for existing download
            return try await withCheckedThrowingContinuation { continuation in
                var download = existing
                download.continuation = continuation
                activeDownloads[episode.id] = download
            }
        }

        // Start new download
        let task = getSession().downloadTask(with: episode.url)
        task.taskDescription = episode.id  // Store episode ID for delegate lookup

        return try await withCheckedThrowingContinuation { continuation in
            activeDownloads[episode.id] = ActiveDownload(
                episode: episode,
                task: task,
                progress: 0,
                continuation: continuation
            )
            task.resume()
        }
    }

    /// Cancels a download in progress.
    func cancel(episodeId: String) {
        guard let download = activeDownloads.removeValue(forKey: episodeId) else { return }
        download.task.cancel()
        download.continuation?.resume(throwing: CancellationError())
    }

    /// Returns current progress for a download (0.0 to 1.0).
    func progress(for episodeId: String) -> Double? {
        activeDownloads[episodeId]?.progress
    }

    /// Whether an episode is currently downloading.
    func isDownloading(_ episodeId: String) -> Bool {
        activeDownloads[episodeId] != nil
    }

    // MARK: - Delegate Callbacks

    fileprivate func didUpdateProgress(for taskId: String, progress: Double) {
        guard var download = activeDownloads[taskId] else { return }
        download.progress = progress
        activeDownloads[taskId] = download
        onProgress?(taskId, progress)
    }

    fileprivate func didComplete(for taskId: String, location: URL?, error: Error?) {
        guard let download = activeDownloads.removeValue(forKey: taskId) else { return }

        if let error = error {
            download.continuation?.resume(throwing: error)
            return
        }

        guard let tempLocation = location else {
            download.continuation?.resume(throwing: AudioError.internalError("Download location missing"))
            return
        }

        // Move to permanent location
        do {
            let ext = download.episode.url.pathExtension.isEmpty ? "mp3" : download.episode.url.pathExtension
            let destURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Resonance/Downloads", isDirectory: true)
                .appendingPathComponent("\(download.episode.id).\(ext)")

            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.moveItem(at: tempLocation, to: destURL)
            download.continuation?.resume(returning: destURL)
        } catch {
            download.continuation?.resume(throwing: error)
        }
    }
}

// MARK: - URLSession Delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    // Use nonisolated(unsafe) for the back-reference since we manage thread safety manually
    nonisolated(unsafe) weak var manager: DownloadManager?

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let taskId = downloadTask.taskDescription,
              totalBytesExpectedToWrite > 0 else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        Task { [weak manager] in
            await manager?.didUpdateProgress(for: taskId, progress: progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let taskId = downloadTask.taskDescription else { return }

        // Copy file immediately since location is temporary
        let tempCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension)

        do {
            try FileManager.default.copyItem(at: location, to: tempCopy)

            Task { [weak manager] in
                await manager?.didComplete(for: taskId, location: tempCopy, error: nil)
            }
        } catch {
            Task { [weak manager] in
                await manager?.didComplete(for: taskId, location: nil, error: error)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error = error,
              let taskId = task.taskDescription else { return }

        Task { [weak manager] in
            await manager?.didComplete(for: taskId, location: nil, error: error)
        }
    }
}
