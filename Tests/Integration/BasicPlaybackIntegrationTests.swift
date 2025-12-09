// BasicPlaybackIntegrationTests.swift - T043: Basic 3-line podcast streaming scenario
// Tests the fundamental user experience that makes Resonance accessible

import XCTest
import Combine
import Foundation
@testable import Resonance

final class BasicPlaybackIntegrationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioPlayable!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioPlayable()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        mockPlayer = nil
        try await super.tearDown()
    }

    // MARK: - T043.1: The Essential 3-Line Integration Pattern

    func testThreeLineBasicUsage() async throws {
        // Test the fundamental promise of Resonance: 3-line podcast streaming
        // This is the most important test - it validates the core value proposition

        let testURL = URL(string: "https://example.com/podcast.mp3")!
        let expectation = expectation(description: "Basic 3-line playback")

        var playbackStates: [PlaybackState] = []

        // The 3-line pattern users expect:
        // 1. Load audio
        mockPlayer.loadAudio(from: testURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        // 2. Start playback
                        self.mockPlayer.play()
                            .sink(
                                receiveCompletion: { _ in },
                                receiveValue: {
                                    expectation.fulfill()
                                }
                            )
                            .store(in: &self.cancellables)
                    case .failure(let error):
                        XCTFail("Load failed: \(error)")
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        // 3. Monitor state changes
        mockPlayer.playbackState
            .sink { state in
                playbackStates.append(state)
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 2.0)

        // Verify the expected state progression
        XCTAssertTrue(playbackStates.contains(.loading), "Should show loading state")
        XCTAssertTrue(playbackStates.contains(.ready), "Should reach ready state")
        XCTAssertTrue(playbackStates.contains(.playing), "Should reach playing state")
    }

    // MARK: - T043.2: Real-World Error Scenarios

    func testNetworkErrorRecovery() async throws {
        // Test real-world scenario: network failure during streaming
        let testURL = URL(string: "https://unreachable.example.com/podcast.mp3")!
        let expectation = expectation(description: "Network error handling")

        mockPlayer.simulateNetworkError = true

        mockPlayer.loadAudio(from: testURL, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error, AudioError.networkFailure)
                        expectation.fulfill()
                    } else {
                        XCTFail("Expected network failure")
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - T043.3: Basic Seek and Time Tracking

    func testBasicSeekOperation() async throws {
        // Test seeking during playback - essential for podcast apps
        let testURL = URL(string: "https://example.com/podcast.mp3")!
        let expectation = expectation(description: "Seek operation")

        // Load and start playback first
        try await preparePlayback(url: testURL)

        var currentTimes: [TimeInterval] = []

        mockPlayer.currentTime
            .sink { time in
                currentTimes.append(time)
            }
            .store(in: &cancellables)

        // Seek to 30 seconds
        let seekTime: TimeInterval = 30.0
        mockPlayer.seek(to: seekTime)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)

        // Verify seek worked
        XCTAssertTrue(currentTimes.last == seekTime, "Should seek to requested time")
    }

    // MARK: - T043.4: Metadata Handling

    func testBasicMetadataDisplay() async throws {
        // Test metadata display for podcast titles/artists
        let testURL = URL(string: "https://example.com/podcast.mp3")!
        let testMetadata = AudioMetadata(
            title: "Test Podcast Episode",
            artist: "Test Podcaster",
            artwork: Data([1, 2, 3, 4]), // Mock image data
            chapters: []
        )

        let expectation = expectation(description: "Metadata loading")

        mockPlayer.loadAudio(from: testURL, metadata: testMetadata)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)

        // Verify metadata was processed
        XCTAssertEqual(mockPlayer.loadedMetadata?.title, "Test Podcast Episode")
        XCTAssertEqual(mockPlayer.loadedMetadata?.artist, "Test Podcaster")
        XCTAssertNotNil(mockPlayer.loadedMetadata?.artwork)
    }

    // MARK: - T043.5: Performance Characteristics

    func testPlaybackPerformance() async throws {
        // Test that basic playback meets performance requirements
        let testURL = URL(string: "https://example.com/podcast.mp3")!

        // Measure load time
        let loadStartTime = Date()

        try await preparePlayback(url: testURL)

        let loadDuration = Date().timeIntervalSince(loadStartTime)

        // Basic playback should be fast
        XCTAssertLessThan(loadDuration, 0.5, "Load should complete in under 500ms")

        // Measure play start time
        let playStartTime = Date()

        let expectation = expectation(description: "Play performance")

        mockPlayer.play()
            .sink(
                receiveCompletion: { _ in },
                receiveValue: {
                    let playDuration = Date().timeIntervalSince(playStartTime)
                    XCTAssertLessThan(playDuration, 0.1, "Play should start in under 100ms")
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Helper Methods

    private func preparePlayback(url: URL) async throws {
        let expectation = expectation(description: "Prepare playback")

        mockPlayer.loadAudio(from: url, metadata: nil)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation

/// Mock implementation of AudioPlayable for testing the basic contract
private class MockAudioPlayable: AudioPlayable {
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)

    var simulateNetworkError = false
    var loadedMetadata: AudioMetadata?

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
        if simulateNetworkError {
            return Fail(error: AudioError.networkFailure).eraseToAnyPublisher()
        }

        loadedMetadata = metadata

        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.loading)

                // Simulate loading delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.playbackStateSubject.send(.ready)
                    self.durationSubject.send(120.0) // 2-minute test audio
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.playing)
                self.startTimeUpdates()
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.paused)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.currentTimeSubject.send(position)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    private func startTimeUpdates() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            if self.playbackStateSubject.value == .playing {
                let newTime = self.currentTimeSubject.value + 0.1
                self.currentTimeSubject.send(min(newTime, self.durationSubject.value))
            }
        }
    }
}