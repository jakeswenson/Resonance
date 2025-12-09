// AudioQueueManageable.swift - Protocol for playlist and queue management capabilities
// Swift 6 Sendable compliant protocol extending AudioConfigurable with queue functionality

import Foundation
import Combine

/// Enhanced protocol for audio queue and playlist management
///
/// AudioQueueManageable extends AudioConfigurable with sophisticated queue management capabilities
/// for building music players, podcast apps, and other applications requiring playlist functionality.
///
/// This protocol provides:
/// - Complete queue management (add, remove, reorder items)
/// - Autoplay and queue navigation (next/previous)
/// - Repeat modes (off, one, all) and shuffle functionality
/// - Reactive publishers for queue state updates
/// - Queue configuration and statistics
/// - Swift 6 Sendable compliance for concurrent usage
///
/// Usage example:
/// ```swift
/// let player = SomeAudioQueueManageable()
/// player.enqueue(url: audioURL, metadata: metadata)
/// player.repeatMode = .all
/// player.shuffleEnabled = true
/// player.play()
/// ```
@MainActor
public protocol AudioQueueManageable: AudioConfigurable {

    // MARK: - Queue Management Properties

    /// Whether automatic advancement to next item is enabled
    ///
    /// Controls whether the player automatically advances to the next queue item
    /// when the current item finishes playing. This is the primary control for
    /// continuous playback behavior.
    ///
    /// - Default: `true`
    /// - When `false`: Playback stops at the end of each item
    /// - When `true`: Automatically plays next item in queue
    var autoAdvanceEnabled: Bool { get set }

    /// Current repeat mode for queue playback
    ///
    /// Controls how the queue behaves when reaching the end:
    /// - `.off`: Stop playback when queue ends
    /// - `.one`: Repeat current item indefinitely
    /// - `.all`: Repeat entire queue when it ends
    ///
    /// Default is `.off`. Repeat behavior interacts with shuffle mode to provide
    /// expected user experience.
    var repeatMode: RepeatMode { get set }

    /// Whether shuffle mode is currently enabled
    ///
    /// When enabled, queue items are played in randomized order rather than
    /// sequential order. The shuffle algorithm should provide good distribution
    /// and avoid immediate repeats when possible.
    ///
    /// - Default: `false`
    /// - When `true`: Items played in randomized order
    /// - When `false`: Items played in queue order
    var shuffleEnabled: Bool { get set }

    // MARK: - Queue State Publishers

    /// Publisher that emits the current queue contents
    ///
    /// Emits the complete current queue as an array of QueuedAudio items.
    /// Initial state should be an empty array for new instances.
    /// Updates whenever items are added, removed, or reordered.
    ///
    /// The array is ordered by queue position, with index 0 being the next item to play.
    /// When shuffle is enabled, the array represents the shuffled order.
    ///
    /// - Returns: Publisher that never fails and emits [QueuedAudio] arrays
    var queue: AnyPublisher<[QueuedAudio], Never> { get }

    /// Publisher that emits the currently playing/selected queue item
    ///
    /// Emits the current queue item that is playing or selected for playback.
    /// Initial state should be `nil` for new instances.
    /// Updates when playback moves to a different queue item.
    ///
    /// This may be different from the first item in the queue array if the user
    /// manually selects a specific item or if shuffle mode affects playback order.
    ///
    /// - Returns: Publisher that never fails and emits QueuedAudio? values
    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> { get }

    // MARK: - Queue Management Methods

    /// Adds an audio item to the end of the queue
    ///
    /// Appends the specified URL with optional metadata to the end of the current queue.
    /// The item will be played after all currently queued items when auto-advance is enabled.
    ///
    /// The queue publisher will emit the updated queue once the item is successfully added.
    /// If the queue is empty and no audio is currently loaded, this may automatically
    /// load and prepare the added item for playback.
    ///
    /// - Parameters:
    ///   - url: Audio URL to add to queue (remote or local)
    ///   - metadata: Optional metadata for the audio item
    /// - Returns: Publisher that completes when item is enqueued or fails with AudioError
    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError>

