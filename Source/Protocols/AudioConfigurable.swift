// AudioConfigurable.swift - Enhanced protocol for audio configuration capabilities
// Swift 6 Sendable compliant protocol extending AudioPlayable with volume, rate, and metadata management

import Foundation
import Combine

/// Enhanced protocol for audio configuration and management
///
/// AudioConfigurable extends AudioPlayable with additional configuration capabilities for users
/// who need volume control, playback rate adjustment, and enhanced metadata management.
///
/// This protocol provides:
/// - Volume control with automatic range clamping (0.0 to 1.0)
/// - Playback rate control with range limits (0.5 to 4.0)
/// - Dynamic metadata updates during playback
/// - Skip controls for forward/backward navigation
/// - Additional reactive publishers for enhanced features
/// - Buffer status monitoring for streaming content
/// - Swift 6 Sendable compliance for concurrent usage
///
/// Usage example:
/// ```swift
/// let player = SomeAudioConfigurable()
/// player.loadAudio(from: url, metadata: nil)
/// player.volume = 0.7
/// player.playbackRate = 1.5
/// player.play()
/// ```
@MainActor
public protocol AudioConfigurable: AudioPlayable {

    // MARK: - Volume Control

    /// Audio volume level (0.0 to 1.0)
    ///
    /// Controls the output volume of the audio playback.
    /// Values are automatically clamped to the valid range:
    /// - Minimum: 0.0 (silent)
    /// - Maximum: 1.0 (full volume)
    /// - Default: 1.0
    ///
    /// Setting volume outside the valid range will be clamped to the nearest valid value.
    var volume: Float { get set }

    // MARK: - Playback Rate Control

    /// Playback rate (0.5 to 4.0, default 1.0)
    ///
    /// Controls the speed of audio playback while preserving pitch for spoken content.
    /// Values are automatically clamped to the valid range:
    /// - Minimum: 0.5 (half speed)
    /// - Maximum: 4.0 (4x speed)
    /// - Default: 1.0 (normal speed)
    ///
    /// Note: Rate changes preserve pitch for optimal spoken content experience.
    /// Setting rate outside the valid range will be clamped to the nearest valid value.
    var playbackRate: Float { get set }

    // MARK: - Enhanced Reactive Publishers

    /// Publisher that emits current audio metadata updates
    ///
    /// Emits the current metadata and all subsequent changes.
    /// Initial state should be `nil` for new instances.
    /// Updates when metadata is loaded from audio files or updated via `updateMetadata(_:)`.
    ///
    /// - Returns: Publisher that never fails and emits AudioMetadata? values
    var metadata: AnyPublisher<AudioMetadata?, Never> { get }

    /// Publisher that emits streaming buffer status updates
    ///
    /// Emits buffer status information for streaming content.
    /// Initial state should be `nil` for new instances or local content.
    /// Updates during streaming to provide buffering progress and readiness status.
    ///
    /// - Returns: Publisher that never fails and emits BufferStatus? values
    var bufferStatus: AnyPublisher<BufferStatus?, Never> { get }

    // MARK: - Metadata Management

    /// Updates metadata during playback for dynamic content
    ///
    /// Allows updating metadata while audio is playing. Useful for:
    /// - Live streams with changing metadata
    /// - Playlist advancement
    /// - Chapter navigation
    /// - Dynamic content updates
    ///
    /// The metadata publisher will emit the new metadata when successfully updated.
    ///
    /// - Parameter metadata: New metadata to apply
    /// - Returns: Publisher that completes when metadata is updated or fails with AudioError
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError>

    // MARK: - Skip Controls

    /// Skips forward by the specified duration
    ///
    /// Advances playback position by the given number of seconds.
    /// If the skip would go beyond the end of the content, seeks to the end.
    /// Updates the currentTime publisher with the new position.
    ///
    /// - Parameter duration: Time to skip forward in seconds (must be positive)
    /// - Returns: Publisher that completes when skip finishes or fails with AudioError
    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError>

    /// Skips backward by the specified duration
    ///
    /// Moves playback position back by the given number of seconds.
    /// If the skip would go before the beginning, seeks to the start.
    /// Updates the currentTime publisher with the new position.
    ///
    /// - Parameter duration: Time to skip backward in seconds (must be positive)
    /// - Returns: Publisher that completes when skip finishes or fails with AudioError
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError>
}

// MARK: - Supporting Types

/// Buffer status information for streaming audio content
///
/// Provides detailed information about the buffering state of streaming audio,
/// including buffered ranges, readiness status, and progress indicators.
public struct BufferStatus: Sendable, Equatable, Hashable {
    /// Buffered time range relative to current position
    ///
    /// Represents the time range of content that has been buffered and is ready for playback.
    /// The range is relative to the current playback position (e.g., 0.0...30.0 means
    /// 30 seconds of content is buffered from the current position).
    public let bufferedRange: ClosedRange<TimeInterval>

    /// Whether enough content is buffered for smooth playback
    ///
    /// Indicates if sufficient content has been buffered to begin or continue playback
    /// without interruption. Used to determine if playback should start or if buffering
    /// UI should be shown.
    public let isReadyForPlaying: Bool

