// AudioQueueManageableTests.swift - Contract tests for AudioQueueManageable protocol
// These tests verify playlist and queue management functionality

import XCTest
import Combine
@testable import Resonance

final class AudioQueueManageableTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioQueueManageable!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioQueueManageable()
    }

    override func tearDown() {
        cancellables = nil
        mockPlayer = nil
        super.tearDown()
    }

    // MARK: - Queue Management Contract Tests

    func testEnqueueAudio() {
        // Arrange
        let audioURL = URL(string: "https://example.com/audio.mp3")!
        let metadata = AudioMetadata(title: "Test Audio")
        let expectation = XCTestExpectation(description: "Enqueue completes")

        // Act & Assert
        mockPlayer.enqueue(url: audioURL, metadata: metadata)
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
        XCTAssertTrue(mockPlayer.enqueuedItems.contains { $0.url == audioURL })
    }

    func testEnqueueNext() {
        // Arrange
        let audioURL = URL(string: "https://example.com/priority.mp3")!
        let expectation = XCTestExpectation(description: "Enqueue next completes")

        // Act & Assert
        mockPlayer.enqueueNext(url: audioURL, metadata: nil)
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
        XCTAssertEqual(mockPlayer.enqueuedNextItems.first?.url, audioURL)
    }

    func testDequeue() {
        // Arrange
        let queueId = UUID()
        let expectation = XCTestExpectation(description: "Dequeue completes")

        // Act & Assert
        mockPlayer.dequeue(id: queueId)
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
        XCTAssertTrue(mockPlayer.dequeuedIds.contains(queueId))
    }

    func testPlayNext() {
        // Arrange
        let expectation = XCTestExpectation(description: "Play next completes")

        // Act & Assert
        mockPlayer.playNext()
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
        XCTAssertTrue(mockPlayer.playNextWasCalled)
    }

    func testPlayPrevious() {
        // Arrange
        let expectation = XCTestExpectation(description: "Play previous completes")

        // Act & Assert
        mockPlayer.playPrevious()
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
        XCTAssertTrue(mockPlayer.playPreviousWasCalled)
    }

    func testClearQueue() {
        // Arrange
        let expectation = XCTestExpectation(description: "Clear queue completes")

        // Act & Assert
        mockPlayer.clearQueue()
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
        XCTAssertTrue(mockPlayer.clearQueueWasCalled)
    }

    // MARK: - Queue Publishers Contract Tests

    func testQueuePublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Queue updates received")
        expectation.expectedFulfillmentCount = 2
        var queueUpdates: [[QueuedAudio]] = []

        // Act & Assert
        mockPlayer.queue
            .sink { queue in
                queueUpdates.append(queue)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate queue update
        let queuedAudio = QueuedAudio(
            url: URL(string: "https://example.com/audio.mp3")!,
            queuePosition: 0
        )
        mockPlayer.simulateQueueUpdate([queuedAudio])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(queueUpdates.count, 2)
        XCTAssertEqual(queueUpdates[0].count, 0) // Initial empty
        XCTAssertEqual(queueUpdates[1].count, 1) // One item added
    }

    func testCurrentQueueItemPublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Current item updates")
        expectation.expectedFulfillmentCount = 2

        // Act & Assert
        mockPlayer.currentQueueItem
            .sink { currentItem in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate current item update
        let currentItem = QueuedAudio(
            url: URL(string: "https://example.com/current.mp3")!,
            queuePosition: 0
        )
        mockPlayer.simulateCurrentItemUpdate(currentItem)

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Playback Mode Contract Tests

    func testAutoAdvanceEnabled() {
        // Arrange & Act
        mockPlayer.autoAdvanceEnabled = true

        // Assert
        XCTAssertTrue(mockPlayer.autoAdvanceEnabled)

        // Act
        mockPlayer.autoAdvanceEnabled = false

        // Assert
        XCTAssertFalse(mockPlayer.autoAdvanceEnabled)
    }

    func testRepeatMode() {
        // Test all repeat modes
        mockPlayer.repeatMode = .off
        XCTAssertEqual(mockPlayer.repeatMode, .off)

        mockPlayer.repeatMode = .one
        XCTAssertEqual(mockPlayer.repeatMode, .one)

        mockPlayer.repeatMode = .all
        XCTAssertEqual(mockPlayer.repeatMode, .all)
    }

    func testShuffleEnabled() {
        // Arrange & Act
        mockPlayer.shuffleEnabled = true

        // Assert
        XCTAssertTrue(mockPlayer.shuffleEnabled)

        // Act
        mockPlayer.shuffleEnabled = false

        // Assert
        XCTAssertFalse(mockPlayer.shuffleEnabled)
    }

    func testMoveQueueItem() {
        // Arrange
        let expectation = XCTestExpectation(description: "Move item completes")

        // Act & Assert
        mockPlayer.moveQueueItem(from: 0, to: 2)
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
        XCTAssertEqual(mockPlayer.lastMoveFrom, 0)
        XCTAssertEqual(mockPlayer.lastMoveTo, 2)
    }
}