    /// Adds an audio item to play immediately after the current item
    ///
    /// Inserts the specified URL at the front of the queue, making it the next item
    /// to play after the current item finishes. This is useful for "play next" functionality
    /// that doesn't interrupt current playback but takes priority over the existing queue.
    ///
    /// The queue publisher will emit the updated queue with the item inserted at position 0
    /// (or position 1 if current item is still in the queue).
    ///
    /// - Parameters:
    ///   - url: Audio URL to play next (remote or local)
    ///   - metadata: Optional metadata for the audio item
    /// - Returns: Publisher that completes when item is enqueued or fails with AudioError
    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError>

    /// Removes a specific item from the queue by its unique ID
    ///
    /// Removes the queue item with the specified ID from the current queue.
    /// If the removed item is currently playing, behavior depends on implementation:
    /// - May stop playback and advance to next item
    /// - May stop playback entirely if no next item exists
    ///
    /// The queue publisher will emit the updated queue once the item is removed.
    ///
    /// - Parameter queueId: Unique identifier of the item to remove
    /// - Returns: Publisher that completes when item is removed or fails with AudioError
    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError>

    /// Advances to the next item in the queue
    ///
    /// Immediately moves to and begins playing the next item in the queue.
    /// Behavior depends on current repeat mode and shuffle settings:
    /// - Normal: Plays next item in queue order
    /// - Shuffle: Plays next item in shuffled order
    /// - Repeat One: Restarts current item
    /// - End of queue with Repeat All: Starts over from beginning
    ///
    /// The currentQueueItem publisher will emit the new current item.
    /// If no next item is available, may emit completion or error.
    ///
    /// - Returns: Publisher that completes when advanced or fails with AudioError
    func playNext() -> AnyPublisher<Void, AudioError>

    /// Goes back to the previous item in the queue
    ///
    /// Moves to and begins playing the previous item in the queue.
    /// Behavior depends on current playback position and settings:
    /// - If current item played < 5 seconds: Go to actual previous item
    /// - If current item played > 5 seconds: Restart current item
    /// - At beginning of queue with Repeat All: Go to last item
    ///
    /// The currentQueueItem publisher will emit the new current item.
    ///
    /// - Returns: Publisher that completes when moved or fails with AudioError
    func playPrevious() -> AnyPublisher<Void, AudioError>

    /// Removes all items from the queue
    ///
    /// Clears the entire queue, removing all items except potentially the currently
    /// playing item (implementation-dependent). This is useful for starting fresh
    /// or switching to a completely different playlist.
    ///
    /// The queue publisher will emit an empty array once cleared.
    /// The currentQueueItem may be set to nil if current playback is also stopped.
    ///
    /// - Returns: Publisher that completes when queue is cleared or fails with AudioError
    func clearQueue() -> AnyPublisher<Void, AudioError>

    /// Moves a queue item from one position to another
    ///
    /// Reorders the queue by moving the item at the `from` index to the `to` index.
    /// This enables drag-and-drop reordering functionality in playlist UIs.
    /// All other items shift positions accordingly to maintain queue integrity.
    ///
    /// The queue publisher will emit the updated queue with new positions.
    /// Queue positions in QueuedAudio items will be updated to reflect the new order.
    ///
    /// - Parameters:
    ///   - from: Current index position of item to move
    ///   - to: Destination index position for the item
    /// - Returns: Publisher that completes when moved or fails with AudioError
    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError>
}

// MARK: - Protocol Extensions

extension AudioQueueManageable {

