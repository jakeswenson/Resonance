// AudioPlayable.swift - Foundational protocol for basic audio playback functionality
// Swift 6 Sendable compliant protocol designed for progressive adoption and 3-line basic usage

import Foundation
import Combine

/// The foundational protocol for basic audio playback functionality.
///
/// AudioPlayable is the simplest layer of the Resonance audio system, designed for 3-line basic usage:
/// ```swift
/// let player = SomeAudioPlayable()
/// player.loadAudio(from: url, metadata: nil)
/// player.play()
/// ```
///
/// This protocol provides:
/// - Basic playback controls (play, pause, seek)
/// - Reactive state observation using Combine publishers
/// - Simple URL-based audio loading
/// - Swift 6 Sendable compliance for concurrent usage
/// - Clean error handling with typed AudioError
///
/// The protocol is designed for progressive adoption - implementations can start simple
/// and add more sophisticated features through additional protocols.
@MainActor
public protocol AudioPlayable: Sendable {

    // MARK: - Reactive State Publishers

    /// Publisher that emits playback state changes
    ///
    /// Emits the current playback state and all subsequent changes.
    /// Initial state should be `.idle` for new instances.
    ///
    /// - Returns: Publisher that never fails and emits PlaybackState values
    var playbackState: AnyPublisher<PlaybackState, Never> { get }

    /// Publisher that emits current playback time updates
    ///
    /// Emits the current position in seconds and updates during playback.
    /// Should emit 0.0 for initial state and when no audio is loaded.
    /// Updates should be frequent enough for smooth UI updates (recommended: ~0.1s intervals).
    ///
    /// - Returns: Publisher that never fails and emits TimeInterval values
    var currentTime: AnyPublisher<TimeInterval, Never> { get }

    /// Publisher that emits total duration updates
    ///
    /// Emits the total duration in seconds when available.
    /// Should emit 0.0 for initial state and update when audio metadata becomes available.
    /// For streaming content, may update as more duration information becomes available.
    ///
    /// - Returns: Publisher that never fails and emits TimeInterval values
    var duration: AnyPublisher<TimeInterval, Never> { get }

    // MARK: - Audio Loading

    /// Loads audio from a URL with optional metadata
    ///
    /// Prepares audio content for playback. This method should:
    /// - Validate the URL
    /// - Begin loading/streaming the audio content
    /// - Update playbackState to reflect loading progress
    /// - Emit duration when available
    /// - Complete when ready for playback or fail with appropriate error
    ///
    /// The metadata parameter is optional and used for display purposes.
    /// Implementations may extract metadata from the audio file if none provided.
    ///
    /// - Parameters:
    ///   - url: URL of the audio content (local file or remote stream)
    ///   - metadata: Optional metadata for display and organization
    /// - Returns: Publisher that completes when loading finishes or fails with AudioError
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError>

    // MARK: - Playback Controls

    /// Starts or resumes audio playback
    ///
    /// Begins playback of the currently loaded audio content.
    /// Should update playbackState to `.playing` on success.
    /// If no audio is loaded, should fail with appropriate error.
    ///
    /// - Returns: Publisher that completes when play operation finishes or fails with AudioError
    func play() -> AnyPublisher<Void, AudioError>

    /// Pauses audio playback
    ///
    /// Pauses the currently playing audio, maintaining current position.
    /// Should update playbackState to `.paused` on success.
    /// If not currently playing, should complete without error.
    ///
    /// - Returns: Publisher that completes when pause operation finishes or fails with AudioError
    func pause() -> AnyPublisher<Void, AudioError>

    /// Seeks to a specific position in the audio
    ///
    /// Changes the current playback position to the specified time.
    /// Should validate that the position is within valid bounds.
    /// Should update currentTime publisher with the new position.
    /// May temporarily update playbackState to `.buffering` during seek.
    ///
    /// - Parameter position: Target position in seconds
    /// - Returns: Publisher that completes when seek operation finishes or fails with AudioError
    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError>
}

// MARK: - Protocol Extensions

extension AudioPlayable {

    /// Convenience method for loading and immediately playing audio
    ///
    /// Combines loadAudio and play operations for simple usage.
    /// Equivalent to calling loadAudio followed by play.
    ///
    /// - Parameters:
    ///   - url: URL of the audio content
    ///   - metadata: Optional metadata for display
    /// - Returns: Publisher that completes when both operations finish or fails with AudioError
    func loadAndPlay(from url: URL, metadata: AudioMetadata? = nil) -> AnyPublisher<Void, AudioError> {
        loadAudio(from: url, metadata: metadata)
            .flatMap { _ -> AnyPublisher<Void, AudioError> in
                return self.play()
            }
            .eraseToAnyPublisher()
    }

