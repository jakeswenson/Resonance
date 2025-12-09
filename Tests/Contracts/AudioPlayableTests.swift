// AudioPlayableTests.swift - Contract tests for AudioPlayable protocol
// These tests define the expected behavior of any AudioPlayable implementation

import XCTest
import Combine
@testable import Resonance

final class AudioPlayableTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioPlayable!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioPlayable()
    }

    override func tearDown() {
        cancellables = nil
        mockPlayer = nil
        super.tearDown()
    }

    // MARK: - Basic Playback Contract Tests

    func testLoadAudioFromURL() {
        // Arrange
        let testURL = URL(string: "https://example.com/test.mp3")!
        let metadata = AudioMetadata(title: "Test Audio", artist: "Test Artist")
        let expectation = XCTestExpectation(description: "Load audio completes")

        // Act & Assert
        mockPlayer.loadAudio(from: testURL, metadata: metadata)
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
        XCTAssertEqual(mockPlayer.lastLoadedURL, testURL)
        XCTAssertEqual(mockPlayer.lastLoadedMetadata?.title, "Test Audio")
    }

    func testPlayAudio() {
        // Arrange
        let expectation = XCTestExpectation(description: "Play completes")

        // Act & Assert
        mockPlayer.play()
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
        XCTAssertTrue(mockPlayer.playWasCalled)
    }

    func testPauseAudio() {
        // Arrange
        let expectation = XCTestExpectation(description: "Pause completes")

        // Act & Assert
        mockPlayer.pause()
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
        XCTAssertTrue(mockPlayer.pauseWasCalled)
    }

    func testSeekToPosition() {
        // Arrange
        let targetPosition: TimeInterval = 30.0
        let expectation = XCTestExpectation(description: "Seek completes")

        // Act & Assert
        mockPlayer.seek(to: targetPosition)
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
        XCTAssertEqual(mockPlayer.lastSeekPosition, targetPosition)
    }

    // MARK: - State Observation Contract Tests

    func testPlaybackStatePublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Playback state changes")
        expectation.expectedFulfillmentCount = 2
        var receivedStates: [PlaybackState] = []

        // Act & Assert
        mockPlayer.playbackState
            .sink { state in
                receivedStates.append(state)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger state changes
        mockPlayer.simulateStateChange(.playing)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStates.count, 2)
        XCTAssertEqual(receivedStates[0], .idle)
        XCTAssertEqual(receivedStates[1], .playing)
    }

    func testCurrentTimePublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Current time updates")
        expectation.expectedFulfillmentCount = 2
        var receivedTimes: [TimeInterval] = []

        // Act & Assert
        mockPlayer.currentTime
            .sink { time in
                receivedTimes.append(time)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger time updates
        mockPlayer.simulateTimeUpdate(15.5)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedTimes.count, 2)
        XCTAssertEqual(receivedTimes[0], 0.0)
        XCTAssertEqual(receivedTimes[1], 15.5)
    }

    func testDurationPublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Duration updates")
        expectation.expectedFulfillmentCount = 2
        var receivedDurations: [TimeInterval] = []

        // Act & Assert
        mockPlayer.duration
            .sink { duration in
                receivedDurations.append(duration)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Trigger duration update
        mockPlayer.simulateDurationUpdate(120.0)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedDurations.count, 2)
        XCTAssertEqual(receivedDurations[0], 0.0)
        XCTAssertEqual(receivedDurations[1], 120.0)
    }

    // MARK: - Error Handling Contract Tests

    func testLoadAudioError() {
        // Arrange
        let invalidURL = URL(string: "invalid://url")!
        let expectation = XCTestExpectation(description: "Load audio fails")

        // Act & Assert
        mockPlayer.forceError = AudioError.invalidURL
        mockPlayer.loadAudio(from: invalidURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error as? AudioError, AudioError.invalidURL)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }

    func testPlaybackStateErrorTransition() {
        // Arrange
        let expectation = XCTestExpectation(description: "Error state received")

        // Act & Assert
        mockPlayer.playbackState
            .dropFirst() // Skip initial state
            .sink { state in
                if case .error(let error) = state {
                    XCTAssertEqual(error as? AudioError, AudioError.audioSessionError)
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        mockPlayer.simulateStateChange(.error(AudioError.audioSessionError))
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation for Testing

private class MockAudioPlayable: AudioPlayable {
    var lastLoadedURL: URL?
    var lastLoadedMetadata: AudioMetadata?
    var lastSeekPosition: TimeInterval?
    var playWasCalled = false
    var pauseWasCalled = false
    var forceError: AudioError?

    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0.0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0.0)

    var playbackState: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }

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

    // Test helper methods
    func simulateStateChange(_ state: PlaybackState) {
        playbackStateSubject.send(state)
    }

    func simulateTimeUpdate(_ time: TimeInterval) {
        currentTimeSubject.send(time)
    }

    func simulateDurationUpdate(_ duration: TimeInterval) {
        durationSubject.send(duration)
    }
}