// QueueTypes.swift - Queue and playlist management types
// Swift 6 Sendable compliant types for audio queue management

import Foundation

/// Represents an item in the audio playback queue
/// This struct is Sendable for use across concurrency boundaries
public struct QueuedAudio: Sendable, Identifiable, Equatable, Hashable {
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

    /// Position in the current queue (0-based)
    public let queuePosition: Int

    /// Priority for playback ordering (higher = more important)
    public let priority: Int

    /// Whether this item should auto-advance to next
    public let autoAdvance: Bool

    /// Optional user-defined tags for categorization
    public let tags: Set<String>

    /// Creates a new queued audio item
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - url: Audio URL
    ///   - metadata: Associated metadata
    ///   - queuedDate: When item was queued
    ///   - hasBeenPlayed: Whether item has been played
    ///   - queuePosition: Position in queue
    ///   - priority: Playback priority
    ///   - autoAdvance: Whether to auto-advance after playing
    ///   - tags: User-defined tags
    public init(
        id: UUID = UUID(),
        url: URL,
        metadata: AudioMetadata? = nil,
        queuedDate: Date = Date(),
        hasBeenPlayed: Bool = false,
        queuePosition: Int,
        priority: Int = 0,
        autoAdvance: Bool = true,
        tags: Set<String> = []
    ) {
        self.id = id
        self.url = url
        self.metadata = metadata
        self.queuedDate = queuedDate
        self.hasBeenPlayed = hasBeenPlayed
        self.queuePosition = queuePosition
        self.priority = priority
        self.autoAdvance = autoAdvance
        self.tags = tags
    }

    /// Creates a copy with updated values
    /// - Parameters:
    ///   - metadata: Updated metadata
    ///   - hasBeenPlayed: Updated played status
    ///   - queuePosition: Updated queue position
    ///   - priority: Updated priority
    ///   - autoAdvance: Updated auto-advance setting
    ///   - tags: Updated tags
    /// - Returns: New queued audio item with updated values
    public func updated(
        metadata: AudioMetadata? = nil,
        hasBeenPlayed: Bool? = nil,
        queuePosition: Int? = nil,
        priority: Int? = nil,
        autoAdvance: Bool? = nil,
        tags: Set<String>? = nil
    ) -> QueuedAudio {
        QueuedAudio(
            id: self.id,
            url: self.url,
            metadata: metadata ?? self.metadata,
            queuedDate: self.queuedDate,
            hasBeenPlayed: hasBeenPlayed ?? self.hasBeenPlayed,
            queuePosition: queuePosition ?? self.queuePosition,
            priority: priority ?? self.priority,
            autoAdvance: autoAdvance ?? self.autoAdvance,
            tags: tags ?? self.tags
        )
    }

    /// Display name for this queued item
    public var displayName: String {
        return metadata?.displayTitle ?? url.lastPathComponent
    }

    /// Display artist for this queued item
    public var displayArtist: String {
        return metadata?.displayArtist ?? "Unknown Artist"
    }

    /// Whether this item is ready for playback
    public var isReadyForPlayback: Bool {
        // Check if it's a local file that exists, or assume remote URLs are accessible
        if url.isFileURL {
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true // Assume remote URLs are accessible
    }

    /// Time since this item was queued
    public var timeSinceQueued: TimeInterval {
        return Date().timeIntervalSince(queuedDate)
    }
}

// MARK: - RepeatMode

/// Queue repeat behavior options
/// This enum is Sendable for use across concurrency boundaries
public enum RepeatMode: String, Sendable, CaseIterable, Equatable, Hashable {
    /// No repeat - stop when queue ends
    case off

    /// Repeat current item indefinitely
    case one

    /// Repeat entire queue when it ends
    case all

    /// Display name for UI
    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .one: return "Repeat One"
        case .all: return "Repeat All"
        }
    }

    /// Icon name for UI representation
    public var iconName: String {
        switch self {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }

    /// Next repeat mode in cycle (for UI toggle)
    public var next: RepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
        }
    }
}

// MARK: - QueueEvent

/// Events that occur during queue management and playback
/// This enum is Sendable for use across concurrency boundaries
public enum QueueEvent: Sendable, Equatable, Hashable {
    /// Item was added to queue
    case itemAdded(QueuedAudio)

    /// Item was removed from queue
    case itemRemoved(UUID)

    /// Items were reordered in queue
    case queueReordered([UUID]) // Array of IDs in new order

    /// Queue was cleared of all items
    case queueCleared

    /// Automatically advanced to next item
    case autoAdvanced(from: QueuedAudio?, to: QueuedAudio?)

    /// Queue playback completed (no more items)
    case queueCompleted

    /// Shuffle mode was toggled
    case shuffleToggled(Bool)

    /// Repeat mode was changed
    case repeatModeChanged(RepeatMode)

    /// Current item changed (user selection or auto-advance)
    case currentItemChanged(QueuedAudio?)

