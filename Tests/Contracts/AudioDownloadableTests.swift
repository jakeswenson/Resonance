// AudioDownloadableTests.swift - Contract tests for AudioDownloadable protocol
// These tests verify download functionality and offline capabilities

import XCTest
import Combine
@testable import Resonance

final class AudioDownloadableTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockDownloader: MockAudioDownloadable!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        mockDownloader = MockAudioDownloadable()
    }

    override func tearDown() {
        cancellables = nil
        mockDownloader = nil
        super.tearDown()
    }

    // MARK: - Download Management Contract Tests

    func testDownloadAudio() {
        // Arrange
        let remoteURL = URL(string: "https://example.com/audio.mp3")!
        let metadata = AudioMetadata(title: "Test Download")
        let expectation = XCTestExpectation(description: "Download progress received")
        var progressUpdates: [DownloadProgress] = []

        // Act & Assert
        mockDownloader.downloadAudio(from: remoteURL, metadata: metadata)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { progress in
                    progressUpdates.append(progress)
                }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 2.0)
        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertEqual(progressUpdates.last?.progress, 1.0)
        XCTAssertEqual(progressUpdates.last?.state, .completed)
    }

    func testCancelDownload() {
        // Arrange
        let remoteURL = URL(string: "https://example.com/audio.mp3")!
        let expectation = XCTestExpectation(description: "Cancel completes")

        // Act & Assert
        mockDownloader.cancelDownload(for: remoteURL)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockDownloader.cancelledURLs.contains(remoteURL))
    }

    func testLocalURLForRemoteURL() {
        // Arrange
        let remoteURL = URL(string: "https://example.com/audio.mp3")!
        let expectedLocalURL = URL(fileURLWithPath: "/tmp/audio.mp3")

        // Act
        mockDownloader.setLocalURL(expectedLocalURL, for: remoteURL)
        let result = mockDownloader.localURL(for: remoteURL)

        // Assert
        XCTAssertEqual(result, expectedLocalURL)
    }

    func testLocalURLForNonExistentRemoteURL() {
        // Arrange
        let remoteURL = URL(string: "https://example.com/nonexistent.mp3")!

        // Act
        let result = mockDownloader.localURL(for: remoteURL)

        // Assert
        XCTAssertNil(result)
    }

    func testDeleteDownload() {
        // Arrange
        let localURL = URL(fileURLWithPath: "/tmp/audio.mp3")
        let expectation = XCTestExpectation(description: "Delete completes")

        // Act & Assert
        mockDownloader.deleteDownload(at: localURL)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockDownloader.deletedURLs.contains(localURL))
    }

    func testGetAllDownloads() {
        // Arrange
        let download1 = DownloadInfo(
            remoteURL: URL(string: "https://example.com/audio1.mp3")!,
            localURL: URL(fileURLWithPath: "/tmp/audio1.mp3"),
            downloadDate: Date(),
            fileSize: 1024
        )
        let download2 = DownloadInfo(
            remoteURL: URL(string: "https://example.com/audio2.mp3")!,
            localURL: URL(fileURLWithPath: "/tmp/audio2.mp3"),
            downloadDate: Date(),
            fileSize: 2048
        )

        // Act
        mockDownloader.addDownloadInfo(download1)
        mockDownloader.addDownloadInfo(download2)
        let allDownloads = mockDownloader.getAllDownloads()

        // Assert
        XCTAssertEqual(allDownloads.count, 2)
        XCTAssertTrue(allDownloads.contains { $0.fileSize == 1024 })
        XCTAssertTrue(allDownloads.contains { $0.fileSize == 2048 })
    }

    // MARK: - Download Progress Publisher Contract Tests

    func testDownloadProgressPublisher() {
        // Arrange
        let remoteURL1 = URL(string: "https://example.com/audio1.mp3")!
        let remoteURL2 = URL(string: "https://example.com/audio2.mp3")!
        let expectation = XCTestExpectation(description: "Progress updates received")
        expectation.expectedFulfillmentCount = 3
        var progressUpdates: [[URL: DownloadProgress]] = []

        // Act & Assert
        mockDownloader.downloadProgress
            .sink { progressDict in
                progressUpdates.append(progressDict)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate progress updates
        let progress1 = DownloadProgress(
            remoteURL: remoteURL1,
            progress: 0.5,
            state: .downloading,
            downloadedBytes: 512
        )
        let progress2 = DownloadProgress(
            remoteURL: remoteURL2,
            progress: 0.3,
            state: .downloading,
            downloadedBytes: 256
        )

        mockDownloader.simulateProgressUpdate(progress1)
        mockDownloader.simulateProgressUpdate(progress2)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(progressUpdates.count, 3)
        XCTAssertTrue(progressUpdates.last?.keys.contains(remoteURL1) ?? false)
        XCTAssertTrue(progressUpdates.last?.keys.contains(remoteURL2) ?? false)
    }

    // MARK: - Cellular Data Control Contract Tests

    func testAllowsCellularDownloads() {
        // Arrange & Act
        mockDownloader.allowsCellularDownloads = false

        // Assert
        XCTAssertFalse(mockDownloader.allowsCellularDownloads)

        // Act
        mockDownloader.allowsCellularDownloads = true

        // Assert
        XCTAssertTrue(mockDownloader.allowsCellularDownloads)
    }

    // MARK: - Error Handling Contract Tests

    func testDownloadFailure() {
        // Arrange
        let remoteURL = URL(string: "https://invalid.url/audio.mp3")!
        let expectation = XCTestExpectation(description: "Download fails")

        // Act & Assert
        mockDownloader.forceError = AudioError.networkFailure
        mockDownloader.downloadAudio(from: remoteURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error as? AudioError, AudioError.networkFailure)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation for Testing

private class MockAudioDownloadable: AudioDownloadable {
    var cancelledURLs: Set<URL> = []
    var deletedURLs: Set<URL> = []
    var forceError: AudioError?
    var allowsCellularDownloads: Bool = true

    private var localURLs: [URL: URL] = [:]
    private var downloadInfos: [DownloadInfo] = []
    private let downloadProgressSubject = CurrentValueSubject<[URL: DownloadProgress], Never>([:])

    var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> {
        downloadProgressSubject.eraseToAnyPublisher()
    }

    func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(DownloadProgress(
            remoteURL: url,
            localURL: URL(fileURLWithPath: "/tmp/downloaded.mp3"),
            progress: 1.0,
            state: .completed,
            totalBytes: 1024,
            downloadedBytes: 1024
        ))
        .setFailureType(to: AudioError.self)
        .eraseToAnyPublisher()
    }

    func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        cancelledURLs.insert(url)

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func localURL(for remoteURL: URL) -> URL? {
        return localURLs[remoteURL]
    }

    func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        deletedURLs.insert(localURL)

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func getAllDownloads() -> [DownloadInfo] {
        return downloadInfos
    }

    // Test helper methods
    func setLocalURL(_ localURL: URL, for remoteURL: URL) {
        localURLs[remoteURL] = localURL
    }

    func addDownloadInfo(_ info: DownloadInfo) {
        downloadInfos.append(info)
    }

    func simulateProgressUpdate(_ progress: DownloadProgress) {
        var currentProgress = downloadProgressSubject.value
        currentProgress[progress.remoteURL] = progress
        downloadProgressSubject.send(currentProgress)
    }
}