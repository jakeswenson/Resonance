// AudioConfigurable.swift - Intermediate Protocol for Audio Configuration
// Contract Test: Must verify volume, rate, and metadata management

import Foundation
import Combine

/// Intermediate protocol for audio configuration and management
/// Extends AudioPlayable with volume, playback rate, and enhanced metadata support
public protocol AudioConfigurable: AudioPlayable {

    /// Audio volume level (0.0 to 1.0)
    var volume: Float { get set }

    /// Playback rate (0.5 to 4.0, default 1.0)
    /// - Note: Rate changes preserve pitch for spoken content
    var playbackRate: Float { get set }

    /// Update metadata during playback (for dynamic content)
    /// - Parameter metadata: New metadata to apply
    /// - Returns: Publisher that completes when metadata is updated
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError>

    /// Skip forward by specified duration
    /// - Parameter duration: Time to skip forward in seconds
    /// - Returns: Publisher that completes when skip finishes or fails
    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError>

    /// Skip backward by specified duration
    /// - Parameter duration: Time to skip backward in seconds
    /// - Returns: Publisher that completes when skip finishes or fails
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError>

    /// Current audio metadata
    var metadata: AnyPublisher<AudioMetadata?, Never> { get }

    /// Streaming buffer status (if applicable)
    var bufferStatus: AnyPublisher<BufferStatus?, Never> { get }
}

// MARK: - Supporting Types

public struct BufferStatus {
    /// Buffered time range relative to current position
    public let bufferedRange: ClosedRange<TimeInterval>

    /// Whether enough content is buffered for smooth playback
    public let isReadyForPlaying: Bool

    /// Buffering progress as percentage (0.0 to 1.0)
    public let bufferingProgress: Double

    public init(bufferedRange: ClosedRange<TimeInterval>,
                isReadyForPlaying: Bool,
                bufferingProgress: Double) {
        self.bufferedRange = bufferedRange
        self.isReadyForPlaying = isReadyForPlaying
        self.bufferingProgress = bufferingProgress
    }
}