    /// Item was marked as played
    case itemPlayed(UUID)

    /// Auto advance setting was changed
    case autoAdvanceChanged(Bool)

    /// Item was enqueued next
    case itemEnqueuedNext(QueuedAudio)

    /// Item was moved in queue
    case itemMoved(from: Int, to: Int)

    /// Went back to previous item
    case wentBackToPrevious(QueuedAudio?)

    /// Advanced to next item automatically
    case advancedToNext(QueuedAudio?)

    /// Display description for logging/debugging
    public var description: String {
        switch self {
        case .itemAdded(let item):
            return "Added '\(item.displayName)' to queue"
        case .itemRemoved(let id):
            return "Removed item \(id) from queue"
        case .queueReordered(let ids):
            return "Reordered queue (\(ids.count) items)"
        case .queueCleared:
            return "Cleared queue"
        case .autoAdvanced(let from, let to):
            let fromName = from?.displayName ?? "none"
            let toName = to?.displayName ?? "none"
            return "Auto-advanced from '\(fromName)' to '\(toName)'"
        case .queueCompleted:
            return "Queue playback completed"
        case .shuffleToggled(let enabled):
            return "Shuffle \(enabled ? "enabled" : "disabled")"
        case .repeatModeChanged(let mode):
            return "Repeat mode: \(mode.displayName)"
        case .currentItemChanged(let item):
            let name = item?.displayName ?? "none"
            return "Current item: '\(name)'"
        case .itemPlayed(let id):
            return "Item \(id) marked as played"
        case .autoAdvanceChanged(let enabled):
            return "Auto advance \(enabled ? "enabled" : "disabled")"
        case .itemEnqueuedNext(let item):
            return "Enqueued '\(item.displayName)' next"
        case .itemMoved(let from, let to):
            return "Moved item from \(from) to \(to)"
        case .wentBackToPrevious(let item):
            let name = item?.displayName ?? "none"
            return "Went back to previous item '\(name)'"
        case .advancedToNext(let item):
            let name = item?.displayName ?? "none"
            return "Advanced to next item '\(name)'"
        }
    }
}

// MARK: - QueueConfiguration

/// Configuration options for queue behavior
/// This struct is Sendable for use across concurrency boundaries
public struct QueueConfiguration: Sendable, Equatable, Hashable {
    /// Whether queue should automatically advance to next item
    public let autoAdvanceEnabled: Bool

    /// Queue repeat mode
    public let repeatMode: RepeatMode

    /// Whether shuffle mode is enabled
    public let shuffleEnabled: Bool

    /// Maximum number of items in queue (0 = unlimited)
    public let maxQueueSize: Int

    /// Whether to auto-remove played items
    public let autoRemovePlayedItems: Bool

    /// Whether to prioritize unplayed items
    public let prioritizeUnplayed: Bool

    /// Creates new queue configuration
    /// - Parameters:
    ///   - autoAdvanceEnabled: Whether to auto-advance
    ///   - repeatMode: Repeat behavior
    ///   - shuffleEnabled: Whether shuffle is active
    ///   - maxQueueSize: Maximum queue size
    ///   - autoRemovePlayedItems: Whether to auto-remove played items
    ///   - prioritizeUnplayed: Whether to prioritize unplayed items
    public init(
        autoAdvanceEnabled: Bool = true,
        repeatMode: RepeatMode = .off,
        shuffleEnabled: Bool = false,
        maxQueueSize: Int = 0,
        autoRemovePlayedItems: Bool = false,
        prioritizeUnplayed: Bool = true
    ) {
        self.autoAdvanceEnabled = autoAdvanceEnabled
        self.repeatMode = repeatMode
        self.shuffleEnabled = shuffleEnabled
        self.maxQueueSize = max(0, maxQueueSize)
        self.autoRemovePlayedItems = autoRemovePlayedItems
        self.prioritizeUnplayed = prioritizeUnplayed
    }

    /// Creates a copy with updated values
    /// - Parameters:
    ///   - autoAdvanceEnabled: Updated auto-advance setting
    ///   - repeatMode: Updated repeat mode
    ///   - shuffleEnabled: Updated shuffle setting
    ///   - maxQueueSize: Updated max queue size
    ///   - autoRemovePlayedItems: Updated auto-remove setting
    ///   - prioritizeUnplayed: Updated prioritize setting
    /// - Returns: New configuration with updated values
    public func updated(
        autoAdvanceEnabled: Bool? = nil,
        repeatMode: RepeatMode? = nil,
        shuffleEnabled: Bool? = nil,
        maxQueueSize: Int? = nil,
        autoRemovePlayedItems: Bool? = nil,
        prioritizeUnplayed: Bool? = nil
    ) -> QueueConfiguration {
        QueueConfiguration(
            autoAdvanceEnabled: autoAdvanceEnabled ?? self.autoAdvanceEnabled,
            repeatMode: repeatMode ?? self.repeatMode,
            shuffleEnabled: shuffleEnabled ?? self.shuffleEnabled,
            maxQueueSize: maxQueueSize ?? self.maxQueueSize,
            autoRemovePlayedItems: autoRemovePlayedItems ?? self.autoRemovePlayedItems,
            prioritizeUnplayed: prioritizeUnplayed ?? self.prioritizeUnplayed
        )
    }
}

