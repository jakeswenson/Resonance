// AudioQueueManageable.swift - Protocol for Playlist and Queue Management
// Contract Test: Must verify queue operations and automatic playback transitions

import Foundation
import Combine

/// Protocol for managing audio playlists and automatic playback queues
/// Enables podcast app features like autoplay next episode
public protocol AudioQueueManageable: AudioConfigurable {

    /// Add audio to the end of the playback queue
    /// - Parameter url: Audio URL to queue
    /// - Parameter metadata: Optional metadata for queued audio
    /// - Returns: Publisher that completes when audio is queued or fails
    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError>

    /// Add audio to the front of the playback queue (play next)
    /// - Parameter url: Audio URL to play next
    /// - Parameter metadata: Optional metadata for queued audio
    /// - Returns: Publisher that completes when audio is queued or fails
    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError>

    /// Remove audio from the queue
    /// - Parameter queueId: Unique identifier of queued item
    /// - Returns: Publisher that completes when item is removed or fails
    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError>

    /// Move to next audio in queue
    /// - Returns: Publisher that completes when next audio starts or fails
    func playNext() -> AnyPublisher<Void, AudioError>

    /// Move to previous audio in queue
    /// - Returns: Publisher that completes when previous audio starts or fails
    func playPrevious() -> AnyPublisher<Void, AudioError>

    /// Clear all queued audio
    /// - Returns: Publisher that completes when queue is cleared
    func clearQueue() -> AnyPublisher<Void, AudioError>

    /// Reorder queue items
    /// - Parameter from: Source index
    /// - Parameter to: Destination index
    /// - Returns: Publisher that completes when reorder finishes or fails
    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError>

    /// Current queue contents
    var queue: AnyPublisher<[QueuedAudio], Never> { get }

    /// Currently playing queue item (if any)
    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> { get }

    /// Whether queue should automatically advance to next item
    var autoAdvanceEnabled: Bool { get set }

    /// Queue repeat mode
    var repeatMode: RepeatMode { get set }

    /// Shuffle mode for queue playback
    var shuffleEnabled: Bool { get set }
}

// MARK: - Supporting Types

public struct QueuedAudio {
    /// Unique identifier for this queue item
    public let id: UUID

    /// Audio URL (remote or local)
    public let url: URL

    /// Associated metadata
    public let metadata: AudioMetadata?

    /// When this item was added to queue
    public let queuedDate: Date

    /// Whether this item has been played
    public let hasBeenPlayed: Bool

    /// Position in the current queue
    public let queuePosition: Int

    public init(id: UUID = UUID(),
                url: URL,
                metadata: AudioMetadata? = nil,
                queuedDate: Date = Date(),
                hasBeenPlayed: Bool = false,
                queuePosition: Int) {
        self.id = id
        self.url = url
        self.metadata = metadata
        self.queuedDate = queuedDate
        self.hasBeenPlayed = hasBeenPlayed
        self.queuePosition = queuePosition
    }
}

public enum RepeatMode: CaseIterable {
    /// No repeat - stop when queue ends
    case off

    /// Repeat current item indefinitely
    case one

    /// Repeat entire queue when it ends
    case all
}

/// Queue events for observing queue state changes
public enum QueueEvent {
    /// Item was added to queue
    case itemAdded(QueuedAudio)

    /// Item was removed from queue
    case itemRemoved(UUID)

    /// Queue was reordered
    case queueReordered

    /// Queue was cleared
    case queueCleared

    /// Automatically advanced to next item
    case autoAdvanced(from: QueuedAudio?, to: QueuedAudio?)

    /// Queue playback completed
    case queueCompleted
}

/// Extended protocol for observing queue events
public protocol AudioQueueObservable: AudioQueueManageable {
    /// Publisher for queue events
    var queueEvents: AnyPublisher<QueueEvent, Never> { get }
}