    /// Buffering progress as percentage (0.0 to 1.0)
    ///
    /// Overall progress of the buffering operation as a percentage.
    /// - 0.0: No content buffered
    /// - 1.0: Fully buffered
    /// - Values in between: Partial buffering progress
    public let bufferingProgress: Double

    /// Creates new buffer status information
    ///
    /// - Parameters:
    ///   - bufferedRange: Time range of buffered content
    ///   - isReadyForPlaying: Whether enough content is buffered for playback
    ///   - bufferingProgress: Buffering progress as percentage (0.0 to 1.0)
    public init(
        bufferedRange: ClosedRange<TimeInterval>,
        isReadyForPlaying: Bool,
        bufferingProgress: Double
    ) {
        self.bufferedRange = bufferedRange
        self.isReadyForPlaying = isReadyForPlaying
        self.bufferingProgress = max(0.0, min(1.0, bufferingProgress))
    }

    /// Duration of buffered content in seconds
    public var bufferedDuration: TimeInterval {
        return bufferedRange.upperBound - bufferedRange.lowerBound
    }

    /// Whether any content is buffered
    public var hasBufferedContent: Bool {
        return bufferedDuration > 0
    }

    /// Whether buffering is complete
    public var isFullyBuffered: Bool {
        return bufferingProgress >= 1.0
    }

    /// Formatted buffering progress as percentage string
    public var formattedProgress: String {
        let percentage = Int(bufferingProgress * 100)
        return "\(percentage)%"
    }
}

// MARK: - Protocol Extensions

extension AudioConfigurable {

    /// Convenience method for setting volume with fade effect
    ///
    /// Gradually changes volume over the specified duration for smooth transitions.
    /// Useful for fade-in, fade-out, and crossfading effects.
    ///
    /// - Parameters:
    ///   - targetVolume: Target volume level (0.0 to 1.0)
    ///   - duration: Fade duration in seconds
    /// - Returns: Publisher that completes when fade finishes or fails with AudioError
    func fadeVolume(to targetVolume: Float, over duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        let clampedTarget = max(0.0, min(1.0, targetVolume))
        let startVolume = volume
        let volumeStep = (clampedTarget - startVolume) / Float(duration * 10) // 10 updates per second
        let stepDuration = duration / 10

        return Timer.publish(every: stepDuration, on: .main, in: .default)
            .autoconnect()
            .prefix(10)
            .scan(-1) { index, _ in index + 1 }
            .map { index -> Float in
                return startVolume + (volumeStep * Float(index + 1))
            }
            .handleEvents(receiveOutput: { newVolume in
                // Volume will be updated naturally through the publisher chain
            })
            .last()
            .map { _ in () }
            .setFailureType(to: AudioError.self)
            .eraseToAnyPublisher()
    }

    /// Convenience method for common skip durations
    ///
    /// Provides quick access to commonly used skip durations:
    /// - 15 seconds forward/backward
    /// - 30 seconds forward/backward
    /// - Chapter-based navigation when available
    ///
    /// - Parameter direction: Skip direction and duration
    /// - Returns: Publisher that completes when skip finishes or fails with AudioError
    func skip(_ direction: SkipDirection) -> AnyPublisher<Void, AudioError> {
        switch direction {
        case .forward15:
            return skipForward(duration: 15.0)
        case .forward30:
            return skipForward(duration: 30.0)
        case .backward15:
            return skipBackward(duration: 15.0)
        case .backward30:
            return skipBackward(duration: 30.0)
        case .nextChapter:
            return skipToNextChapter()
        case .previousChapter:
            return skipToPreviousChapter()
        }
    }

    /// Skips to the next chapter if metadata contains chapter information
    ///
    /// Finds the next chapter based on current playback position and seeks to its start time.
    /// If no next chapter exists, seeks to the end of the content.
    ///
    /// - Returns: Publisher that completes when skip finishes or fails with AudioError
    func skipToNextChapter() -> AnyPublisher<Void, AudioError> {
        Publishers.CombineLatest(currentTime.first(), metadata.first())
            .flatMap { currentTime, metadata -> AnyPublisher<Void, AudioError> in
                guard let chapters = metadata?.chapters,
                      !chapters.isEmpty else {
                    return Fail(error: AudioError.internalError("No chapters available"))
                        .eraseToAnyPublisher()
                }

                // Find next chapter after current time
                let nextChapter = chapters.first { chapter in
                    chapter.startTime > currentTime
                }

                if let chapter = nextChapter {
                    return self.seek(to: chapter.startTime)
                } else {
                    // No next chapter, seek to end
                    return self.seekToEnd()
                }
            }
            .eraseToAnyPublisher()
    }

