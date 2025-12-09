// AudioPlayable.swift - Core Protocol for Basic Audio Playback
// Contract Test: Must verify play/pause/seek functionality

import Foundation
import Combine

/// Core protocol providing essential audio playback functionality
/// This is the simplest interface - enables 3-line integration for basic use cases
public protocol AudioPlayable {

    /// Load audio from URL and prepare for playback
    /// - Parameter url: Remote or local audio URL
    /// - Parameter metadata: Optional audio information for display
    /// - Returns: Publisher that completes when audio is ready or fails with error
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError>

    /// Start or resume audio playback
    /// - Returns: Publisher that completes when playback starts or fails
    func play() -> AnyPublisher<Void, AudioError>

    /// Pause audio playback
    /// - Returns: Publisher that completes when paused or fails
    func pause() -> AnyPublisher<Void, AudioError>

    /// Seek to specific time position
    /// - Parameter position: Target time in seconds
    /// - Returns: Publisher that completes when seek finishes or fails
    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError>

    /// Current playback state
    var playbackState: AnyPublisher<PlaybackState, Never> { get }

    /// Current playback position in seconds
    var currentTime: AnyPublisher<TimeInterval, Never> { get }

    /// Total audio duration in seconds (may update during streaming)
    var duration: AnyPublisher<TimeInterval, Never> { get }
}

// MARK: - Supporting Types

public struct AudioMetadata {
    public let title: String?
    public let artist: String?
    public let artwork: Data?
    public let chapters: [ChapterInfo]

    public init(title: String? = nil,
                artist: String? = nil,
                artwork: Data? = nil,
                chapters: [ChapterInfo] = []) {
        self.title = title
        self.artist = artist
        self.artwork = artwork
        self.chapters = chapters
    }
}

public struct ChapterInfo {
    public let title: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval

    public init(title: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
    }
}

public enum PlaybackState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case completed
    case error(AudioError)
}

public enum AudioError: Error {
    case invalidURL
    case networkFailure
    case audioFormatUnsupported
    case audioSessionError
    case seekOutOfBounds
    case internalError(String)
}