// MARK: - QueueStatistics

/// Statistics about queue usage and playback
/// This struct is Sendable for use across concurrency boundaries
public struct QueueStatistics: Sendable, Equatable {
    /// Total number of items currently in queue
    public let totalItems: Int

    /// Number of unplayed items
    public let unplayedItems: Int

    /// Number of played items
    public let playedItems: Int

    /// Total duration of all items (if known)
    public let totalDuration: TimeInterval?

    /// Average item duration (if calculable)
    public let averageItemDuration: TimeInterval?

    /// When these statistics were calculated
    public let calculatedAt: Date

    /// Creates new queue statistics
    /// - Parameters:
    ///   - totalItems: Total queue items
    ///   - unplayedItems: Unplayed items count
    ///   - playedItems: Played items count
    ///   - totalDuration: Total duration if known
    ///   - averageItemDuration: Average duration if calculable
    ///   - calculatedAt: Calculation timestamp
    public init(
        totalItems: Int,
        unplayedItems: Int,
        playedItems: Int,
        totalDuration: TimeInterval? = nil,
        averageItemDuration: TimeInterval? = nil,
        calculatedAt: Date = Date()
    ) {
        self.totalItems = totalItems
        self.unplayedItems = unplayedItems
        self.playedItems = playedItems
        self.totalDuration = totalDuration
        self.averageItemDuration = averageItemDuration
        self.calculatedAt = calculatedAt
    }

    /// Percentage of items that have been played (0.0 to 1.0)
    public var playedPercentage: Double {
        guard totalItems > 0 else { return 0.0 }
        return Double(playedItems) / Double(totalItems)
    }

    /// Formatted total duration string
    public var formattedTotalDuration: String? {
        guard let duration = totalDuration else { return nil }
        return TimeInterval.formatDuration(duration)
    }
}

// MARK: - CustomStringConvertible

extension QueuedAudio: CustomStringConvertible {
    public var description: String {
        let playedText = hasBeenPlayed ? " (played)" : ""
        return "\(displayName)\(playedText)"
    }
}


extension QueueConfiguration: CustomStringConvertible {
    public var description: String {
        let autoText = autoAdvanceEnabled ? "auto" : "manual"
        let shuffleText = shuffleEnabled ? ", shuffle" : ""
        return "QueueConfig[\(autoText), \(repeatMode.displayName)\(shuffleText)]"
    }
}

extension QueueStatistics: CustomStringConvertible {
    public var description: String {
        let durationText = formattedTotalDuration.map { " (\($0))" } ?? ""
        return "QueueStats[\(totalItems) items, \(unplayedItems) unplayed\(durationText)]"
    }
}

// MARK: - Hashable Implementation for QueueEvent

extension QueueEvent {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .itemAdded(let item):
            hasher.combine("itemAdded")
            hasher.combine(item.id)
        case .itemRemoved(let id):
            hasher.combine("itemRemoved")
            hasher.combine(id)
        case .queueReordered(let ids):
            hasher.combine("queueReordered")
            hasher.combine(ids)
        case .queueCleared:
            hasher.combine("queueCleared")
        case .autoAdvanced(let from, let to):
            hasher.combine("autoAdvanced")
            hasher.combine(from?.id)
            hasher.combine(to?.id)
        case .queueCompleted:
            hasher.combine("queueCompleted")
        case .shuffleToggled(let enabled):
            hasher.combine("shuffleToggled")
            hasher.combine(enabled)
        case .repeatModeChanged(let mode):
            hasher.combine("repeatModeChanged")
            hasher.combine(mode)
        case .currentItemChanged(let item):
            hasher.combine("currentItemChanged")
            hasher.combine(item?.id)
        case .itemPlayed(let id):
            hasher.combine("itemPlayed")
            hasher.combine(id)
        case .autoAdvanceChanged(let enabled):
            hasher.combine("autoAdvanceChanged")
            hasher.combine(enabled)
        case .itemEnqueuedNext(let item):
            hasher.combine("itemEnqueuedNext")
            hasher.combine(item.id)
        case .itemMoved(let from, let to):
            hasher.combine("itemMoved")
            hasher.combine(from)
            hasher.combine(to)
        case .wentBackToPrevious(let item):
            hasher.combine("wentBackToPrevious")
            hasher.combine(item?.id)
        case .advancedToNext(let item):
            hasher.combine("advancedToNext")
            hasher.combine(item?.id)
        }
    }
}