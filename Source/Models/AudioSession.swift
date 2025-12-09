// AudioSession.swift - Represents an active audio playback session
// Swift 6 Sendable compliant value type for thread-safe session management

import Foundation

/// Represents an active audio playback session with reactive state management
/// This struct is Sendable for use across concurrency boundaries
public struct AudioSession: Sendable, Identifiable, Equatable {
    /// Unique session identifier
    public let id: UUID

    /// Source audio URL (remote or local)
    public let url: URL

    /// Optional metadata for display and organization
    public let metadata: AudioMetadata?

    /// Current playback status
    public let state: PlaybackState

    /// Current playback position in seconds
    public let progress: TimeInterval

    /// Total audio duration in seconds (may update for streaming)
    public let duration: TimeInterval

    /// When this session was created
    public let createdAt: Date

    /// When this session was last updated
    public let updatedAt: Date

    /// Creates a new audio session
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - url: Audio source URL
    ///   - metadata: Optional audio metadata
    ///   - state: Initial playback state (defaults to .idle)
    ///   - progress: Initial progress (defaults to 0)
    ///   - duration: Initial duration (defaults to 0, updates during streaming)
    ///   - createdAt: Creation timestamp (defaults to now)
    ///   - updatedAt: Update timestamp (defaults to now)
    public init(
        id: UUID = UUID(),
        url: URL,
        metadata: AudioMetadata? = nil,
        state: PlaybackState = .idle,
        progress: TimeInterval = 0.0,
        duration: TimeInterval = 0.0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.metadata = metadata
        self.state = state
        self.progress = progress
        self.duration = duration
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Creates a copy of this session with updated values
    /// - Parameters:
    ///   - state: New playback state
    ///   - progress: New progress position
    ///   - duration: New duration (optional)
    ///   - metadata: New metadata (optional)
    /// - Returns: Updated session copy
    public func updated(
        state: PlaybackState? = nil,
        progress: TimeInterval? = nil,
        duration: TimeInterval? = nil,
        metadata: AudioMetadata? = nil
    ) -> AudioSession {
        AudioSession(
            id: self.id,
            url: self.url,
            metadata: metadata ?? self.metadata,
            state: state ?? self.state,
            progress: progress ?? self.progress,
            duration: duration ?? self.duration,
            createdAt: self.createdAt,
            updatedAt: Date() // Always update timestamp
        )
    }

    /// Whether this session is currently active (playing or paused)
    public var isActive: Bool {
        switch state {
        case .playing, .paused, .buffering:
            return true
        case .idle, .loading, .ready, .completed, .error:
            return false
        }
    }

    /// Whether this session is ready for playback operations
    public var isReady: Bool {
        switch state {
        case .ready, .playing, .paused:
            return true
        case .idle, .loading, .buffering, .completed, .error:
            return false
        }
    }

    /// Progress as a percentage (0.0 to 1.0)
    public var progressPercentage: Double {
        guard duration > 0 else { return 0.0 }
        return min(max(progress / duration, 0.0), 1.0)
    }

    /// Remaining time in seconds
    public var remainingTime: TimeInterval {
        guard duration > progress else { return 0.0 }
        return duration - progress
    }
}

// MARK: - Equatable Implementation

extension AudioSession {
    public static func == (lhs: AudioSession, rhs: AudioSession) -> Bool {
        return lhs.id == rhs.id &&
               lhs.url == rhs.url &&
               lhs.state == rhs.state &&
               abs(lhs.progress - rhs.progress) < 0.1 && // Allow small time differences
               abs(lhs.duration - rhs.duration) < 0.1
    }
}

// MARK: - CustomStringConvertible

extension AudioSession: CustomStringConvertible {
    public var description: String {
        let title = metadata?.title ?? url.lastPathComponent
        let stateDesc = "\(state)"
        let timeDesc = String(format: "%.1f/%.1f", progress, duration)
        return "AudioSession[\(title): \(stateDesc) \(timeDesc)]"
    }
}

// MARK: - Hashable

extension AudioSession: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(url)
        hasher.combine(state)
        // Don't include progress/duration in hash as they change frequently
    }
}