// MARK: - Mock Implementation for Testing

private class MockAudioQueueManageable: AudioQueueManageable {
    // Track method calls
    var enqueuedItems: [QueuedAudio] = []
    var enqueuedNextItems: [QueuedAudio] = []
    var dequeuedIds: [UUID] = []
    var playNextWasCalled = false
    var playPreviousWasCalled = false
    var clearQueueWasCalled = false
    var lastMoveFrom: Int?
    var lastMoveTo: Int?

    // Queue properties
    var autoAdvanceEnabled: Bool = true
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    // AudioConfigurable properties (simplified)
    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    // Publishers
    private let queueSubject = CurrentValueSubject<[QueuedAudio], Never>([])
    private let currentQueueItemSubject = CurrentValueSubject<QueuedAudio?, Never>(nil)

    // Other required publishers (simplified)
    var playbackState: AnyPublisher<PlaybackState, Never> {
        Just(.idle).eraseToAnyPublisher()
    }
    var currentTime: AnyPublisher<TimeInterval, Never> {
        Just(0.0).eraseToAnyPublisher()
    }
    var duration: AnyPublisher<TimeInterval, Never> {
        Just(0.0).eraseToAnyPublisher()
    }
    var metadata: AnyPublisher<AudioMetadata?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    var bufferStatus: AnyPublisher<BufferStatus?, Never> {
        Just(nil).eraseToAnyPublisher()
    }

    var queue: AnyPublisher<[QueuedAudio], Never> {
        queueSubject.eraseToAnyPublisher()
    }

    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> {
        currentQueueItemSubject.eraseToAnyPublisher()
    }

    // AudioQueueManageable methods
    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        let queuedAudio = QueuedAudio(url: url, metadata: metadata, queuePosition: enqueuedItems.count)
        enqueuedItems.append(queuedAudio)
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        let queuedAudio = QueuedAudio(url: url, metadata: metadata, queuePosition: 0)
        enqueuedNextItems.append(queuedAudio)
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError> {
        dequeuedIds.append(queueId)
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func playNext() -> AnyPublisher<Void, AudioError> {
        playNextWasCalled = true
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func playPrevious() -> AnyPublisher<Void, AudioError> {
        playPreviousWasCalled = true
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func clearQueue() -> AnyPublisher<Void, AudioError> {
        clearQueueWasCalled = true
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError> {
        lastMoveFrom = from
        lastMoveTo = to
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // Simplified implementations of other required methods
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func play() -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func pause() -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // Test helpers
    func simulateQueueUpdate(_ queue: [QueuedAudio]) {
        queueSubject.send(queue)
    }

    func simulateCurrentItemUpdate(_ item: QueuedAudio?) {
        currentQueueItemSubject.send(item)
    }
}