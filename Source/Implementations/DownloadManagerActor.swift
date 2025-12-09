// DownloadManagerActor.swift - Thread-safe download management actor
// Provides background downloads with reactive progress tracking via Combine

import Foundation
import Combine
import Network

/// Thread-safe actor for managing concurrent background downloads
/// Isolates all download operations and file management to prevent threading issues
/// Provides reactive progress updates and handles app lifecycle events
@globalActor
public actor DownloadManagerActor {

    public static let shared = DownloadManagerActor()

    // MARK: - Private State

    /// Active download tasks indexed by remote URL
    private var activeTasks: [URL: URLSessionDownloadTask] = [:]

    /// Current download progress indexed by remote URL
    private var downloadProgressMap: [URL: DownloadProgress] = [:]

    /// Completed downloads indexed by remote URL
    private var completedDownloads: [URL: DownloadInfo] = [:]

    /// Progress subject for reactive updates
    private let progressSubject = CurrentValueSubject<[URL: DownloadProgress], Never>([:])

    /// Background URL session for downloads
    private let urlSession: URLSession

    /// File manager for local storage operations
    private let fileManager = FileManager.default

    /// Downloads directory URL
    private let downloadsDirectory: URL

    /// Network monitor for connectivity awareness
    private let networkMonitor = NWPathMonitor()

    /// Current network path
    private var currentNetworkPath: NWPath?

    /// Whether cellular downloads are allowed
    private var _allowsCellularDownloads: Bool = true

    /// Maximum concurrent downloads
    private let maxConcurrentDownloads: Int = 3

    /// Download queue for managing concurrency
    private var downloadQueue: [(url: URL, metadata: AudioMetadata?)] = []

    /// Currently active download count
    private var activeDownloadCount: Int = 0

    // MARK: - Initialization

    private init() {
        // Configure downloads directory
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.downloadsDirectory = documentsURL.appendingPathComponent("AudioDownloads", isDirectory: true)

        // Ensure downloads directory exists
        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true, attributes: nil)

        // Configure background URL session
        let config = URLSessionConfiguration.background(withIdentifier: "com.resonance.downloads")
        config.allowsCellularAccess = _allowsCellularDownloads
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true

        self.urlSession = URLSession(configuration: config, delegate: DownloadDelegate(), delegateQueue: nil)

        // Start network monitoring
        setupNetworkMonitoring()

        // Load existing downloads
        loadPersistedDownloads()
    }

    // MARK: - Public Interface

    /// Downloads audio from a remote URL with optional metadata
    /// - Parameters:
    ///   - url: Remote URL to download from
    ///   - metadata: Optional audio metadata to associate with the download
    /// - Returns: Publisher that emits download progress updates
    public func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError> {
        return Future<DownloadProgress, AudioError> { [weak self] promise in
            Task {
                await self?.startDownload(url: url, metadata: metadata, promise: promise)
            }
        }
        .flatMap { initialProgress in
            // Return a publisher that emits progress updates for this specific URL
            self.progressSubject
                .compactMap { progressMap in progressMap[url] }
                .prepend(initialProgress)
                .handleEvents(receiveCompletion: { _ in
                    // Clean up completed downloads from progress map
                    Task {
                        await self.cleanupCompletedDownload(url: url)
                    }
                })
        }
        .eraseToAnyPublisher()
    }

    /// Cancels an active download
    /// - Parameter url: Remote URL of the download to cancel
    /// - Returns: Publisher that completes when cancellation is finished
    public func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task {
                await self?.performCancelDownload(for: url, promise: promise)
            }
        }
        .eraseToAnyPublisher()
    }

    /// Pauses an active download
    /// - Parameter url: Remote URL of the download to pause
    /// - Returns: Publisher that completes when download is paused
    public func pauseDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task {
                await self?.performPauseDownload(for: url, promise: promise)
            }
        }
        .eraseToAnyPublisher()
    }

    /// Resumes a paused download
    /// - Parameter url: Remote URL of the download to resume
    /// - Returns: Publisher that emits progress updates as download continues
    public func resumeDownload(for url: URL) -> AnyPublisher<DownloadProgress, AudioError> {
        return Future<DownloadProgress, AudioError> { [weak self] promise in
            Task {
                await self?.performResumeDownload(for: url, promise: promise)
            }
        }
        .flatMap { initialProgress in
            // Return progress updates for this URL
            self.progressSubject
                .compactMap { progressMap in progressMap[url] }
                .prepend(initialProgress)
        }
        .eraseToAnyPublisher()
    }

    /// Returns the local URL for a downloaded audio file
    /// - Parameter remoteURL: The original remote URL
    /// - Returns: Local file URL if downloaded, nil otherwise
    public func localURL(for remoteURL: URL) -> URL? {
        return completedDownloads[remoteURL]?.localURL
    }

    /// Deletes a downloaded audio file from local storage
    /// - Parameter localURL: Local file URL to delete
    /// - Returns: Publisher that completes when file is deleted
    public func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task {
                await self?.performDeleteDownload(at: localURL, promise: promise)
            }
        }
        .eraseToAnyPublisher()
    }

    /// Returns information about all downloaded audio files
    /// - Returns: Array of download information sorted by download date
    public func getAllDownloads() -> [DownloadInfo] {
        return Array(completedDownloads.values).sorted { $0.downloadDate > $1.downloadDate }
    }

    /// Publisher for real-time download progress updates
    public var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> {
        return progressSubject.eraseToAnyPublisher()
    }

    /// Controls whether downloads are allowed over cellular data
    public var allowsCellularDownloads: Bool {
        get { _allowsCellularDownloads }
        set {
            _allowsCellularDownloads = newValue
            urlSession.configuration.allowsCellularAccess = newValue
            updateDownloadsForNetworkChange()
        }
    }

    /// Returns total size of all downloaded content
    public func totalDownloadedSize() -> Int64 {
        return completedDownloads.values.reduce(0) { total, download in
            total + download.fileSize
        }
    }

    /// Returns available storage space for downloads
    public func availableDownloadSpace() -> Int64? {
        guard let attributes = try? fileManager.attributesOfFileSystem(forPath: downloadsDirectory.path),
              let freeSize = attributes[.systemFreeSize] as? Int64 else {
            return nil
        }
        return freeSize
    }

    // MARK: - Private Implementation

    /// Starts a new download or queues it if at max capacity
    private func startDownload(url: URL, metadata: AudioMetadata?, promise: @escaping (Result<DownloadProgress, AudioError>) -> Void) {
        // Check if already downloading or completed
        if activeTasks[url] != nil {
            let error = AudioError.internalError("Download already in progress for URL: \(url)")
            promise(.failure(error))
            return
        }

        if completedDownloads[url] != nil {
            let error = AudioError.internalError("File already downloaded for URL: \(url)")
            promise(.failure(error))
            return
        }

        // Create initial progress
        let initialProgress = DownloadProgress(
            remoteURL: url,
            progress: 0.0,
            state: .pending,
            downloadedBytes: 0,
            metadata: metadata
        )

        downloadProgressMap[url] = initialProgress
        progressSubject.send(downloadProgressMap)

        // Check if we can start immediately or need to queue
        if activeDownloadCount < maxConcurrentDownloads {
            executeDownload(url: url, metadata: metadata)
        } else {
            // Queue the download for later execution
            downloadQueue.append((url: url, metadata: metadata))
        }
        promise(.success(initialProgress))
    }

    /// Executes a download task
    private func executeDownload(url: URL, metadata: AudioMetadata?) {
        let task = urlSession.downloadTask(with: url)
        activeTasks[url] = task
        activeDownloadCount += 1

        // Update progress to downloading state
        if let progress = downloadProgressMap[url] {
            let updatedProgress = progress.updated(state: .downloading)
            downloadProgressMap[url] = updatedProgress
            progressSubject.send(downloadProgressMap)
        }

        task.resume()
    }

    /// Processes the next queued download if available
    private func processNextQueuedDownload() {
        guard !downloadQueue.isEmpty, activeDownloadCount < maxConcurrentDownloads else {
            return
        }

        let nextDownload = downloadQueue.removeFirst()
        executeDownload(url: nextDownload.url, metadata: nextDownload.metadata)
    }

    /// Cancels a download
    private func performCancelDownload(for url: URL, promise: @escaping (Result<Void, AudioError>) -> Void) {
        guard let task = activeTasks[url] else {
            // Remove from queue if present
            downloadQueue.removeAll { $0.url == url }

            // Remove from progress if present
            downloadProgressMap.removeValue(forKey: url)
            progressSubject.send(downloadProgressMap)

            promise(.success(()))
            return
        }

        task.cancel()
        activeTasks.removeValue(forKey: url)
        activeDownloadCount -= 1

        // Update progress
        if let progress = downloadProgressMap[url] {
            let cancelledProgress = progress.updated(state: .cancelled)
            downloadProgressMap[url] = cancelledProgress
            progressSubject.send(downloadProgressMap)
        }

        // Process next queued download
        processNextQueuedDownload()

        promise(.success(()))
    }

    /// Pauses a download
    private func performPauseDownload(for url: URL, promise: @escaping (Result<Void, AudioError>) -> Void) {
        guard let task = activeTasks[url] else {
            let error = AudioError.internalError("No active download found for URL: \(url)")
            promise(.failure(error))
            return
        }

        task.suspend()

        // Update progress
        if let progress = downloadProgressMap[url] {
            let pausedProgress = progress.updated(state: .paused)
            downloadProgressMap[url] = pausedProgress
            progressSubject.send(downloadProgressMap)
        }

        promise(.success(()))
    }

    /// Resumes a download
    private func performResumeDownload(for url: URL, promise: @escaping (Result<DownloadProgress, AudioError>) -> Void) {
        guard let task = activeTasks[url] else {
            // If no active task, start a new download
            startDownload(url: url, metadata: downloadProgressMap[url]?.metadata, promise: promise)
            return
        }

        task.resume()

        // Update progress
        if let progress = downloadProgressMap[url] {
            let resumedProgress = progress.updated(state: .downloading)
            downloadProgressMap[url] = resumedProgress
            progressSubject.send(downloadProgressMap)
            promise(.success(resumedProgress))
        } else {
            let error = AudioError.internalError("No progress found for URL: \(url)")
            promise(.failure(error))
        }
    }

    /// Deletes a local download
    private func performDeleteDownload(at localURL: URL, promise: @escaping (Result<Void, AudioError>) -> Void) {
        do {
            try fileManager.removeItem(at: localURL)

            // Remove from completed downloads
            let urlsToRemove = completedDownloads.compactMap { (key, value) in
                value.localURL == localURL ? key : nil
            }

            for url in urlsToRemove {
                completedDownloads.removeValue(forKey: url)
            }

            persistDownloads()
            promise(.success(()))
        } catch {
            let audioError = AudioError.internalError("Failed to delete file: \(error.localizedDescription)")
            promise(.failure(audioError))
        }
    }

    /// Cleans up completed download from progress map
    private func cleanupCompletedDownload(url: URL) {
        if let progress = downloadProgressMap[url], progress.state.isFinal {
            downloadProgressMap.removeValue(forKey: url)
            progressSubject.send(downloadProgressMap)
        }
    }

    /// Generates local URL for a remote URL
    private func generateLocalURL(for remoteURL: URL) -> URL {
        let filename = remoteURL.lastPathComponent.isEmpty ? "audio_\(UUID().uuidString)" : remoteURL.lastPathComponent
        return downloadsDirectory.appendingPathComponent(filename)
    }

    /// Sets up network monitoring
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handleNetworkPathUpdate(path)
            }
        }
        networkMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// Handles network path updates
    private func handleNetworkPathUpdate(_ path: NWPath) {
        let previousPath = currentNetworkPath
        currentNetworkPath = path

        // If we went from no connection to connection, resume downloads
        if previousPath?.status != .satisfied && path.status == .satisfied {
            updateDownloadsForNetworkChange()
        }
        // If we lost connection, pause downloads
        else if previousPath?.status == .satisfied && path.status != .satisfied {
            pauseAllDownloadsForNetworkLoss()
        }
        // If cellular setting changed, update downloads
        else if previousPath?.isExpensive != path.isExpensive {
            updateDownloadsForNetworkChange()
        }
    }

    /// Updates downloads based on network changes
    private func updateDownloadsForNetworkChange() {
        guard let path = currentNetworkPath, path.status == .satisfied else {
            return
        }

        // If on cellular and cellular downloads are disabled, pause downloads
        if path.isExpensive && !_allowsCellularDownloads {
            pauseAllDownloadsForCellular()
        }
        // If on WiFi or cellular downloads are allowed, resume paused downloads
        else if !path.isExpensive || _allowsCellularDownloads {
            resumePausedDownloads()
        }
    }

    /// Pauses all downloads due to network loss
    private func pauseAllDownloadsForNetworkLoss() {
        for (url, task) in activeTasks {
            task.suspend()

            if let progress = downloadProgressMap[url] {
                let pausedProgress = progress.updated(state: .paused)
                downloadProgressMap[url] = pausedProgress
            }
        }
        progressSubject.send(downloadProgressMap)
    }

    /// Pauses all downloads due to cellular restriction
    private func pauseAllDownloadsForCellular() {
        for (url, task) in activeTasks {
            task.suspend()

            if let progress = downloadProgressMap[url] {
                let pausedProgress = progress.updated(state: .paused)
                downloadProgressMap[url] = pausedProgress
            }
        }
        progressSubject.send(downloadProgressMap)
    }

    /// Resumes paused downloads when network allows
    private func resumePausedDownloads() {
        for (url, task) in activeTasks {
            if let progress = downloadProgressMap[url], progress.state == .paused {
                task.resume()

                let resumedProgress = progress.updated(state: .downloading)
                downloadProgressMap[url] = resumedProgress
            }
        }
        progressSubject.send(downloadProgressMap)
    }

    /// Persists download information to disk
    private func persistDownloads() {
        let persistenceURL = downloadsDirectory.appendingPathComponent("downloads.json")

        do {
            let data = try JSONEncoder().encode(Array(completedDownloads.values))
            try data.write(to: persistenceURL)
        } catch {
            print("Failed to persist downloads: \(error)")
        }
    }

    /// Loads persisted download information
    private func loadPersistedDownloads() {
        let persistenceURL = downloadsDirectory.appendingPathComponent("downloads.json")

        guard fileManager.fileExists(atPath: persistenceURL.path),
              let data = try? Data(contentsOf: persistenceURL),
              let downloads = try? JSONDecoder().decode([DownloadInfo].self, from: data) else {
            return
        }

        // Verify files still exist and update completed downloads
        for download in downloads {
            if fileManager.fileExists(atPath: download.localURL.path) {
                completedDownloads[download.remoteURL] = download
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

/// Delegate for handling download events
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let originalURL = downloadTask.originalRequest?.url else { return }

        Task {
            await DownloadManagerActor.shared.handleDownloadCompletion(
                originalURL: originalURL,
                temporaryURL: location,
                task: downloadTask
            )
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let originalURL = downloadTask.originalRequest?.url else { return }

        Task {
            await DownloadManagerActor.shared.handleDownloadProgress(
                originalURL: originalURL,
                bytesWritten: bytesWritten,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpected: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let originalURL = task.originalRequest?.url else { return }

        if let error = error {
            Task {
                await DownloadManagerActor.shared.handleDownloadError(
                    originalURL: originalURL,
                    error: error
                )
            }
        }
    }
}

// MARK: - DownloadManagerActor Extensions

extension DownloadManagerActor {

    /// Handles download completion
    func handleDownloadCompletion(originalURL: URL, temporaryURL: URL, task: URLSessionDownloadTask) {
        let localURL = generateLocalURL(for: originalURL)

        do {
            // Move file from temporary location to permanent location
            if fileManager.fileExists(atPath: localURL.path) {
                try fileManager.removeItem(at: localURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: localURL)

            // Get file size
            let attributes = try fileManager.attributesOfItem(atPath: localURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            // Update progress to completed
            if let progress = downloadProgressMap[originalURL] {
                let completedProgress = progress.updated(
                    localURL: localURL,
                    progress: 1.0,
                    state: .completed,
                    downloadedBytes: fileSize,
                    endTime: Date()
                )
                downloadProgressMap[originalURL] = completedProgress
                progressSubject.send(downloadProgressMap)

                // Create download info
                let downloadInfo = DownloadInfo(
                    id: progress.id,
                    remoteURL: originalURL,
                    localURL: localURL,
                    downloadDate: Date(),
                    metadata: progress.metadata,
                    fileSize: fileSize,
                    downloadDuration: Date().timeIntervalSince(progress.startTime)
                )

                completedDownloads[originalURL] = downloadInfo
                persistDownloads()
            }

            // Clean up
            activeTasks.removeValue(forKey: originalURL)
            activeDownloadCount -= 1

            // Process next queued download
            processNextQueuedDownload()

        } catch {
            handleDownloadError(originalURL: originalURL, error: error)
        }
    }

    /// Handles download progress updates
    func handleDownloadProgress(originalURL: URL, bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpected: Int64) {
        guard let progress = downloadProgressMap[originalURL] else { return }

        let downloadProgress = totalBytesExpected > 0 ? Double(totalBytesWritten) / Double(totalBytesExpected) : 0.0

        let updatedProgress = progress.updated(
            progress: downloadProgress,
            state: DownloadState.downloading,
            totalBytes: totalBytesExpected > 0 ? totalBytesExpected : nil,
            downloadedBytes: totalBytesWritten
        )

        downloadProgressMap[originalURL] = updatedProgress
        progressSubject.send(downloadProgressMap)
    }

    /// Handles download errors
    func handleDownloadError(originalURL: URL, error: Error) {
        let audioError = AudioError.networkFailure

        // Update progress with error
        if let progress = downloadProgressMap[originalURL] {
            let errorProgress = progress.updated(
                state: DownloadState.failed(audioError),
                endTime: Date(),
                error: audioError
            )
            downloadProgressMap[originalURL] = errorProgress
            progressSubject.send(downloadProgressMap)
        }

        // Clean up
        activeTasks.removeValue(forKey: originalURL)
        activeDownloadCount -= 1

        // Process next queued download
        processNextQueuedDownload()
    }
}

// MARK: - Extensions for Sendable Compliance

extension DownloadInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case id, remoteURL, localURL, downloadDate, metadata, fileSize, downloadDuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        remoteURL = try container.decode(URL.self, forKey: .remoteURL)
        localURL = try container.decode(URL.self, forKey: .localURL)
        downloadDate = try container.decode(Date.self, forKey: .downloadDate)
        metadata = try container.decodeIfPresent(AudioMetadata.self, forKey: .metadata)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        downloadDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .downloadDuration)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(remoteURL, forKey: .remoteURL)
        try container.encode(localURL, forKey: .localURL)
        try container.encode(downloadDate, forKey: .downloadDate)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encodeIfPresent(downloadDuration, forKey: .downloadDuration)
    }
}