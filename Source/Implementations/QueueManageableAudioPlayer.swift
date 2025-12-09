//
//  QueueManageableAudioPlayer.swift
//  Resonance
//
//  Enhanced audio player with queue and playlist management capabilities.
//  Provides comprehensive queue management with autoplay, shuffle, and repeat modes.
//

import Foundation
import Combine
import AVFoundation

/// Enhanced audio player with queue and playlist management capabilities
///
/// QueueManageableAudioPlayer extends ConfigurableAudioPlayer with AudioQueueManageable features,
/// enabling sophisticated playlist and queue management for music players and podcast apps.
///
/// **Enhanced usage pattern:**
/// ```swift
/// let player = QueueManageableAudioPlayer()
///
/// // Build a queue
/// try await player.enqueue(url: song1URL, metadata: song1Metadata).async()
/// try await player.enqueue(url: song2URL, metadata: song2Metadata).async()
///
/// // Configure playback behavior
/// player.repeatMode = .all
/// player.shuffleEnabled = true
/// player.autoAdvanceEnabled = true
///
/// // Start playback
/// try await player.play().async()
/// ```
///
/// This implementation:
/// - Inherits all AudioConfigurable functionality from ConfigurableAudioPlayer
/// - Implements AudioQueueManageable for comprehensive queue management
/// - Provides autoplay with queue navigation (next/previous)
/// - Supports repeat modes (off, one, all) and shuffle functionality
/// - Offers reactive publishers for queue state updates
/// - Maintains Swift 6 concurrency and Sendable compliance
@MainActor
public final class QueueManageableAudioPlayer: ConfigurableAudioPlayer, AudioQueueManageable, @unchecked Sendable {

    // MARK: - Queue State Management

    /// Current queue items
    private var queueItems: [QueuedAudio] = []

    /// Current playing queue item
    private var currentItem: QueuedAudio?

    /// Shuffled queue order (indices into queueItems)
    private var shuffledOrder: [Int] = []

    /// Current position in shuffled order
    private var shuffledPosition: Int = 0

    // MARK: - Queue Configuration

    /// Whether automatic advancement to next item is enabled
    public var autoAdvanceEnabled: Bool = true {
        didSet {
            if autoAdvanceEnabled != oldValue {
                setupAutoAdvanceHandling()
                emitQueueEvent(.autoAdvanceChanged(autoAdvanceEnabled))
            }
        }
    }

    /// Current repeat mode for queue playback
    public var repeatMode: RepeatMode = .off {
        didSet {
            if repeatMode != oldValue {
                emitQueueEvent(.repeatModeChanged(repeatMode))
            }
        }
    }

    /// Whether shuffle mode is currently enabled
    public var shuffleEnabled: Bool = false {
        didSet {
            if shuffleEnabled != oldValue {
                updateShuffleOrder()
                emitQueueEvent(.shuffleToggled(shuffleEnabled))
            }
        }
    }

    // MARK: - Reactive Publishers

    /// Queue items subject for reactive updates
    private let queueSubject = CurrentValueSubject<[QueuedAudio], Never>([])

    /// Current queue item subject
    private let currentQueueItemSubject = CurrentValueSubject<QueuedAudio?, Never>(nil)

    /// Queue events subject
    private let queueEventsSubject = PassthroughSubject<QueueEvent, Never>()

    /// Queue cancellables
    private var queueCancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize QueueManageableAudioPlayer with optional coordinator dependency injection
    /// - Parameter coordinator: Optional coordinator instance (defaults to shared)
    public override init(coordinator: ReactiveAudioCoordinator = .shared) {
        super.init(coordinator: coordinator)
        setupQueueBindings()
        setupAutoAdvanceHandling()
    }

    deinit {
        // Note: Cannot call cleanupQueue() from deinit due to @MainActor isolation
        // Cleanup is handled by ARC and the Set<AnyCancellable> will auto-cleanup
    }

    // MARK: - AudioQueueManageable Protocol Implementation

    /// Publisher that emits the current queue contents
    public var queue: AnyPublisher<[QueuedAudio], Never> {
        queueSubject.eraseToAnyPublisher()
    }

    /// Publisher that emits the currently playing/selected queue item
    public var currentQueueItem: AnyPublisher<QueuedAudio?, Never> {
        currentQueueItemSubject.eraseToAnyPublisher()
    }

