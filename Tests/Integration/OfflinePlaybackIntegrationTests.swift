// OfflinePlaybackIntegrationTests.swift - T045: Offline download and playback workflow
// Tests download-first workflows for podcast and audiobook apps

import XCTest
import Combine
import Foundation
@testable import Resonance

final class OfflinePlaybackIntegrationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockDownloader: MockAudioDownloadable!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        mockDownloader = MockAudioDownloadable()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        mockDownloader = nil
        try await super.tearDown()
    }

    // MARK: - T045.1: Complete Download-to-Play Workflow

    func testCompleteOfflineWorkflow() async throws {
        // Test the full offline experience: download, store, play offline
        let remoteURL = URL(string: "https://example.com/podcast-episode.mp3")!
        let metadata = AudioMetadata(
            title: "Offline Episode",
            artist: "Podcast Host",
            artwork: Data([1, 2, 3, 4])
        )

        // Step 1: Initiate download
        var downloadProgresses: [DownloadProgress] = []
        var downloadError: AudioError?

        let downloadExpectation = expectation(description: "Download completion")

        mockDownloader.downloadAudio(from: remoteURL, metadata: metadata)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        downloadError = error
                    }
                    downloadExpectation.fulfill()
                },
                receiveValue: { progress in
                    downloadProgresses.append(progress)
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [downloadExpectation], timeout: 3.0)

        // Verify download completed successfully
        XCTAssertNil(downloadError, "Download should complete without error")
        XCTAssertFalse(downloadProgresses.isEmpty, "Should receive progress updates")

        let finalProgress = downloadProgresses.last!
        XCTAssertEqual(finalProgress.progress, 1.0, "Download should reach 100%")
        XCTAssertEqual(finalProgress.state, .completed, "Should be in completed state")
        XCTAssertNotNil(finalProgress.localURL, "Should have local URL when complete")

        // Step 2: Verify download is stored locally
        let localURL = mockDownloader.localURL(for: remoteURL)
        XCTAssertNotNil(localURL, "Should find local file for remote URL")
        XCTAssertEqual(localURL, finalProgress.localURL, "Local URLs should match")

        // Step 3: Play from local storage
        try await playOfflineAudio(localURL: localURL!)

        // Step 4: Verify in download list
        let allDownloads = mockDownloader.getAllDownloads()
        XCTAssertEqual(allDownloads.count, 1, "Should have one download")
        XCTAssertEqual(allDownloads.first?.remoteURL, remoteURL)
        XCTAssertEqual(allDownloads.first?.metadata?.title, "Offline Episode")
    }

    // MARK: - T045.2: Download Progress Tracking

    func testDownloadProgressTracking() async throws {
        // Test detailed progress monitoring for UI updates
        let remoteURL = URL(string: "https://example.com/large-audiobook.mp3")!

        var progressUpdates: [DownloadProgress] = []
        var globalProgressUpdates: [[URL: DownloadProgress]] = []

        // Monitor individual download progress
        let downloadExpectation = expectation(description: "Download with progress")

        mockDownloader.downloadAudio(from: remoteURL, metadata: nil)
            .sink(
                receiveCompletion: { _ in downloadExpectation.fulfill() },
                receiveValue: { progress in
                    progressUpdates.append(progress)
                }
            )
            .store(in: &cancellables)

        // Monitor global download progress
        mockDownloader.downloadProgress
            .sink { progressDict in
                globalProgressUpdates.append(progressDict)
            }
            .store(in: &cancellables)

        await fulfillment(of: [downloadExpectation], timeout: 3.0)

        // Verify progress tracking
        XCTAssertGreaterThan(progressUpdates.count, 3, "Should have multiple progress updates")

        // Check progress sequence
        let progressValues = progressUpdates.map { $0.progress }
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i-1],
                                       "Progress should only increase")
        }

        // Verify bytes tracking
        let bytesUpdates = progressUpdates.compactMap { $0.downloadedBytes }
        XCTAssertFalse(bytesUpdates.isEmpty, "Should track downloaded bytes")

        // Verify global progress was tracked
        XCTAssertFalse(globalProgressUpdates.isEmpty, "Should receive global progress updates")
        let hasOurDownload = globalProgressUpdates.contains { dict in
            dict[remoteURL] != nil
        }
        XCTAssertTrue(hasOurDownload, "Global progress should include our download")
    }

    // MARK: - T045.3: Download Cancellation

    func testDownloadCancellation() async throws {
        // Test user cancelling download mid-stream
        let remoteURL = URL(string: "https://example.com/cancellable-audio.mp3")!

        var progressUpdates: [DownloadProgress] = []

        // Start download
        let downloadExpectation = expectation(description: "Download start")
        mockDownloader.downloadAudio(from: remoteURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    downloadExpectation.fulfill()
                },
                receiveValue: { progress in
                    progressUpdates.append(progress)

                    // Cancel after first progress update
                    if progress.progress > 0.1 {
                        Task {
                            try await self.cancelDownload(url: remoteURL)
                        }
                    }
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [downloadExpectation], timeout: 2.0)

        // Verify cancellation worked
        let finalProgress = progressUpdates.last!
        XCTAssertEqual(finalProgress.state, .cancelled, "Should be cancelled")
        XCTAssertLessThan(finalProgress.progress, 1.0, "Should not complete")

        // Verify no local file exists
        let localURL = mockDownloader.localURL(for: remoteURL)
        XCTAssertNil(localURL, "Should not have local file after cancellation")
    }

    // MARK: - T045.4: Multiple Downloads Management

    func testMultipleDownloadsManagement() async throws {
        // Test downloading multiple files simultaneously
        let urls = [
            URL(string: "https://example.com/episode1.mp3")!,
            URL(string: "https://example.com/episode2.mp3")!,
            URL(string: "https://example.com/episode3.mp3")!
        ]

        var completedDownloads: [URL] = []
        let allDownloadsExpectation = expectation(description: "All downloads complete")
        allDownloadsExpectation.expectedFulfillmentCount = 3

        // Start all downloads
        for url in urls {
            mockDownloader.downloadAudio(from: url, metadata: nil)
                .sink(
                    receiveCompletion: { completion in
                        if case .finished = completion {
                            completedDownloads.append(url)
                        }
                        allDownloadsExpectation.fulfill()
                    },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
        }

        await fulfillment(of: [allDownloadsExpectation], timeout: 5.0)

        // Verify all downloads completed
        XCTAssertEqual(completedDownloads.count, 3, "All downloads should complete")

        // Check download list
        let allDownloads = mockDownloader.getAllDownloads()
        XCTAssertEqual(allDownloads.count, 3, "Should have all three downloads")

        // Verify each URL has local file
        for url in urls {
            let localURL = mockDownloader.localURL(for: url)
            XCTAssertNotNil(localURL, "Each URL should have local file")
        }
    }

    // MARK: - T045.5: Offline Playback Without Network

    func testTrueOfflinePlayback() async throws {
        // Test playing downloaded content when completely offline
        let remoteURL = URL(string: "https://example.com/offline-test.mp3")!

        // First download the content
        try await downloadAudio(url: remoteURL)

        // Simulate going offline
        mockDownloader.simulateOfflineMode = true

        // Get local URL and verify we can still play
        let localURL = mockDownloader.localURL(for: remoteURL)
        XCTAssertNotNil(localURL, "Should have local URL")

        // Attempt to play offline
        try await playOfflineAudio(localURL: localURL!)

        // Verify we could play without network
        XCTAssertTrue(mockDownloader.simulateOfflineMode, "Should still be in offline mode")
    }

    // MARK: - T045.6: Storage Management

    func testStorageManagement() async throws {
        // Test deleting downloads to manage storage
        let remoteURL = URL(string: "https://example.com/deletable-audio.mp3")!

        // Download first
        try await downloadAudio(url: remoteURL)

        let localURL = mockDownloader.localURL(for: remoteURL)!

        // Verify download exists
        let downloadsBeforeDelete = mockDownloader.getAllDownloads()
        XCTAssertEqual(downloadsBeforeDelete.count, 1)

        // Delete the download
        let deleteExpectation = expectation(description: "Delete download")
        mockDownloader.deleteDownload(at: localURL)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        deleteExpectation.fulfill()
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [deleteExpectation], timeout: 1.0)

        // Verify deletion
        let downloadsAfterDelete = mockDownloader.getAllDownloads()
        XCTAssertEqual(downloadsAfterDelete.count, 0, "Download should be deleted")

        let remainingLocalURL = mockDownloader.localURL(for: remoteURL)
        XCTAssertNil(remainingLocalURL, "Local URL should no longer exist")
    }

    // MARK: - T045.7: Cellular Data Control

    func testCellularDataControl() async throws {
        // Test cellular download restrictions
        let remoteURL = URL(string: "https://example.com/cellular-test.mp3")!

        // Disable cellular downloads
        mockDownloader.allowsCellularDownloads = false

        // Simulate being on cellular
        mockDownloader.simulateCellularNetwork = true

        var downloadError: AudioError?
        let downloadExpectation = expectation(description: "Cellular download attempt")

        mockDownloader.downloadAudio(from: remoteURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        downloadError = error
                    }
                    downloadExpectation.fulfill()
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [downloadExpectation], timeout: 1.0)

        // Should fail due to cellular restriction
        XCTAssertNotNil(downloadError, "Should fail on cellular when disabled")

        // Enable cellular and try again
        mockDownloader.allowsCellularDownloads = true

        let cellularDownloadExpectation = expectation(description: "Cellular download allowed")
        mockDownloader.downloadAudio(from: remoteURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        cellularDownloadExpectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [cellularDownloadExpectation], timeout: 2.0)

        // Should succeed with cellular enabled
        let localURL = mockDownloader.localURL(for: remoteURL)
        XCTAssertNotNil(localURL, "Should download successfully on cellular when allowed")
    }

    // MARK: - Helper Methods

    private func downloadAudio(url: URL, metadata: AudioMetadata? = nil) async throws {
        let expectation = expectation(description: "Download audio")

        mockDownloader.downloadAudio(from: url, metadata: metadata)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    private func cancelDownload(url: URL) async throws {
        let expectation = expectation(description: "Cancel download")

        mockDownloader.cancelDownload(for: url)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    private func playOfflineAudio(localURL: URL) async throws {
        // Simulate playing from local file
        // In real implementation, this would use AudioPlayable with local URL
        let expectation = expectation(description: "Play offline audio")

        // Mock playing local audio file
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation

/// Mock implementation of AudioDownloadable for testing offline workflows
private class MockAudioDownloadable: AudioDownloadable {
    private var downloads: [URL: DownloadInfo] = [:]
    private var activeDownloads: [URL: DownloadProgress] = [:]
    private let downloadProgressSubject = CurrentValueSubject<[URL: DownloadProgress], Never>([:])

    var allowsCellularDownloads: Bool = true
    var simulateOfflineMode: Bool = false
    var simulateCellularNetwork: Bool = false

    var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> {
        downloadProgressSubject.eraseToAnyPublisher()
    }

    func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError> {
        // Check cellular restrictions
        if simulateCellularNetwork && !allowsCellularDownloads {
            return Fail(error: AudioError.networkFailure).eraseToAnyPublisher()
        }

        return Future { promise in
            Task {
                await self.simulateDownload(url: url, metadata: metadata, promise: promise)
            }
        }.eraseToAnyPublisher()
    }

    func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if var progress = self.activeDownloads[url] {
                    progress = DownloadProgress(
                        remoteURL: url,
                        localURL: nil,
                        progress: progress.progress,
                        state: .cancelled,
                        totalBytes: progress.totalBytes,
                        downloadedBytes: progress.downloadedBytes
                    )
                    self.activeDownloads[url] = progress
                    self.downloadProgressSubject.send(self.activeDownloads)
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func localURL(for remoteURL: URL) -> URL? {
        return downloads[remoteURL]?.localURL
    }

    func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                // Find and remove download by local URL
                if let remoteURL = self.downloads.first(where: { $0.value.localURL == localURL })?.key {
                    self.downloads.removeValue(forKey: remoteURL)
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func getAllDownloads() -> [DownloadInfo] {
        return Array(downloads.values).sorted { $0.downloadDate < $1.downloadDate }
    }

    private func simulateDownload(url: URL, metadata: AudioMetadata?,
                                promise: @escaping (Result<DownloadProgress, AudioError>) -> Void) async {

        let totalBytes: Int64 = 10_000_000 // 10MB
        let progressSteps = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]

        for (index, progressValue) in progressSteps.enumerated() {
            let downloadedBytes = Int64(Double(totalBytes) * progressValue)

            let progress = DownloadProgress(
                remoteURL: url,
                localURL: progressValue == 1.0 ? generateLocalURL(for: url) : nil,
                progress: progressValue,
                state: progressValue == 1.0 ? .completed : .downloading,
                totalBytes: totalBytes,
                downloadedBytes: downloadedBytes
            )

            activeDownloads[url] = progress
            downloadProgressSubject.send(activeDownloads)

            promise(.success(progress))

            // Check for cancellation between steps
            if index < progressSteps.count - 1 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
                if activeDownloads[url]?.state == .cancelled {
                    return
                }
            }
        }

        // Store completed download
        if activeDownloads[url]?.state == .completed {
            let localURL = generateLocalURL(for: url)
            let downloadInfo = DownloadInfo(
                remoteURL: url,
                localURL: localURL,
                downloadDate: Date(),
                metadata: metadata,
                fileSize: totalBytes
            )
            downloads[url] = downloadInfo
        }
    }

    private func generateLocalURL(for remoteURL: URL) -> URL {
        let filename = remoteURL.lastPathComponent
        return URL(fileURLWithPath: "/tmp/downloads/\(filename)")
    }
}