// AudioConfigurableTests.swift - Contract tests for AudioConfigurable protocol
// These tests verify enhanced audio configuration capabilities

import XCTest
import Combine
@testable import Resonance

final class AudioConfigurableTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioConfigurable!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioConfigurable()
    }

    override func tearDown() {
        cancellables = nil
        mockPlayer = nil
        super.tearDown()
    }

    // MARK: - Volume Control Contract Tests

    func testVolumeProperty() {
        // Arrange & Act
        mockPlayer.volume = 0.7

        // Assert
        XCTAssertEqual(mockPlayer.volume, 0.7, accuracy: 0.01)
    }

    func testVolumeRangeLimits() {
        // Test minimum volume
        mockPlayer.volume = -0.5
        XCTAssertGreaterThanOrEqual(mockPlayer.volume, 0.0)

        // Test maximum volume
        mockPlayer.volume = 1.5
        XCTAssertLessThanOrEqual(mockPlayer.volume, 1.0)
    }

    // MARK: - Playback Rate Contract Tests

    func testPlaybackRateProperty() {
        // Arrange & Act
        mockPlayer.playbackRate = 1.5

        // Assert
        XCTAssertEqual(mockPlayer.playbackRate, 1.5, accuracy: 0.01)
    }

    func testPlaybackRateRangeLimits() {
        // Test minimum rate
        mockPlayer.playbackRate = 0.25
        XCTAssertGreaterThanOrEqual(mockPlayer.playbackRate, 0.5)

        // Test maximum rate
        mockPlayer.playbackRate = 5.0
        XCTAssertLessThanOrEqual(mockPlayer.playbackRate, 4.0)
    }

    // MARK: - Metadata Management Contract Tests

    func testUpdateMetadata() {
        // Arrange
        let newMetadata = AudioMetadata(
            title: "Updated Title",
            artist: "Updated Artist",
            artwork: Data([1, 2, 3, 4])
        )
        let expectation = XCTestExpectation(description: "Metadata update completes")

        // Act & Assert
        mockPlayer.updateMetadata(newMetadata)
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
        XCTAssertEqual(mockPlayer.lastUpdatedMetadata?.title, "Updated Title")
        XCTAssertEqual(mockPlayer.lastUpdatedMetadata?.artist, "Updated Artist")
    }

    func testMetadataPublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Metadata updates received")
        expectation.expectedFulfillmentCount = 2
        var receivedMetadata: [AudioMetadata?] = []

        // Act & Assert
        mockPlayer.metadata
            .sink { metadata in
                receivedMetadata.append(metadata)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger metadata update
        let newMetadata = AudioMetadata(title: "New Title")
        mockPlayer.simulateMetadataUpdate(newMetadata)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedMetadata.count, 2)
        XCTAssertNil(receivedMetadata[0])
        XCTAssertEqual(receivedMetadata[1]?.title, "New Title")
    }

    // MARK: - Skip Controls Contract Tests

    func testSkipForward() {
        // Arrange
        let skipDuration: TimeInterval = 30.0
        let expectation = XCTestExpectation(description: "Skip forward completes")

        // Act & Assert
        mockPlayer.skipForward(duration: skipDuration)
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
        XCTAssertEqual(mockPlayer.lastSkipForwardDuration, skipDuration)
    }

    func testSkipBackward() {
        // Arrange
        let skipDuration: TimeInterval = 15.0
        let expectation = XCTestExpectation(description: "Skip backward completes")

        // Act & Assert
        mockPlayer.skipBackward(duration: skipDuration)
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
        XCTAssertEqual(mockPlayer.lastSkipBackwardDuration, skipDuration)
    }

    // MARK: - Buffer Status Contract Tests

    func testBufferStatusPublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Buffer status updates")
        expectation.expectedFulfillmentCount = 2
        var receivedStatuses: [BufferStatus?] = []

        // Act & Assert
        mockPlayer.bufferStatus
            .sink { status in
                receivedStatuses.append(status)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger buffer status update
        let bufferStatus = BufferStatus(
            bufferedRange: 0.0...30.0,
            isReadyForPlaying: true,
            bufferingProgress: 0.75
        )
        mockPlayer.simulateBufferStatusUpdate(bufferStatus)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStatuses.count, 2)
        XCTAssertNil(receivedStatuses[0])
        XCTAssertEqual(receivedStatuses[1]?.bufferingProgress, 0.75)
        XCTAssertTrue(receivedStatuses[1]?.isReadyForPlaying ?? false)
    }

    // MARK: - Error Handling Contract Tests

    func testSkipOutOfBounds() {
        // Arrange
        let expectation = XCTestExpectation(description: "Skip error handled")

        // Act & Assert
        mockPlayer.forceError = AudioError.seekOutOfBounds
        mockPlayer.skipForward(duration: 1000.0) // Way beyond duration
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error as? AudioError, AudioError.seekOutOfBounds)
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

private class MockAudioConfigurable: AudioConfigurable {
    // AudioPlayable properties
    var lastLoadedURL: URL?
    var lastLoadedMetadata: AudioMetadata?
    var lastSeekPosition: TimeInterval?
    var playWasCalled = false
    var pauseWasCalled = false
    var forceError: AudioError?

    // AudioConfigurable properties
    var lastUpdatedMetadata: AudioMetadata?
    var lastSkipForwardDuration: TimeInterval?
    var lastSkipBackwardDuration: TimeInterval?

    private var _volume: Float = 1.0
    private var _playbackRate: Float = 1.0

    var volume: Float {
        get { _volume }
        set { _volume = max(0.0, min(1.0, newValue)) }
    }

    var playbackRate: Float {
        get { _playbackRate }
        set { _playbackRate = max(0.5, min(4.0, newValue)) }
    }

    // Publishers
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0.0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0.0)
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)

    var playbackState: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }

    var metadata: AnyPublisher<AudioMetadata?, Never> {
        metadataSubject.eraseToAnyPublisher()
    }

    var bufferStatus: AnyPublisher<BufferStatus?, Never> {
        bufferStatusSubject.eraseToAnyPublisher()
    }

    // AudioPlayable methods
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        lastLoadedURL = url
        lastLoadedMetadata = metadata

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        playWasCalled = true

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Void, AudioError> {
        pauseWasCalled = true

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        lastSeekPosition = position

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // AudioConfigurable methods
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        lastUpdatedMetadata = metadata

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        lastSkipForwardDuration = duration

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        lastSkipBackwardDuration = duration

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // Test helper methods
    func simulateMetadataUpdate(_ metadata: AudioMetadata?) {
        metadataSubject.send(metadata)
    }

    func simulateBufferStatusUpdate(_ status: BufferStatus?) {
        bufferStatusSubject.send(status)
    }
}