    /// Adds an audio item to the end of the queue
    public func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                // Create new queue item
                let queueItem = QueuedAudio(
                    url: url,
                    metadata: metadata,
                    queuePosition: self.queueItems.count
                )

                // Add to queue
                self.queueItems.append(queueItem)
                self.updateQueuePositions()
                self.updateShuffleOrder()

                // If this is the first item and nothing is playing, set as current
                if self.currentItem == nil {
                    self.currentItem = queueItem
                    self.currentQueueItemSubject.send(queueItem)
                }

                // Emit updates
                self.queueSubject.send(self.queueItems)
                self.emitQueueEvent(.itemAdded(queueItem))

                #if DEBUG
                print("QueueManageableAudioPlayer: Enqueued '\(queueItem.displayName)'")
                #endif
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Adds an audio item to play immediately after the current item
    public func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                // Determine insertion position
                let insertPosition: Int
                if let currentItem = self.currentItem,
                   let currentIndex = self.queueItems.firstIndex(where: { $0.id == currentItem.id }) {
                    insertPosition = currentIndex + 1
                } else {
                    insertPosition = 0
                }

                // Create new queue item
                let queueItem = QueuedAudio(
                    url: url,
                    metadata: metadata,
                    queuePosition: insertPosition,
                    priority: 1 // Higher priority for "play next"
                )

                // Insert into queue
                self.queueItems.insert(queueItem, at: insertPosition)
                self.updateQueuePositions()
                self.updateShuffleOrder()

                // If no current item, set as current
                if self.currentItem == nil {
                    self.currentItem = queueItem
                    self.currentQueueItemSubject.send(queueItem)
                }

                // Emit updates
                self.queueSubject.send(self.queueItems)
                self.emitQueueEvent(.itemEnqueuedNext(queueItem))

                #if DEBUG
                print("[QueueManageableAudioPlayer] DEBUG: Enqueued next '\(queueItem.displayName)'")
                #endif
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Removes a specific item from the queue by its unique ID
    public func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                // Find and remove item
                guard let itemIndex = self.queueItems.firstIndex(where: { $0.id == queueId }) else {
                    #if DEBUG
                    print("QueueManageableAudioPlayer: Item to dequeue not found: \(queueId)")
                    #endif
                    promise(.success(()))
                    return
                }

                let removedItem = self.queueItems.remove(at: itemIndex)

                // Handle removal of current item
                if let currentItem = self.currentItem, currentItem.id == queueId {
                    // Try to advance to next item
                    if self.autoAdvanceEnabled {
                        self.performAutoAdvance()
                    } else {
                        // Just clear current item
                        self.currentItem = nil
                        self.currentQueueItemSubject.send(nil)
                        _ = try? await self.pause().async()
                    }
                }

                // Update positions and shuffle order
                self.updateQueuePositions()
                self.updateShuffleOrder()

                // Emit updates
                self.queueSubject.send(self.queueItems)
                self.emitQueueEvent(.itemRemoved(queueId))

                #if DEBUG
                print("QueueManageableAudioPlayer: Dequeued '\(removedItem.displayName)'")
                #endif
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Advances to the next item in the queue
    public func playNext() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    let nextItem: QueuedAudio? = self.getNextItem()

                    if let nextItem = nextItem {
                        // Load and potentially start playing the next item
                        try await self.loadQueueItem(nextItem)

                        let currentState = await self.playbackState.first().value
                        if currentState == .playing || currentState == .paused {
                            _ = await self.play().async()
                        }

                        self.emitQueueEvent(.advancedToNext(nextItem))
                        promise(.success(()))
                    } else {
                        // No next item available
                        self.emitQueueEvent(.queueCompleted)
                        promise(.success(()))
                    }

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to play next: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Goes back to the previous item in the queue
    public func playPrevious() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    let currentTime = await self.currentTime.first().value

                    // If we've played less than 5 seconds, go to actual previous
                    if currentTime < 5.0 {
                        let previousItem = self.getPreviousItem()

                        if let previousItem = previousItem {
                            try await self.loadQueueItem(previousItem)

                            let currentState = await self.playbackState.first().value
                            if currentState == .playing {
                                _ = await self.play().async()
                            }

                            self.emitQueueEvent(.wentBackToPrevious(previousItem))
                        } else {
                            // No previous item, restart current
                            _ = try await self.seek(to: 0).async()
                        }
                    } else {
                        // Restart current item
                        _ = try await self.seek(to: 0).async()
                    }