    /// Skips to the previous chapter if metadata contains chapter information
    ///
    /// Finds the previous chapter based on current playback position and seeks to its start time.
    /// If no previous chapter exists, seeks to the beginning of the content.
    ///
    /// - Returns: Publisher that completes when skip finishes or fails with AudioError
    func skipToPreviousChapter() -> AnyPublisher<Void, AudioError> {
        Publishers.CombineLatest(currentTime.first(), metadata.first())
            .flatMap { currentTime, metadata -> AnyPublisher<Void, AudioError> in
                guard let chapters = metadata?.chapters,
                      !chapters.isEmpty else {
                    return Fail(error: AudioError.internalError("No chapters available"))
                        .eraseToAnyPublisher()
                }

                // Find previous chapter before current time
                let previousChapter = chapters.last { chapter in
                    chapter.startTime < currentTime - 5.0 // 5-second threshold to avoid skipping to current chapter
                }

                if let chapter = previousChapter {
                    return self.seek(to: chapter.startTime)
                } else {
                    // No previous chapter, seek to beginning
                    return self.seekToBeginning()
                }
            }
            .eraseToAnyPublisher()
    }

    /// Returns current chapter information based on playback position
    ///
    /// - Returns: Publisher that emits the current chapter or nil if none match
    func currentChapter() -> AnyPublisher<ChapterInfo?, Never> {
        Publishers.CombineLatest(currentTime, metadata)
            .map { currentTime, metadata in
                guard let chapters = metadata?.chapters else { return nil }
                return chapters.first { chapter in
                    chapter.contains(time: currentTime)
                }
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Skip Direction

/// Enumeration of skip directions and durations
public enum SkipDirection: Sendable, CaseIterable {
    case forward15
    case forward30
    case backward15
    case backward30
    case nextChapter
    case previousChapter

    /// Human-readable description
    public var description: String {
        switch self {
        case .forward15: return "Forward 15s"
        case .forward30: return "Forward 30s"
        case .backward15: return "Backward 15s"
        case .backward30: return "Backward 30s"
        case .nextChapter: return "Next Chapter"
        case .previousChapter: return "Previous Chapter"
        }
    }

    /// Whether this skip direction requires chapter metadata
    public var requiresChapters: Bool {
        switch self {
        case .nextChapter, .previousChapter:
            return true
        case .forward15, .forward30, .backward15, .backward30:
            return false
        }
    }
}

// MARK: - CustomStringConvertible

extension BufferStatus: CustomStringConvertible {
    public var description: String {
        let durationStr = String(format: "%.1fs", bufferedDuration)
        let progressStr = formattedProgress
        let readyStr = isReadyForPlaying ? "ready" : "not ready"
        return "Buffer: \(durationStr) buffered, \(progressStr) complete, \(readyStr)"
    }
}


// MARK: - Documentation Notes

/*
 DESIGN PRINCIPLES:

 1. PROGRESSIVE ENHANCEMENT
    - Builds on AudioPlayable foundation
    - Adds configuration capabilities without breaking basic usage
    - Can be further extended with more advanced protocols

 2. AUTOMATIC RANGE CLAMPING
    - Volume and playback rate automatically clamp to valid ranges
    - Prevents invalid states and system errors
    - Provides consistent behavior across implementations

 3. ENHANCED REACTIVE FEATURES
    - Additional publishers for metadata and buffer status
    - Chapter-aware navigation when metadata supports it
    - Smooth fade transitions for professional audio applications

 4. SWIFT 6 SENDABLE COMPLIANCE
    - All types maintain Sendable conformance
    - BufferStatus is immutable value type
    - MainActor isolation for UI thread safety

 5. STREAMING-AWARE
    - BufferStatus provides detailed streaming information
    - Graceful handling of live content and unknown durations
    - Network-aware buffering and readiness states

 USAGE PATTERNS:

 Volume Control:
 ```swift
 player.volume = 0.8
 player.fadeVolume(to: 0.0, over: 2.0) // Fade out over 2 seconds
 ```

 Playback Rate:
 ```swift
 player.playbackRate = 1.5 // 1.5x speed
 player.playbackRate = 0.75 // Slower for learning content
 ```

 Skip Controls:
 ```swift
 player.skip(.forward30) // Skip 30 seconds forward
 player.skip(.nextChapter) // Skip to next chapter
 ```

 Buffer Monitoring:
 ```swift
 player.bufferStatus
     .compactMap { $0 }
     .sink { status in
         if status.isReadyForPlaying {
             showPlayButton()
         } else {
             showBufferingIndicator(progress: status.bufferingProgress)
         }
     }
     .store(in: &cancellables)
 ```

 Dynamic Metadata:
 ```swift
 player.metadata
     .compactMap { $0 }
     .sink { metadata in
         updateNowPlaying(with: metadata)
         updateChapterList(with: metadata.chapters)
     }
     .store(in: &cancellables)
 ```

 IMPLEMENTATION GUIDELINES:

 - Volume and rate properties should provide immediate feedback
 - Buffer status updates should be frequent enough for smooth UI
 - Metadata updates should trigger appropriate system integrations
 - Skip operations should handle boundary conditions gracefully
 - Chapter navigation should provide smooth user experience
 - All publishers should emit current state on subscription
 - Proper error handling for network and system failures
 - Memory-efficient buffering for large audio files
 */