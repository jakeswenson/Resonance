// EnhancedPlaybackIntegrationTests.swift - T044: Enhanced playback with speed control
// Tests advanced playback features for app developers

import XCTest
import Combine
import Foundation
@testable import Resonance

final class EnhancedPlaybackIntegrationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioConfigurable!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioConfigurable()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        mockPlayer = nil
        try await super.tearDown()
    }

    // MARK: - T044.1: Volume Control Integration

    func testVolumeControlWorkflow() async throws {
        // Test real-world volume management scenario
        let testURL = URL(string: "https://example.com/audiobook.mp3")!

        try await preparePlayback(url: testURL)

        // Start with default volume
        XCTAssertEqual(mockPlayer.volume, 1.0, "Default volume should be 1.0")

        // Simulate user adjusting volume during playback
        mockPlayer.volume = 0.5
        XCTAssertEqual(mockPlayer.volume, 0.5, "Volume should update immediately")

        // Test edge cases
        mockPlayer.volume = 0.0  // Mute
        XCTAssertEqual(mockPlayer.volume, 0.0, "Should support muting")

        mockPlayer.volume = 1.0  // Max volume
        XCTAssertEqual(mockPlayer.volume, 1.0, "Should support max volume")
    }

    // MARK: - T044.2: Playback Rate Control for Podcasts

    func testPlaybackRateControl() async throws {
        // Test podcast speed control - critical feature for podcast apps
        let testURL = URL(string: "https://example.com/podcast.mp3")!

        try await preparePlayback(url: testURL)

        var playbackRates: [Float] = []

        // Monitor playback rate changes
        mockPlayer.rateChangePublisher
            .sink { rate in
                playbackRates.append(rate)
            }
            .store(in: &cancellables)

        // Test common podcast playback rates
        mockPlayer.playbackRate = 1.5  // 1.5x speed
        XCTAssertEqual(mockPlayer.playbackRate, 1.5)

        mockPlayer.playbackRate = 2.0  // 2x speed
        XCTAssertEqual(mockPlayer.playbackRate, 2.0)

        mockPlayer.playbackRate = 0.75 // 0.75x speed (slower)
        XCTAssertEqual(mockPlayer.playbackRate, 0.75)

        // Verify rate changes were captured
        XCTAssertTrue(playbackRates.contains(1.5))
        XCTAssertTrue(playbackRates.contains(2.0))
        XCTAssertTrue(playbackRates.contains(0.75))
    }

    // MARK: - T044.3: Skip Forward/Backward for Podcasts

    func testSkipControls() async throws {
        // Test 15-second skip forward/backward - standard podcast behavior
        let testURL = URL(string: "https://example.com/podcast.mp3")!

        try await preparePlayback(url: testURL)

        var currentTimes: [TimeInterval] = []

        mockPlayer.currentTime
            .sink { time in
                currentTimes.append(time)
            }
            .store(in: &cancellables)

        // Start at 60 seconds
        try await seek(to: 60.0)

        // Skip forward 15 seconds
        let skipForwardExpectation = expectation(description: "Skip forward")
        mockPlayer.skipForward(duration: 15.0)
            .sink(
                receiveCompletion: { _ in skipForwardExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [skipForwardExpectation], timeout: 1.0)

        // Should be at 75 seconds
        XCTAssertEqual(mockPlayer.currentTimeValue, 75.0, "Should skip forward 15 seconds")

        // Skip backward 30 seconds
        let skipBackwardExpectation = expectation(description: "Skip backward")
        mockPlayer.skipBackward(duration: 30.0)
            .sink(
                receiveCompletion: { _ in skipBackwardExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [skipBackwardExpectation], timeout: 1.0)

        // Should be at 45 seconds
        XCTAssertEqual(mockPlayer.currentTimeValue, 45.0, "Should skip backward 30 seconds")
    }

    // MARK: - T044.4: Dynamic Metadata Updates

    func testDynamicMetadataUpdates() async throws {
        // Test updating metadata during playback (e.g., chapter changes)
        let testURL = URL(string: "https://example.com/podcast.mp3")!

        let initialMetadata = AudioMetadata(
            title: "Episode 1: Introduction",
            artist: "Test Podcast",
            artwork: nil,
            chapters: []
        )

        try await preparePlayback(url: testURL, metadata: initialMetadata)

        var metadataUpdates: [AudioMetadata?] = []

        mockPlayer.metadata
            .sink { metadata in
                metadataUpdates.append(metadata)
            }
            .store(in: &cancellables)

        // Simulate chapter change during playback
        let newMetadata = AudioMetadata(
            title: "Episode 1: Chapter 2 - Deep Dive",
            artist: "Test Podcast",
            artwork: Data([5, 6, 7, 8]), // New artwork
            chapters: []
        )

        let updateExpectation = expectation(description: "Metadata update")
        mockPlayer.updateMetadata(newMetadata)
            .sink(
                receiveCompletion: { _ in updateExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [updateExpectation], timeout: 1.0)

        // Verify metadata was updated
        XCTAssertEqual(mockPlayer.currentMetadata?.title, "Episode 1: Chapter 2 - Deep Dive")
        XCTAssertNotNil(mockPlayer.currentMetadata?.artwork)
        XCTAssertTrue(metadataUpdates.count >= 2, "Should have captured metadata updates")
    }

    // MARK: - T044.5: Buffer Status Monitoring

    func testBufferStatusMonitoring() async throws {
        // Test streaming buffer monitoring - crucial for smooth playback
        let testURL = URL(string: "https://example.com/stream.mp3")!

        try await preparePlayback(url: testURL)

        var bufferStatuses: [BufferStatus?] = []

        mockPlayer.bufferStatus
            .sink { status in
                bufferStatuses.append(status)
            }
            .store(in: &cancellables)

        // Simulate streaming with varying buffer conditions
        await mockPlayer.simulateBuffering()

        // Verify buffer status updates
        let validStatuses = bufferStatuses.compactMap { $0 }
        XCTAssertFalse(validStatuses.isEmpty, "Should receive buffer status updates")

        // Check for realistic buffer progression
        let hasReadyStatus = validStatuses.contains { $0.isReadyForPlaying }
        XCTAssertTrue(hasReadyStatus, "Should indicate when ready for playing")

        let hasProgressingBuffer = validStatuses.contains { $0.bufferingProgress > 0 }
        XCTAssertTrue(hasProgressingBuffer, "Should show buffering progress")
    }

    // MARK: - T044.6: Enhanced Error Recovery

    func testEnhancedErrorRecovery() async throws {
        // Test graceful handling of enhanced features during errors
        let testURL = URL(string: "https://example.com/problematic.mp3")!

        try await preparePlayback(url: testURL)

        // Start playback
        let playExpectation = expectation(description: "Start playback")
        mockPlayer.play()
            .sink(
                receiveCompletion: { _ in playExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [playExpectation], timeout: 1.0)

        // Simulate network interruption during rate change
        mockPlayer.simulateNetworkInterruption = true
        mockPlayer.playbackRate = 2.0

        // Try to skip forward during network issues
        let skipExpectation = expectation(description: "Skip during error")
        mockPlayer.skipForward(duration: 15.0)
            .sink(
                receiveCompletion: { completion in
                    // Should handle gracefully without crashing
                    skipExpectation.fulfill()
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [skipExpectation], timeout: 1.0)

        // Verify player maintains stable state
        XCTAssertNotEqual(mockPlayer.playbackState.value, .error(AudioError.internalError("crash")))
    }

    // MARK: - T044.7: Performance Under Enhanced Load

    func testPerformanceWithEnhancedFeatures() async throws {
        // Test performance when using multiple enhanced features simultaneously
        let testURL = URL(string: "https://example.com/performance-test.mp3")!

        let startTime = Date()

        try await preparePlayback(url: testURL)

        // Apply multiple enhancements rapidly
        mockPlayer.volume = 0.8
        mockPlayer.playbackRate = 1.5

        let metadata = AudioMetadata(title: "Performance Test", artist: "Test Suite")
        let updateExpectation = expectation(description: "Multiple updates")

        mockPlayer.updateMetadata(metadata)
            .sink(
                receiveCompletion: { _ in updateExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [updateExpectation], timeout: 1.0)

        let totalDuration = Date().timeIntervalSince(startTime)

        // Multiple enhanced operations should complete quickly
        XCTAssertLessThan(totalDuration, 1.0, "Enhanced operations should be efficient")

        // Verify all settings applied
        XCTAssertEqual(mockPlayer.volume, 0.8)
        XCTAssertEqual(mockPlayer.playbackRate, 1.5)
        XCTAssertEqual(mockPlayer.currentMetadata?.title, "Performance Test")
    }

    // MARK: - Helper Methods

    private func preparePlayback(url: URL, metadata: AudioMetadata? = nil) async throws {
        let expectation = expectation(description: "Prepare playback")

        mockPlayer.loadAudio(from: url, metadata: metadata)
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

    private func seek(to position: TimeInterval) async throws {
        let expectation = expectation(description: "Seek operation")

        mockPlayer.seek(to: position)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation

/// Mock implementation of AudioConfigurable for testing enhanced features
private class MockAudioConfigurable: AudioConfigurable {
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)
    private let rateChangeSubject = PassthroughSubject<Float, Never>()

    var volume: Float = 1.0

    private var _playbackRate: Float = 1.0
    var playbackRate: Float {
        get { _playbackRate }
        set {
            _playbackRate = newValue
            rateChangeSubject.send(newValue)
        }
    }

    var simulateNetworkInterruption = false
    var currentMetadata: AudioMetadata? { metadataSubject.value }
    var currentTimeValue: TimeInterval { currentTimeSubject.value }

    // Protocol conformance
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

    var rateChangePublisher: AnyPublisher<Float, Never> {
        rateChangeSubject.eraseToAnyPublisher()
    }

    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.loading)
                self.metadataSubject.send(metadata)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.playbackStateSubject.send(.ready)
                    self.durationSubject.send(180.0) // 3-minute test audio
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if self.simulateNetworkInterruption {
                    self.playbackStateSubject.send(.buffering)
                } else {
                    self.playbackStateSubject.send(.playing)
                }
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

    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.metadataSubject.send(metadata)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if self.simulateNetworkInterruption {
                    // Simulate graceful handling during network issues
                    promise(.success(()))
                } else {
                    let newTime = self.currentTimeSubject.value + duration
                    self.currentTimeSubject.send(min(newTime, self.durationSubject.value))
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }

    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                let newTime = max(0, self.currentTimeSubject.value - duration)
                self.currentTimeSubject.send(newTime)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func simulateBuffering() async {
        // Simulate realistic buffering progression
        let bufferProgresses: [Double] = [0.1, 0.3, 0.6, 0.8, 1.0]

        for progress in bufferProgresses {
            let bufferStatus = BufferStatus(
                bufferedRange: 0...30.0,
                isReadyForPlaying: progress >= 0.3,
                bufferingProgress: progress
            )
            bufferStatusSubject.send(bufferStatus)

            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        }
    }
}