                    promise(.success(()))

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to play previous: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Removes all items from the queue
    public func clearQueue() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                // Clear queue
                self.queueItems.removeAll()
                self.shuffledOrder.removeAll()
                self.currentItem = nil

                // Stop playback
                _ = try? await self.pause().async()

                // Emit updates
                self.queueSubject.send([])
                self.currentQueueItemSubject.send(nil)
                self.emitQueueEvent(.queueCleared)

                #if DEBUG
                print("QueueManageableAudioPlayer: Queue cleared")
                #endif
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Moves a queue item from one position to another
    public func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                // Validate indices
                guard from >= 0, from < self.queueItems.count,
                      to >= 0, to < self.queueItems.count,
                      from != to else {
                    promise(.failure(.invalidInput("Invalid move indices: \(from) to \(to)")))
                    return
                }

                // Perform move
                let item = self.queueItems.remove(at: from)
                self.queueItems.insert(item, at: to)

                // Update positions and shuffle order
                self.updateQueuePositions()
                self.updateShuffleOrder()

                // Emit updates
                self.queueSubject.send(self.queueItems)
                self.emitQueueEvent(.itemMoved(from: from, to: to))

                #if DEBUG
                print("QueueManageableAudioPlayer: Moved item from \(from) to \(to)")
                #endif
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Queue Navigation Logic

    /// Get the next item based on current settings
    private func getNextItem() -> QueuedAudio? {
        guard !queueItems.isEmpty else { return nil }

        if repeatMode == .one {
            // Repeat current item
            return currentItem
        }

        if shuffleEnabled {
            return getNextShuffledItem()
        } else {
            return getNextSequentialItem()
        }
    }

    /// Get the previous item based on current settings
    private func getPreviousItem() -> QueuedAudio? {
        guard !queueItems.isEmpty else { return nil }

        if shuffleEnabled {
            return getPreviousShuffledItem()
        } else {
            return getPreviousSequentialItem()
        }
    }

    /// Get next item in sequential order
    private func getNextSequentialItem() -> QueuedAudio? {
        guard let currentItem = currentItem else {
            return queueItems.first
        }

        guard let currentIndex = queueItems.firstIndex(where: { $0.id == currentItem.id }) else {
            return queueItems.first
        }

        let nextIndex = currentIndex + 1

        if nextIndex < queueItems.count {
            return queueItems[nextIndex]
        } else if repeatMode == .all {
            return queueItems.first
        } else {
            return nil // End of queue
        }
    }

    /// Get previous item in sequential order
    private func getPreviousSequentialItem() -> QueuedAudio? {
        guard let currentItem = currentItem else {
            return queueItems.last
        }

        guard let currentIndex = queueItems.firstIndex(where: { $0.id == currentItem.id }) else {
            return queueItems.last
        }

        if currentIndex > 0 {
            return queueItems[currentIndex - 1]
        } else if repeatMode == .all {
            return queueItems.last
        } else {
            return nil // Beginning of queue
        }
    }

    /// Get next item in shuffled order
    private func getNextShuffledItem() -> QueuedAudio? {
        guard !shuffledOrder.isEmpty else { return nil }

        let nextPosition = (shuffledPosition + 1) % shuffledOrder.count

        if nextPosition == 0 && repeatMode == .off {
            return nil // End of shuffled queue
        }

        shuffledPosition = nextPosition
        let queueIndex = shuffledOrder[shuffledPosition]

        return queueIndex < queueItems.count ? queueItems[queueIndex] : nil
    }

    /// Get previous item in shuffled order
    private func getPreviousShuffledItem() -> QueuedAudio? {
        guard !shuffledOrder.isEmpty else { return nil }

        let previousPosition = shuffledPosition > 0 ? shuffledPosition - 1 : shuffledOrder.count - 1

        if shuffledPosition == 0 && repeatMode == .off {
            return nil // Beginning of shuffled queue
        }

        shuffledPosition = previousPosition
        let queueIndex = shuffledOrder[shuffledPosition]

        return queueIndex < queueItems.count ? queueItems[queueIndex] : nil
    }

    // MARK: - Queue Management Helpers

    /// Update queue positions after reordering
    private func updateQueuePositions() {
        for (index, _) in queueItems.enumerated() {
            queueItems[index] = queueItems[index].updated(queuePosition: index)
        }
    }