    /// Convenience method to add multiple items to the queue at once
    ///
    /// Efficiently adds multiple audio items to the queue in a single operation.
    /// Items are added in the order provided, maintaining the array sequence.
    /// This is more efficient than individual enqueue calls for bulk operations.
    ///
    /// - Parameter items: Array of (URL, AudioMetadata?) tuples to enqueue
    /// - Returns: Publisher that completes when all items are enqueued or fails with AudioError
    func enqueueAll(_ items: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<Void, AudioError> {
        let publishers = items.map { item in
            enqueue(url: item.url, metadata: item.metadata)
        }

        return publishers.publisher
            .flatMap { $0 }
            .collect()
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Convenience method to replace the entire queue with new items
    ///
    /// Clears the current queue and replaces it with the provided items in one operation.
    /// This is useful for loading new playlists or completely changing the queue content.
    /// Current playback may be interrupted depending on implementation.
    ///
    /// - Parameter items: Array of (URL, AudioMetadata?) tuples for the new queue
    /// - Returns: Publisher that completes when queue is replaced or fails with AudioError
    func replaceQueue(with items: [(url: URL, metadata: AudioMetadata?)]) -> AnyPublisher<Void, AudioError> {
        clearQueue()
            .flatMap { _ in
                self.enqueueAll(items)
            }
            .eraseToAnyPublisher()
    }

    /// Toggles shuffle mode on/off
    ///
    /// Convenience method to toggle shuffle mode between enabled and disabled states.
    /// When enabling shuffle, the queue order is randomized while preserving the current item.
    /// When disabling shuffle, the queue returns to its original insertion order.
    ///
    /// - Returns: New shuffle state after toggling
    mutating func toggleShuffle() -> Bool {
        shuffleEnabled.toggle()
        return shuffleEnabled
    }

    /// Cycles through repeat modes in order: off → all → one → off
    ///
    /// Convenience method for UI controls that cycle through repeat modes with a single button.
    /// The progression follows common user expectations for repeat mode cycling.
    ///
    /// - Returns: New repeat mode after cycling
    mutating func cycleRepeatMode() -> RepeatMode {
        repeatMode = repeatMode.next
        return repeatMode
    }

    /// Gets the next item that would play without actually advancing
    ///
    /// Determines what the next queue item would be based on current settings
    /// (shuffle, repeat mode, etc.) without changing the current playback state.
    /// Useful for "peek ahead" UI functionality.
    ///
    /// - Returns: Publisher that emits the next item or nil if none available
    func peekNext() -> AnyPublisher<QueuedAudio?, Never> {
        queue.combineLatest(currentQueueItem)
            .map { queue, currentItem in
                guard !queue.isEmpty else { return nil as QueuedAudio? }

                if let current = currentItem {
                    // Find current item index and determine next
                    if let currentIndex = queue.firstIndex(where: { $0.id == current.id }) {
                        let nextIndex = (currentIndex + 1) % queue.count

                        // Check if we can advance based on repeat mode
                        if nextIndex == 0 && self.repeatMode == .off {
                            return nil // End of queue, no repeat
                        }

                        return queue.indices.contains(nextIndex) ? queue[nextIndex] : nil
                    }
                }

                // No current item or not found in queue, return first item
                return queue.first
            }
            .eraseToAnyPublisher()
    }

    /// Gets the previous item that would play without actually going back
    ///
    /// Determines what the previous queue item would be based on current settings.
    /// Takes into account the "restart vs previous" behavior typically used in audio players.
    ///
    /// - Returns: Publisher that emits the previous item or current item if would restart
    func peekPrevious() -> AnyPublisher<QueuedAudio?, Never> {
        queue.combineLatest(currentQueueItem, currentTime)
            .map { queue, currentItem, currentTime in
                guard !queue.isEmpty, let current = currentItem else {
                    return queue.last
                }

                // If we've played less than 5 seconds, go to actual previous
                if currentTime < 5.0 {
                    if let currentIndex = queue.firstIndex(where: { $0.id == current.id }) {
                        if currentIndex > 0 {
                            return queue[currentIndex - 1]
                        } else if self.repeatMode == .all {
                            return queue.last // Wrap to end
                        }
                        return nil
                    }
                }

                // Otherwise, would restart current item
                return current
            }
            .eraseToAnyPublisher()
    }

    /// Gets queue statistics for analytics and UI display
    ///
    /// Provides comprehensive statistics about the current queue state, including
    /// item counts, play status, and duration information when available.
    ///
    /// - Returns: Publisher that emits current queue statistics
    func queueStatistics() -> AnyPublisher<QueueStatistics, Never> {
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

// MARK: - Supporting Types

/// Configuration for queue behavior and preferences
///
/// Encapsulates all queue-related settings in a single, immutable value type.
/// This enables easy saving/loading of queue preferences and state restoration.
public struct AudioQueueConfiguration: Sendable, Equatable, Hashable {
    /// Whether auto-advance is enabled
    public let autoAdvanceEnabled: Bool

    /// Current repeat mode
    public let repeatMode: RepeatMode

    /// Whether shuffle is enabled
    public let shuffleEnabled: Bool

    /// Maximum queue size (0 = unlimited)
    public let maxQueueSize: Int

    /// Whether to remove items after they've been played
    public let autoRemovePlayedItems: Bool

    /// Whether to prioritize unplayed items in shuffle mode
    public let prioritizeUnplayedInShuffle: Bool

    /// Creates a new queue configuration
    /// - Parameters:
    ///   - autoAdvanceEnabled: Whether to auto-advance between items
    ///   - repeatMode: Repeat behavior for the queue
    ///   - shuffleEnabled: Whether shuffle mode is active
    ///   - maxQueueSize: Maximum number of items (0 = unlimited)
    ///   - autoRemovePlayedItems: Whether to auto-remove played items
    ///   - prioritizeUnplayedInShuffle: Whether to prioritize unplayed in shuffle
    public init(
        autoAdvanceEnabled: Bool = true,
        repeatMode: RepeatMode = .off,
        shuffleEnabled: Bool = false,
        maxQueueSize: Int = 0,
        autoRemovePlayedItems: Bool = false,
        prioritizeUnplayedInShuffle: Bool = true
    ) {
        self.autoAdvanceEnabled = autoAdvanceEnabled
        self.repeatMode = repeatMode
        self.shuffleEnabled = shuffleEnabled
        self.maxQueueSize = max(0, maxQueueSize)
        self.autoRemovePlayedItems = autoRemovePlayedItems
        self.prioritizeUnplayedInShuffle = prioritizeUnplayedInShuffle
    }
}

/// Queue-related events for logging and analytics
///
/// Provides structured events for queue operations that can be used for
/// analytics, logging, debugging, and state synchronization.
public enum AudioQueueEvent: Sendable, Equatable, Hashable {
    /// Item was added to the queue
    case itemEnqueued(QueuedAudio)

    /// Item was added as "play next"
    case itemEnqueuedNext(QueuedAudio)

    /// Item was removed from the queue
    case itemDequeued(UUID)

    /// Queue was completely cleared
    case queueCleared

    /// Item order was changed
    case itemMoved(from: Int, to: Int)

    /// Advanced to next item
    case advancedToNext(QueuedAudio?)

    /// Went back to previous item
    case wentBackToPrevious(QueuedAudio?)

    /// Shuffle mode was toggled
    case shuffleToggled(Bool)

    /// Repeat mode was changed
    case repeatModeChanged(RepeatMode)

    /// Auto-advance setting was changed
    case autoAdvanceChanged(Bool)

    /// Queue reached the end with no repeat
    case queueEnded

    /// Human-readable description for logging
    public var description: String {
        switch self {
        case .itemEnqueued(let item):
            return "Enqueued: \(item.displayName)"
        case .itemEnqueuedNext(let item):
            return "Enqueued next: \(item.displayName)"
        case .itemDequeued(let id):
            return "Dequeued: \(id)"
        case .queueCleared:
            return "Queue cleared"
        case .itemMoved(let from, let to):
            return "Moved item from \(from) to \(to)"
        case .advancedToNext(let item):
            return "Advanced to: \(item?.displayName ?? "none")"
        case .wentBackToPrevious(let item):
            return "Previous: \(item?.displayName ?? "none")"
        case .shuffleToggled(let enabled):
            return "Shuffle: \(enabled ? "on" : "off")"
        case .repeatModeChanged(let mode):
            return "Repeat: \(mode.displayName)"
        case .autoAdvanceChanged(let enabled):
            return "Auto-advance: \(enabled ? "on" : "off")"
        case .queueEnded:
            return "Queue ended"
        }
    }
}

// MARK: - CustomStringConvertible

extension AudioQueueConfiguration: CustomStringConvertible {
    public var description: String {
        let components = [
            autoAdvanceEnabled ? "auto" : "manual",
            "repeat: \(repeatMode.displayName)",
            shuffleEnabled ? "shuffle" : "sequential",
            maxQueueSize > 0 ? "max: \(maxQueueSize)" : "unlimited"
        ]
        return "QueueConfig[\(components.joined(separator: ", "))]"
    }
}


// MARK: - Documentation Notes

/*
 DESIGN PRINCIPLES:

 1. PROGRESSIVE ENHANCEMENT
    - Extends AudioConfigurable with queue-specific functionality
    - Maintains all volume, rate, and configuration capabilities
    - Can be implemented alongside other protocol extensions

 2. REACTIVE QUEUE MANAGEMENT
    - All queue state exposed through Combine publishers
    - Real-time updates for UI synchronization
    - Predictable state changes and event ordering

 3. FLEXIBLE QUEUE BEHAVIOR
    - Support for various repeat modes and shuffle algorithms
    - Configurable auto-advance and queue size limits
    - Smart "play next" vs "add to end" distinction

 4. SWIFT 6 SENDABLE COMPLIANCE
    - All types are Sendable for concurrent access
    - MainActor isolation for UI thread safety
    - Thread-safe queue manipulation operations

 5. COMPREHENSIVE QUEUE OPERATIONS
    - Individual item management (add, remove, reorder)
    - Bulk operations for efficiency (enqueueAll, replaceQueue)
    - Navigation controls (next, previous, peek operations)
    - Queue analysis (statistics, current state)

 USAGE PATTERNS:

 Basic Queue Management:
 ```swift
 // Add items to queue
 player.enqueue(url: songURL, metadata: songMetadata)
 player.enqueueNext(url: priorityURL, metadata: nil) // Play next

 // Configure playback behavior
 player.repeatMode = .all
 player.shuffleEnabled = true
 player.autoAdvanceEnabled = true
 ```

 Queue Navigation:
 ```swift
 // Manual navigation
 player.playNext() // Skip to next
 player.playPrevious() // Go back or restart

 // Peek at upcoming items
 player.peekNext()
     .sink { nextItem in
         updateUpNextUI(with: nextItem)
     }
     .store(in: &cancellables)
 ```

 Queue Monitoring:
 ```swift
 // Monitor queue changes
 player.queue
     .sink { queueItems in
         updatePlaylistUI(with: queueItems)
     }
     .store(in: &cancellables)

 // Track current item
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
 player.replaceQueue(with: playlistItems)

 // Clear and start fresh
 player.clearQueue()
 ```

 IMPLEMENTATION GUIDELINES:

 - Queue publishers should emit current state immediately on subscription
 - Shuffle algorithms should avoid immediate repeats when possible
 - Repeat One mode should restart the current item, not advance
 - Previous behavior should consider playback time (restart vs actual previous)
 - Queue reordering should update QueuedAudio.queuePosition values
 - Error handling should be graceful and not corrupt queue state
 - Memory management should handle large queues efficiently
 - State persistence should be supported for queue restoration
 */