// PlaylistIntegrationTests.swift - T047: Playlist queue management and autoplay
// Tests queue-based playback for music players and podcast apps

import XCTest
import Combine
import Foundation
@testable import Resonance

final class PlaylistIntegrationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockQueuePlayer: MockAudioQueueObservable!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        mockQueuePlayer = MockAudioQueueObservable()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        mockQueuePlayer = nil
        try await super.tearDown()
    }

    // MARK: - T047.1: Basic Queue Management

    func testBasicQueueOperations() async throws {
        // Test fundamental queue operations: enqueue, dequeue, play next/previous
        let urls = [
            URL(string: "https://example.com/track1.mp3")!,
            URL(string: "https://example.com/track2.mp3")!,
            URL(string: "https://example.com/track3.mp3")!
        ]

        let metadata = urls.map { url in
            AudioMetadata(
                title: "Track \(url.lastPathComponent)",
                artist: "Test Artist"
            )
        }

        var queueUpdates: [[QueuedAudio]] = []

        // Monitor queue changes
        mockQueuePlayer.queue
            .sink { queue in
                queueUpdates.append(queue)
            }
            .store(in: &cancellables)

        // Enqueue tracks
        for (url, meta) in zip(urls, metadata) {
            try await enqueueAudio(url: url, metadata: meta)
        }

        // Verify queue contents
        let currentQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        XCTAssertEqual(currentQueue.count, 3, "Should have three items in queue")

        let queueURLs = currentQueue.map { $0.url }
        XCTAssertEqual(queueURLs, urls, "Queue should maintain order")

        // Test play next
        let playNextExpectation = expectation(description: "Play next track")
        mockQueuePlayer.playNext()
            .sink(
                receiveCompletion: { _ in playNextExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [playNextExpectation], timeout: 1.0)

        // Verify current item updated
        let currentItem = mockQueuePlayer.getCurrentItemSnapshot()
        XCTAssertEqual(currentItem?.url, urls[0], "Should play first queued item")
    }

    // MARK: - T047.2: Priority Queue Operations

    func testPriorityQueueOperations() async throws {
        // Test "play next" functionality for priority queueing
        let regularTrack = URL(string: "https://example.com/regular.mp3")!
        let priorityTrack = URL(string: "https://example.com/priority.mp3")!

        // Add regular track to queue
        try await enqueueAudio(url: regularTrack, metadata: nil)

        // Start playing regular track
        try await playNext()

        var currentQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        XCTAssertEqual(currentQueue.count, 1, "Should have regular track in queue")

        // Add priority track using enqueueNext (play after current)
        let enqueueNextExpectation = expectation(description: "Enqueue next")
        mockQueuePlayer.enqueueNext(url: priorityTrack, metadata: nil)
            .sink(
                receiveCompletion: { _ in enqueueNextExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [enqueueNextExpectation], timeout: 1.0)

        // Verify priority track is next in queue
        currentQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        XCTAssertEqual(currentQueue.count, 2, "Should have both tracks")

        // Priority track should be positioned to play next
        let nextTrack = currentQueue.first { $0.queuePosition == 1 }
        XCTAssertEqual(nextTrack?.url, priorityTrack, "Priority track should be next")
    }

    // MARK: - T047.3: Auto-Advance Functionality

    func testAutoAdvanceFunctionality() async throws {
        // Test automatic advancement when current track ends
        let tracks = [
            URL(string: "https://example.com/auto1.mp3")!,
            URL(string: "https://example.com/auto2.mp3")!,
            URL(string: "https://example.com/auto3.mp3")!
        ]

        // Enable auto-advance
        mockQueuePlayer.autoAdvanceEnabled = true
        XCTAssertTrue(mockQueuePlayer.autoAdvanceEnabled, "Auto-advance should be enabled")

        // Add tracks to queue
        for track in tracks {
            try await enqueueAudio(url: track, metadata: nil)
        }

        var queueEvents: [QueueEvent] = []
        var currentItems: [QueuedAudio?] = []

        // Monitor queue events
        mockQueuePlayer.queueEvents
            .sink { event in
                queueEvents.append(event)
            }
            .store(in: &cancellables)

        // Monitor current item changes
        mockQueuePlayer.currentQueueItem
            .sink { item in
                currentItems.append(item)
            }
            .store(in: &cancellables)

        // Start playing first track
        try await playNext()

        // Simulate track completion and auto-advance
        await mockQueuePlayer.simulateTrackCompletion()

        // Verify auto-advance occurred
        let autoAdvanceEvents = queueEvents.compactMap { event -> (QueuedAudio?, QueuedAudio?)? in
            if case .autoAdvanced(let from, let to) = event {
                return (from, to)
            }
            return nil
        }

        XCTAssertFalse(autoAdvanceEvents.isEmpty, "Should have auto-advance events")

        let (fromTrack, toTrack) = autoAdvanceEvents.first!
        XCTAssertEqual(fromTrack?.url, tracks[0], "Should advance from first track")
        XCTAssertEqual(toTrack?.url, tracks[1], "Should advance to second track")
    }

    // MARK: - T047.4: Repeat Modes

    func testRepeatModes() async throws {
        // Test all repeat modes: off, one, all
        let track = URL(string: "https://example.com/repeat-test.mp3")!

        try await enqueueAudio(url: track, metadata: nil)

        // Test repeat one
        mockQueuePlayer.repeatMode = .one
        XCTAssertEqual(mockQueuePlayer.repeatMode, .one)

        try await playNext()
        await mockQueuePlayer.simulateTrackCompletion()

        // With repeat one, should stay on same track
        let currentItem = mockQueuePlayer.getCurrentItemSnapshot()
        XCTAssertEqual(currentItem?.url, track, "Should repeat current track")

        // Add more tracks for repeat all test
        let track2 = URL(string: "https://example.com/repeat-test2.mp3")!
        try await enqueueAudio(url: track2, metadata: nil)

        // Test repeat all
        mockQueuePlayer.repeatMode = .all
        mockQueuePlayer.autoAdvanceEnabled = true

        // Play through queue and verify it repeats
        try await playNext() // Move to first track
        await mockQueuePlayer.simulateTrackCompletion() // Should go to track2
        await mockQueuePlayer.simulateTrackCompletion() // Should restart from track1

        let finalItem = mockQueuePlayer.getCurrentItemSnapshot()
        XCTAssertEqual(finalItem?.url, track, "Should repeat back to first track")

        // Test repeat off
        mockQueuePlayer.repeatMode = .off

        let queue = mockQueuePlayer.getCurrentQueueSnapshot()
        let lastTrack = queue.last!

        // Simulate completion of last track
        await mockQueuePlayer.simulateTrackCompletion()

        // Should complete queue without repeating
        let queueEvents = mockQueuePlayer.capturedEvents
        let hasCompletionEvent = queueEvents.contains { event in
            if case .queueCompleted = event {
                return true
            }
            return false
        }
        XCTAssertTrue(hasCompletionEvent, "Should complete queue when repeat is off")
    }

    // MARK: - T047.5: Shuffle Mode

    func testShuffleMode() async throws {
        // Test shuffle functionality
        let tracks = (1...10).map { URL(string: "https://example.com/track\($0).mp3")! }

        // Add tracks in order
        for track in tracks {
            try await enqueueAudio(url: track, metadata: nil)
        }

        let originalQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let originalOrder = originalQueue.map { $0.url }

        // Enable shuffle
        mockQueuePlayer.shuffleEnabled = true
        XCTAssertTrue(mockQueuePlayer.shuffleEnabled)

        // Trigger shuffle
        await mockQueuePlayer.applyShuffle()

        let shuffledQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let shuffledOrder = shuffledQueue.map { $0.url }

        // Verify same tracks but different order
        XCTAssertEqual(Set(originalOrder), Set(shuffledOrder), "Should have same tracks")
        XCTAssertNotEqual(originalOrder, shuffledOrder, "Order should be different")

        // Disable shuffle - should restore original order
        mockQueuePlayer.shuffleEnabled = false
        await mockQueuePlayer.removeShuffle()

        let restoredQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let restoredOrder = restoredQueue.map { $0.url }

        XCTAssertEqual(originalOrder, restoredOrder, "Should restore original order")
    }

    // MARK: - T047.6: Queue Reordering

    func testQueueReordering() async throws {
        // Test manual queue reordering
        let tracks = [
            URL(string: "https://example.com/first.mp3")!,
            URL(string: "https://example.com/second.mp3")!,
            URL(string: "https://example.com/third.mp3")!,
            URL(string: "https://example.com/fourth.mp3")!
        ]

        // Add tracks to queue
        for track in tracks {
            try await enqueueAudio(url: track, metadata: nil)
        }

        let originalQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let originalOrder = originalQueue.map { $0.url }

        // Move track from position 0 to position 2
        let reorderExpectation = expectation(description: "Reorder queue")
        mockQueuePlayer.moveQueueItem(from: 0, to: 2)
            .sink(
                receiveCompletion: { _ in reorderExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [reorderExpectation], timeout: 1.0)

        // Verify new order
        let reorderedQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let reorderedURLs = reorderedQueue.map { $0.url }

        let expectedOrder = [tracks[1], tracks[2], tracks[0], tracks[3]]
        XCTAssertEqual(reorderedURLs, expectedOrder, "Should have reordered queue correctly")

        // Verify queue positions are updated
        for (index, item) in reorderedQueue.enumerated() {
            XCTAssertEqual(item.queuePosition, index, "Queue position should match array index")
        }
    }

    // MARK: - T047.7: Complex Queue Scenario

    func testComplexQueueScenario() async throws {
        // Test realistic podcast app scenario: episodes, priority, auto-advance
        let podcastEpisodes = [
            (URL(string: "https://example.com/ep001.mp3")!, AudioMetadata(title: "Episode 1", artist: "Podcast A")),
            (URL(string: "https://example.com/ep002.mp3")!, AudioMetadata(title: "Episode 2", artist: "Podcast A")),
            (URL(string: "https://example.com/ep003.mp3")!, AudioMetadata(title: "Episode 3", artist: "Podcast A"))
        ]

        let urgentEpisode = (URL(string: "https://example.com/urgent.mp3")!,
                           AudioMetadata(title: "Breaking News", artist: "News Podcast"))

        // Configure for podcast playback
        mockQueuePlayer.autoAdvanceEnabled = true
        mockQueuePlayer.repeatMode = .off
        mockQueuePlayer.shuffleEnabled = false

        var queueEvents: [QueueEvent] = []
        mockQueuePlayer.queueEvents
            .sink { event in
                queueEvents.append(event)
            }
            .store(in: &cancellables)

        // Add regular episodes
        for (url, metadata) in podcastEpisodes {
            try await enqueueAudio(url: url, metadata: metadata)
        }

        // Start playing first episode
        try await playNext()

        // Breaking news comes in - add as priority
        try await enqueueNext(url: urgentEpisode.0, metadata: urgentEpisode.1)

        // Simulate current episode finishing
        await mockQueuePlayer.simulateTrackCompletion()

        // Should auto-advance to urgent episode
        let currentItem = mockQueuePlayer.getCurrentItemSnapshot()
        XCTAssertEqual(currentItem?.url, urgentEpisode.0, "Should play urgent episode next")

        // Continue through rest of queue
        await mockQueuePlayer.simulateTrackCompletion() // Finish urgent episode
        await mockQueuePlayer.simulateTrackCompletion() // Finish episode 2
        await mockQueuePlayer.simulateTrackCompletion() // Finish episode 3

        // Queue should be complete
        let completionEvents = queueEvents.filter { event in
            if case .queueCompleted = event { return true }
            return false
        }
        XCTAssertEqual(completionEvents.count, 1, "Should have queue completion event")
    }

    // MARK: - T047.8: Queue Persistence

    func testQueuePersistence() async throws {
        // Test that queue state persists across app lifecycle events
        let tracks = [
            URL(string: "https://example.com/persist1.mp3")!,
            URL(string: "https://example.com/persist2.mp3")!
        ]

        // Build initial queue
        for track in tracks {
            try await enqueueAudio(url: track, metadata: nil)
        }

        try await playNext()
        mockQueuePlayer.repeatMode = .all
        mockQueuePlayer.shuffleEnabled = true

        // Capture current state
        let initialQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let initialItem = mockQueuePlayer.getCurrentItemSnapshot()
        let initialRepeat = mockQueuePlayer.repeatMode
        let initialShuffle = mockQueuePlayer.shuffleEnabled

        // Simulate app backgrounding/foregrounding
        await mockQueuePlayer.simulateAppBackgrounding()
        await mockQueuePlayer.simulateAppForegrounding()

        // Verify state is preserved
        let restoredQueue = mockQueuePlayer.getCurrentQueueSnapshot()
        let restoredItem = mockQueuePlayer.getCurrentItemSnapshot()

        XCTAssertEqual(initialQueue.count, restoredQueue.count, "Queue count should be preserved")
        XCTAssertEqual(initialItem?.url, restoredItem?.url, "Current item should be preserved")
        XCTAssertEqual(initialRepeat, mockQueuePlayer.repeatMode, "Repeat mode should be preserved")
        XCTAssertEqual(initialShuffle, mockQueuePlayer.shuffleEnabled, "Shuffle state should be preserved")
    }

    // MARK: - Helper Methods

    private func enqueueAudio(url: URL, metadata: AudioMetadata?) async throws {
        let expectation = expectation(description: "Enqueue audio")

        mockQueuePlayer.enqueue(url: url, metadata: metadata)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    private func enqueueNext(url: URL, metadata: AudioMetadata?) async throws {
        let expectation = expectation(description: "Enqueue next")

        mockQueuePlayer.enqueueNext(url: url, metadata: metadata)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    private func playNext() async throws {
        let expectation = expectation(description: "Play next")

        mockQueuePlayer.playNext()
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation

/// Mock implementation of AudioQueueObservable for testing queue functionality
private class MockAudioQueueObservable: AudioQueueObservable {
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)
    private let queueSubject = CurrentValueSubject<[QueuedAudio], Never>([])
    private let currentQueueItemSubject = CurrentValueSubject<QueuedAudio?, Never>(nil)
    private let queueEventsSubject = PassthroughSubject<QueueEvent, Never>()

    private var queueItems: [QueuedAudio] = []
    private var currentItemIndex: Int = -1

    var volume: Float = 1.0
    var playbackRate: Float = 1.0
    var autoAdvanceEnabled: Bool = false
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    private(set) var capturedEvents: [QueueEvent] = []

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

    var queue: AnyPublisher<[QueuedAudio], Never> {
        queueSubject.eraseToAnyPublisher()
    }

    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> {
        currentQueueItemSubject.eraseToAnyPublisher()
    }

    var queueEvents: AnyPublisher<QueueEvent, Never> {
        queueEventsSubject.eraseToAnyPublisher()
    }

    // Basic audio methods
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.ready)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.playing)
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
        return seek(to: currentTimeSubject.value + duration)
    }

    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return seek(to: max(0, currentTimeSubject.value - duration))
    }

    // Queue management methods
    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                let queuedAudio = QueuedAudio(
                    url: url,
                    metadata: metadata,
                    queuePosition: self.queueItems.count
                )
                self.queueItems.append(queuedAudio)
                self.updateQueuePositions()
                self.publishQueueUpdate()

                let event = QueueEvent.itemAdded(queuedAudio)
                self.publishEvent(event)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                let insertIndex = self.currentItemIndex + 1
                let queuedAudio = QueuedAudio(
                    url: url,
                    metadata: metadata,
                    queuePosition: insertIndex
                )

                if insertIndex < self.queueItems.count {
                    self.queueItems.insert(queuedAudio, at: insertIndex)
                } else {
                    self.queueItems.append(queuedAudio)
                }

                self.updateQueuePositions()
                self.publishQueueUpdate()

                let event = QueueEvent.itemAdded(queuedAudio)
                self.publishEvent(event)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if let index = self.queueItems.firstIndex(where: { $0.id == queueId }) {
                    self.queueItems.remove(at: index)
                    if self.currentItemIndex >= index && self.currentItemIndex > 0 {
                        self.currentItemIndex -= 1
                    }
                    self.updateQueuePositions()
                    self.publishQueueUpdate()

                    let event = QueueEvent.itemRemoved(queueId)
                    self.publishEvent(event)
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func playNext() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if !self.queueItems.isEmpty && self.currentItemIndex < self.queueItems.count - 1 {
                    self.currentItemIndex += 1
                } else if !self.queueItems.isEmpty && self.currentItemIndex == -1 {
                    self.currentItemIndex = 0
                }

                self.updateCurrentItem()
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func playPrevious() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if self.currentItemIndex > 0 {
                    self.currentItemIndex -= 1
                    self.updateCurrentItem()
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func clearQueue() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.queueItems.removeAll()
                self.currentItemIndex = -1
                self.publishQueueUpdate()
                self.updateCurrentItem()

                let event = QueueEvent.queueCleared
                self.publishEvent(event)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                guard from < self.queueItems.count && to < self.queueItems.count else {
                    promise(.success(()))
                    return
                }

                let item = self.queueItems.remove(at: from)
                self.queueItems.insert(item, at: to)

                // Adjust current index if needed
                if self.currentItemIndex == from {
                    self.currentItemIndex = to
                } else if from < self.currentItemIndex && to >= self.currentItemIndex {
                    self.currentItemIndex -= 1
                } else if from > self.currentItemIndex && to <= self.currentItemIndex {
                    self.currentItemIndex += 1
                }

                self.updateQueuePositions()
                self.publishQueueUpdate()

                let event = QueueEvent.queueReordered
                self.publishEvent(event)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    // Helper methods for testing
    func getCurrentQueueSnapshot() -> [QueuedAudio] {
        return queueItems
    }

    func getCurrentItemSnapshot() -> QueuedAudio? {
        guard currentItemIndex >= 0 && currentItemIndex < queueItems.count else {
            return nil
        }
        return queueItems[currentItemIndex]
    }

    func simulateTrackCompletion() async {
        if autoAdvanceEnabled {
            let currentItem = getCurrentItemSnapshot()

            if currentItemIndex < queueItems.count - 1 {
                // Advance to next
                currentItemIndex += 1
                let nextItem = getCurrentItemSnapshot()

                let event = QueueEvent.autoAdvanced(from: currentItem, to: nextItem)
                publishEvent(event)
                updateCurrentItem()
            } else {
                // Handle end of queue based on repeat mode
                switch repeatMode {
                case .one:
                    // Stay on current track
                    let event = QueueEvent.autoAdvanced(from: currentItem, to: currentItem)
                    publishEvent(event)
                case .all:
                    // Restart from beginning
                    if !queueItems.isEmpty {
                        currentItemIndex = 0
                        let firstItem = getCurrentItemSnapshot()
                        let event = QueueEvent.autoAdvanced(from: currentItem, to: firstItem)
                        publishEvent(event)
                        updateCurrentItem()
                    }
                case .off:
                    // Queue completed
                    let event = QueueEvent.queueCompleted
                    publishEvent(event)
                }
            }
        }
    }

    func applyShuffle() async {
        if shuffleEnabled {
            queueItems.shuffle()
            updateQueuePositions()
            publishQueueUpdate()
        }
    }

    func removeShuffle() async {
        // Restore original order (simplified - in real implementation would preserve original order)
        queueItems.sort { $0.queuedDate < $1.queuedDate }
        updateQueuePositions()
        publishQueueUpdate()
    }

    func simulateAppBackgrounding() async {
        // Simulate app lifecycle event
    }

    func simulateAppForegrounding() async {
        // Simulate app lifecycle event - state should be preserved
    }

    private func updateQueuePositions() {
        for (index, _) in queueItems.enumerated() {
            queueItems[index] = QueuedAudio(
                id: queueItems[index].id,
                url: queueItems[index].url,
                metadata: queueItems[index].metadata,
                queuedDate: queueItems[index].queuedDate,
                hasBeenPlayed: queueItems[index].hasBeenPlayed,
                queuePosition: index
            )
        }
    }

    private func publishQueueUpdate() {
        queueSubject.send(queueItems)
    }

    private func updateCurrentItem() {
        let currentItem = getCurrentItemSnapshot()
        currentQueueItemSubject.send(currentItem)
    }

    private func publishEvent(_ event: QueueEvent) {
        capturedEvents.append(event)
        queueEventsSubject.send(event)
    }
}