    /// Update shuffle order when queue changes or shuffle is toggled
    private func updateShuffleOrder() {
        if shuffleEnabled && !queueItems.isEmpty {
            shuffledOrder = Array(0..<queueItems.count).shuffled()

            // Try to maintain current position if possible
            if let currentItem = currentItem,
               let currentQueueIndex = queueItems.firstIndex(where: { $0.id == currentItem.id }),
               let shuffledIndex = shuffledOrder.firstIndex(of: currentQueueIndex) {
                shuffledPosition = shuffledIndex
            } else {
                shuffledPosition = 0
            }
        } else {
            shuffledOrder = []
            shuffledPosition = 0
        }
    }

    /// Load a queue item for playback
    private func loadQueueItem(_ item: QueuedAudio) async throws {
        currentItem = item
        currentQueueItemSubject.send(item)

        // Mark item as played
        if let itemIndex = queueItems.firstIndex(where: { $0.id == item.id }) {
            queueItems[itemIndex] = queueItems[itemIndex].updated(hasBeenPlayed: true)
            queueSubject.send(queueItems)
            emitQueueEvent(.itemPlayed(item.id))
        }

        // Load the audio
        _ = try await loadAudio(from: item.url, metadata: item.metadata).async()

        #if DEBUG
        print("QueueManageableAudioPlayer: Loaded queue item '\(item.displayName)'")
        #endif
    }

    /// Perform automatic advancement to next item
    private func performAutoAdvance() {
        Task { @MainActor in
            if let nextItem = getNextItem() {
                do {
                    try await loadQueueItem(nextItem)
                    _ = try await play().async()
                } catch {
                    print("QueueManageableAudioPlayer: Auto-advance failed: \(error)")
                }
            } else {
                // End of queue
                emitQueueEvent(.queueCompleted)
            }
        }
    }

    /// Emit a queue event
    private func emitQueueEvent(_ event: QueueEvent) {
        queueEventsSubject.send(event)
        #if DEBUG
        print("QueueManageableAudioPlayer: \(event.description)")
        #endif
    }

    // MARK: - Setup and Cleanup

    /// Setup reactive bindings for queue management
    private func setupQueueBindings() {
        // Initial empty state
        queueSubject.send([])
        currentQueueItemSubject.send(nil)
    }

    /// Setup auto-advance handling
    private func setupAutoAdvanceHandling() {
        // Cancel existing subscription
        queueCancellables.removeAll()

        if autoAdvanceEnabled {
            // Monitor playback state for auto-advance
            playbackState
                .sink { [weak self] state in
                    if state == .completed {
                        self?.performAutoAdvance()
                    }
                }
                .store(in: &queueCancellables)
        }
    }

    /// Cleanup queue-related resources
    private func cleanupQueue() {
        queueCancellables.removeAll()
        queueItems.removeAll()
        shuffledOrder.removeAll()
        currentItem = nil
    }
}

// MARK: - Convenience Extensions

extension QueueManageableAudioPlayer {