    /// Convenience method for toggling play/pause state
    ///
    /// Automatically plays if paused/ready or pauses if playing.
    /// Based on current playbackState, chooses appropriate action.
    ///
    /// - Returns: Publisher that completes when toggle operation finishes or fails with AudioError
    func togglePlayPause() -> AnyPublisher<Void, AudioError> {
        playbackState
            .first()
            .flatMap { state -> AnyPublisher<Void, AudioError> in
                switch state {
                case .playing:
                    return self.pause()
                case .paused, .ready:
                    return self.play()
                default:
                    return Fail(error: AudioError.invalidOperation)
                        .eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }

    /// Convenience method for seeking by relative offset
    ///
    /// Seeks forward or backward by the specified number of seconds
    /// from the current position. Automatically clamps to valid bounds.
    ///
    /// - Parameter offset: Number of seconds to seek (positive = forward, negative = backward)
    /// - Returns: Publisher that completes when seek operation finishes or fails with AudioError
    func seekBy(offset: TimeInterval) -> AnyPublisher<Void, AudioError> {
        currentTime.first().combineLatest(duration.first())
            .flatMap { currentTime, duration -> AnyPublisher<Void, AudioError> in
                let newPosition = max(0, min(duration, currentTime + offset))
                return self.seek(to: newPosition)
            }
            .eraseToAnyPublisher()
    }

    /// Convenience method for seeking to beginning
    ///
    /// Resets playback to the start of the audio content.
    ///
    /// - Returns: Publisher that completes when seek operation finishes or fails with AudioError
    func seekToBeginning() -> AnyPublisher<Void, AudioError> {
        seek(to: 0)
    }

    /// Convenience method for seeking to end
    ///
    /// Seeks to the end of the audio content, effectively completing playback.
    ///
    /// - Returns: Publisher that completes when seek operation finishes or fails with AudioError
    func seekToEnd() -> AnyPublisher<Void, AudioError> {
        duration
            .first()
            .flatMap { duration -> AnyPublisher<Void, AudioError> in
                return self.seek(to: duration)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Additional AudioError Cases

extension AudioError {
    /// Operation is not valid in current state
    static let invalidOperation = AudioError.internalError("Invalid operation for current state")
}

// MARK: - Documentation Notes

/*
 DESIGN PRINCIPLES:

 1. PROGRESSIVE ADOPTION
    - Start with basic 3-line usage: load, play, done
    - Can be extended with additional protocols for advanced features
    - No complex setup or configuration required for basic use

 2. REACTIVE BY DEFAULT
    - All state changes exposed through Combine publishers
    - No callback-based APIs or delegates at this level
    - Publishers never fail - errors come through completion events

 3. SWIFT 6 SENDABLE COMPLIANCE
    - All types are Sendable for concurrent usage
    - MainActor isolation ensures thread safety
    - Weak self captures prevent retain cycles

 4. SIMPLE ERROR HANDLING
    - Single AudioError type covers all failure modes
    - Clear error categories and recovery guidance
    - Operations fail fast with meaningful errors

 5. URL-CENTRIC
    - Works with both local files and remote streams
    - No distinction needed at protocol level
    - Implementation handles URL type differences

 USAGE PATTERNS:

 Basic Usage (3 lines):
 ```swift
 let player = SomeAudioPlayable()
 player.loadAudio(from: url, metadata: nil)
 player.play()
 ```

 Reactive UI Updates:
 ```swift
 player.playbackState
     .sink { state in
         updatePlayButton(for: state)
     }
     .store(in: &cancellables)

 player.currentTime
     .sink { time in
         updateProgressBar(time: time)
     }
     .store(in: &cancellables)
 ```

 Error Handling:
 ```swift
 player.loadAudio(from: url, metadata: metadata)
     .sink(
         receiveCompletion: { completion in
             if case .failure(let error) = completion {
                 showError(error)
             }
         },
         receiveValue: { _ in }
     )
     .store(in: &cancellables)
 ```

 IMPLEMENTATION GUIDELINES:

 - Publishers should be backed by CurrentValueSubject for state
 - Use proper MainActor isolation for UI thread safety
 - Implement proper cleanup in deinit
 - Consider buffering states for streaming content
 - Validate seek positions against duration
 - Handle network errors gracefully for remote content
 - Emit state changes immediately when operations complete
 - Avoid retain cycles through careful closure capture semantics
 */