    /// Add multiple items to the queue at once
    public func enqueueAll(_ items: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<Void, AudioError> {
        let publishers = items.map { item in
            enqueue(url: item.url, metadata: item.metadata)
        }

        return Publishers.Sequence(sequence: publishers)
            .flatMap { $0 }
            .collect()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Replace the entire queue with new items
    public func replaceQueue(with items: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<Void, AudioError> {
        clearQueue()
            .flatMap { _ in
                self.enqueueAll(items)
            }
            .eraseToAnyPublisher()
    }

    /// Toggle shuffle mode on/off
    public func toggleShuffle() -> Bool {
        shuffleEnabled.toggle()
        return shuffleEnabled
    }

    /// Cycle through repeat modes
    public func cycleRepeatMode() -> RepeatMode {
        repeatMode = repeatMode.next
        return repeatMode
    }

    /// Get queue statistics
    public func queueStatistics() -> AnyPublisher<QueueStatistics, Never> {
        queue
            .map { queueItems in
                let totalItems = queueItems.count
                let playedItems = queueItems.filter { $0.hasBeenPlayed }.count
                let unplayedItems = totalItems - playedItems

                // Calculate total duration if metadata is available
                let totalDuration: TimeInterval? = {
                    let durations = queueItems.compactMap { $0.metadata?.duration }
                    guard durations.count == queueItems.count else { return nil }
                    return durations.reduce(0, +)
                }()

                let averageItemDuration: TimeInterval? = {
                    guard let total = totalDuration, totalItems > 0 else { return nil }
                    return total / TimeInterval(totalItems)
                }()

                return QueueStatistics(
                    totalItems: totalItems,
                    unplayedItems: unplayedItems,
                    playedItems: playedItems,
                    totalDuration: totalDuration,
                    averageItemDuration: averageItemDuration
                )
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Async Extension for TimeInterval


// MARK: - Logging Support


// MARK: - Documentation

/*
 DESIGN PRINCIPLES:

 1. COMPREHENSIVE QUEUE MANAGEMENT
    - Complete playlist functionality with add, remove, and reorder operations
    - Support for various repeat modes and shuffle algorithms
    - Configurable auto-advance and queue size limits
    - Smart "play next" vs "add to end" distinction

 2. PROGRESSIVE ENHANCEMENT
    - Builds upon ConfigurableAudioPlayer foundation
    - Adds queue management without breaking existing functionality
    - Compatible with any AudioConfigurable usage patterns
    - Maintains volume and playback rate controls alongside queue features

 3. REACTIVE QUEUE STATE
    - All queue state exposed through Combine publishers
    - Real-time updates for UI synchronization
    - Predictable state changes and event ordering
    - Queue events for analytics and logging

 4. FLEXIBLE PLAYBACK BEHAVIOR
    - Configurable auto-advance settings
    - Multiple repeat modes (off, one, all)
    - Intelligent shuffle algorithms
    - Smart previous behavior (restart vs actual previous)

 5. THREAD-SAFE QUEUE OPERATIONS
    - MainActor isolation ensures thread safety
    - Proper async/await patterns for queue operations
    - Atomic queue modifications where possible
    - Consistent state across all queue operations

 USAGE PATTERNS:

 Basic Queue Management:
 ```swift
 let player = QueueManageableAudioPlayer()

 // Add items to queue
 try await player.enqueue(url: song1URL, metadata: song1Metadata).async()
 try await player.enqueueNext(url: priorityURL, metadata: nil).async()

 // Configure playback behavior
 player.repeatMode = .all
 player.shuffleEnabled = true
 player.autoAdvanceEnabled = true

 // Start playbook
 try await player.play().async()
 ```

 Queue Navigation:
 ```swift
 // Manual navigation
 try await player.playNext().async()
 try await player.playPrevious().async()

 // Monitor queue state
 player.queue
     .sink { queueItems in
         updatePlaylistUI(with: queueItems)
     }
     .store(in: &cancellables)

 player.currentQueueItem
     .sink { currentItem in
         updateNowPlayingUI(with: currentItem)
     }
     .store(in: &cancellables)
 ```

 Bulk Operations:
 ```swift
 // Replace entire queue
 let playlistItems = songs.map { (url: $0.url, metadata: $0.metadata) }
 try await player.replaceQueue(with: playlistItems).async()

 // Clear and start fresh
 try await player.clearQueue().async()
 ```

 Queue Statistics:
 ```swift
 player.queueStatistics()
     .sink { stats in
         print("Queue: \(stats.totalItems) items, \(stats.unplayedItems) unplayed")
         if let duration = stats.formattedTotalDuration {
             print("Total duration: \(duration)")
         }
     }
     .store(in: &cancellables)
 ```

 IMPLEMENTATION NOTES:

 - Queue publishers emit current state immediately on subscription
 - Shuffle algorithms maintain current item position when possible
 - Repeat One mode restarts the current item, not advance
 - Previous behavior considers playback time (restart vs actual previous)
 - Queue reordering updates QueuedAudio.queuePosition values
 - Error handling preserves existing playback functionality
 - Memory management handles large queues efficiently
 - Auto-advance can be disabled for manual control
 - Queue events provide comprehensive activity logging
 - All operations maintain consistency across state changes

 QUEUE BEHAVIOR:

 Repeat Modes:
 - Off: Stop playback when queue ends
 - One: Repeat current item indefinitely
 - All: Repeat entire queue from beginning when it ends

 Shuffle Mode:
 - When enabled, items play in randomized order
 - Current item position is maintained when toggling shuffle
 - Shuffle order is regenerated when queue changes

 Auto-Advance:
 - When enabled, automatically plays next item when current ends
 - When disabled, playback stops at end of each item
 - Can be toggled during playbook without interruption

 Navigation:
 - Next: Advances to next item based on repeat/shuffle settings
 - Previous: Goes to previous item or restarts current (based on playback time)
 - Manual navigation overrides auto-advance behavior temporarily
 */