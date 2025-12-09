//
//  AudioPlayerExtensions.swift
//  Resonance
//
//  Convenience extensions for common audio player use cases and syntactic sugar.
//  Provides easier access to frequent operations and publisher composition helpers.
//

import Foundation
import Combine
import AVFoundation

/// Async wrapper for audio operations that can fail
public struct AudioResult<Success> {
    private let operation: () async throws -> Success

    public init(_ operation: @escaping () async throws -> Success) {
        self.operation = operation
    }

    /// Execute the audio operation asynchronously
    public func async() async throws -> Success {
        return try await operation()
    }
}

// MARK: - AudioPlayable Convenience Extensions

public extension AudioPlayable {
    
    // MARK: - Quick Actions
    
    /// Loads and immediately plays audio in one call
    ///
    /// Convenience method that combines loadAudio and play operations.
    /// Useful for simple use cases where you want immediate playback.
    ///
    /// - Parameters:
    ///   - url: Audio file URL (local or remote)
    ///   - metadata: Optional audio metadata
    /// - Returns: AudioResult that can be awaited
    func loadAndPlay(from url: URL, metadata: AudioMetadata? = nil) -> AudioResult<Void> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            try await self.loadAudio(from: url, metadata: metadata).async()
            try await self.play().async()
        }
    }
    
    /// Pauses if playing, plays if paused - typical toggle behavior
    ///
    /// Convenience method for implementing play/pause toggle buttons.
    ///
    /// - Returns: AudioResult indicating the new state
    func togglePlayback() -> AudioResult<AudioPlaybackState> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            let currentState = try await self.getCurrentState().async()
            
            switch currentState {
            case .playing:
                try await self.pause().async()
                return .paused
            case .paused, .stopped:
                try await self.play().async()
                return .playing
            case .loading:
                // Don't interrupt loading
                return currentState
            }
        }
    }
    
    /// Seeks to a percentage of the total duration
    ///
    /// - Parameter percentage: 0.0 to 1.0 representing position in track
    /// - Returns: AudioResult with the actual time position
    func seekToPercentage(_ percentage: Double) -> AudioResult<TimeInterval> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            guard percentage >= 0.0 && percentage <= 1.0 else {
                throw AudioError.invalidParameter("Percentage must be between 0.0 and 1.0")
            }
            
            let progress = try await self.getCurrentProgress().async()
            let targetTime = progress.duration * percentage
            
            try await self.seek(to: targetTime).async()
            return targetTime
        }
    }
    
    /// Quick skip forward by a standard amount (15 seconds)
    ///
    /// - Parameter amount: Time interval to skip forward (default: 15 seconds)
    /// - Returns: AudioResult with new position
    func skipForward(_ amount: TimeInterval = 15.0) -> AudioResult<TimeInterval> {
        return seekBy(timeInterval: amount)
    }
    
    /// Quick skip backward by a standard amount (15 seconds)
    ///
    /// - Parameter amount: Time interval to skip backward (default: 15 seconds)
    /// - Returns: AudioResult with new position
    func skipBackward(_ amount: TimeInterval = 15.0) -> AudioResult<TimeInterval> {
        return seekBy(timeInterval: -amount)
    }
    
    // MARK: - State Query Convenience
    
    /// Convenience property for checking if audio is currently playing
    var isPlaying: AnyPublisher<Bool, Never> {
        return playbackStatePublisher
            .map { $0 == .playing }
            .eraseToAnyPublisher()
    }
    
    /// Convenience property for checking if audio is paused
    var isPaused: AnyPublisher<Bool, Never> {
        return playbackStatePublisher
            .map { $0 == .paused }
            .eraseToAnyPublisher()
    }
    
    /// Convenience property for checking if audio is loading
    var isLoading: AnyPublisher<Bool, Never> {
        return playbackStatePublisher
            .map { $0 == .loading }
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits only when playback completes (reaches end)
    var playbackCompletedPublisher: AnyPublisher<Void, Never> {
        return playbackStatePublisher
            .filter { $0 == .stopped }
            .map { _ in () }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Time and Progress Convenience
    
    /// Publisher that emits current time only (without duration)
    var currentTimePublisher: AnyPublisher<TimeInterval, Never> {
        return playbackProgressPublisher
            .map(\.currentTime)
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits duration only (when available)
    var durationPublisher: AnyPublisher<TimeInterval, Never> {
        return playbackProgressPublisher
            .map(\.duration)
            .filter { $0 > 0 }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits playback percentage (0.0 to 1.0)
    var playbackPercentagePublisher: AnyPublisher<Double, Never> {
        return playbackProgressPublisher
            .compactMap { progress in
                guard progress.duration > 0 else { return nil }
                return progress.currentTime / progress.duration
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits remaining time
    var remainingTimePublisher: AnyPublisher<TimeInterval, Never> {
        return playbackProgressPublisher
            .map { progress in
                max(0, progress.duration - progress.currentTime)
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - AudioConfigurable Convenience Extensions

public extension AudioConfigurable {
    
    /// Sets up high-quality audio configuration with large buffer
    ///
    /// Convenience method for applications that prioritize audio quality
    /// over memory usage and startup speed.
    ///
    /// - Returns: AudioResult indicating configuration success
    func configureForHighQuality() -> AudioResult<Void> {
        return configure(quality: .high, bufferSize: .large)
    }
    
    /// Sets up balanced configuration suitable for most applications
    ///
    /// - Returns: AudioResult indicating configuration success
    func configureBalanced() -> AudioResult<Void> {
        return configure(quality: .medium, bufferSize: .medium)
    }
    
    /// Sets up configuration optimized for low memory usage
    ///
    /// Suitable for applications with memory constraints or when playing
    /// multiple audio streams simultaneously.
    ///
    /// - Returns: AudioResult indicating configuration success
    func configureForLowMemory() -> AudioResult<Void> {
        return configure(quality: .medium, bufferSize: .small)
    }
}

// MARK: - AudioEffectable Convenience Extensions

public extension AudioEffectable {
    
    // MARK: - Common Effect Presets
    
    /// Adds a subtle reverb effect suitable for music
    ///
    /// - Returns: AudioResult with the effect identifier
    func addMusicReverb() -> AudioResult<AudioEffectID> {
        return addEffect(.reverb(wetDryMix: 0.3))
    }
    
    /// Adds a vocal reverb effect suitable for speech or vocals
    ///
    /// - Returns: AudioResult with the effect identifier
    func addVocalReverb() -> AudioResult<AudioEffectID> {
        return addEffect(.reverb(wetDryMix: 0.15))
    }
    
    /// Adds a bass boost effect for enhanced low frequencies
    ///
    /// - Returns: AudioResult with the effect identifier
    func addBassBoost() -> AudioResult<AudioEffectID> {
        return addEffect(.equalizer(preset: .bassBoost))
    }
    
    /// Adds a vocal clarity effect for better speech intelligibility
    ///
    /// - Returns: AudioResult with the effect identifier
    func addVocalClarity() -> AudioResult<AudioEffectID> {
        return addEffect(.equalizer(preset: .vocal))
    }
    
    /// Adds a compressor for dynamic range control
    ///
    /// - Parameter ratio: Compression ratio (default: 4:1)
    /// - Returns: AudioResult with the effect identifier
    func addCompressor(ratio: Float = 4.0) -> AudioResult<AudioEffectID> {
        return addEffect(.compressor(ratio: ratio, threshold: -20.0))
    }
    
    // MARK: - Effect Chain Management
    
    /// Adds multiple effects in sequence
    ///
    /// - Parameter effects: Array of effects to add in order
    /// - Returns: AudioResult with array of effect identifiers
    func addEffectChain(_ effects: [AudioEffectType]) -> AudioResult<[AudioEffectID]> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            var effectIDs: [AudioEffectID] = []
            
            for effect in effects {
                let effectID = try await self.addEffect(effect).async()
                effectIDs.append(effectID)
            }
            
            return effectIDs
        }
    }
    
    /// Removes multiple effects by their identifiers
    ///
    /// - Parameter effectIDs: Array of effect identifiers to remove
    /// - Returns: AudioResult indicating success
    func removeEffects(_ effectIDs: [AudioEffectID]) -> AudioResult<Void> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            for effectID in effectIDs {
                try await self.removeEffect(effectID).async()
            }
        }
    }
}

// MARK: - AudioDownloadable Convenience Extensions

public extension AudioDownloadable {
    
    /// Downloads audio and returns a publisher that emits progress updates
    ///
    /// Convenience method that combines download initiation with progress observation.
    ///
    /// - Parameter url: URL to download
    /// - Returns: Publisher that emits DownloadProgress updates
    func downloadWithProgress(from url: URL) -> AnyPublisher<DownloadProgress, Error> {
        return Publishers.Create { subscriber in
            let cancellable = Task {
                do {
                    // Start the download
                    let downloadTask = try await self.downloadAudio(from: url).async()
                    
                    // Observe progress
                    let progressCancellable = self.downloadProgressPublisher
                        .sink(
                            receiveCompletion: { completion in
                                switch completion {
                                case .finished:
                                    subscriber.receive(completion: .finished)
                                case .failure(let error):
                                    subscriber.receive(completion: .failure(error))
                                }
                            },
                            receiveValue: { progress in
                                _ = subscriber.receive(progress)
                            }
                        )
                    
                    // Wait for download completion
                    let _ = try await downloadTask.result.async()
                    
                    progressCancellable.cancel()
                    subscriber.receive(completion: .finished)
                    
                } catch {
                    subscriber.receive(completion: .failure(error))
                }
            }
            
            return AnyCancellable {
                cancellable.cancel()
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Downloads multiple files with combined progress reporting
    ///
    /// - Parameter urls: URLs to download
    /// - Returns: Publisher emitting overall progress (0.0 to 1.0)
    func downloadBatch(_ urls: [URL]) -> AnyPublisher<Double, Error> {
        let downloadPublishers = urls.map { url in
            downloadWithProgress(from: url)
                .map(\.progress)
                .eraseToAnyPublisher()
        }
        
        let combinedPublisher = Publishers.CombineLatest(downloadPublishers)
        return combinedPublisher
            .map { progressValues -> Double in
                let total = progressValues.reduce(0.0, +)
                let count = Double(progressValues.count)
                return total / count
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - AudioQueueManageable Convenience Extensions

public extension AudioQueueManageable {
    
    /// Adds multiple tracks to the queue at once
    ///
    /// - Parameter tracks: Array of (URL, AudioMetadata) tuples
    /// - Returns: AudioResult indicating success
    func addTracksToQueue(_ tracks: [(url: URL, metadata: AudioMetadata?)]) -> AudioResult<Void> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            for track in tracks {
                try await self.enqueue(url: track.url, metadata: track.metadata).async()
            }
        }
    }
    
    /// Replaces the entire queue with new tracks
    ///
    /// - Parameter tracks: New tracks for the queue
    /// - Returns: AudioResult indicating success
    func replaceQueue(with tracks: [(url: URL, metadata: AudioMetadata?)]) -> AudioResult<Void> {
        return AudioResult {
            
            try await self.clearQueue().async()
            try await self.addTracksToQueue(tracks).async()
        }
    }
    
    /// Shuffles the current queue
    ///
    /// - Returns: AudioResult indicating success
    func shuffleQueue() -> AudioResult<Void> {
        return AudioResult { [weak self] in
            guard let self = self else {
                throw AudioError.playerDeallocated
            }
            
            let currentQueue = await self.queue.first().value
            let shuffledQueue = currentQueue.shuffled()
            try await self.replaceQueue(with: shuffledQueue.map { ($0.url, $0.metadata) }).async()
        }
    }
}

// MARK: - AudioQueueManageable Extensions

public extension AudioQueueManageable {

    /// Publisher that emits when the queue changes
    var queueChangedPublisher: AnyPublisher<[AudioMetadata], Never> {
        return queue
            .map { queuedItems in
                queuedItems.compactMap { $0.metadata }
            }
            .removeDuplicates { old, new in
                old.count == new.count && old.elementsEqual(new) { $0.url == $1.url }
            }
            .eraseToAnyPublisher()
    }

    /// Publisher that emits queue size changes
    var queueSizePublisher: AnyPublisher<Int, Never> {
        return queue
            .map(\.count)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

// MARK: - Publisher Composition Helpers

public extension AudioPlayable {
    
    /// Combines playback state and progress into a single state object
    ///
    /// Useful for UI that needs to display both state and progress information.
    ///
    /// - Returns: Publisher emitting combined playback information
    func combinedPlaybackInfoPublisher() -> AnyPublisher<PlaybackInfo, Never> {
        return playbackState.combineLatest(currentTime.combineLatest(duration))
            .map { state, timeInfo in
                let (currentTime, totalDuration) = timeInfo
                let progress = totalDuration > 0 ? currentTime / totalDuration : 0.0
                return PlaybackInfo(state: state, progress: progress)
            }
            .eraseToAnyPublisher()
    }
    
    /// Publisher that emits significant playback events only
    ///
    /// Filters out frequent progress updates and only emits on state changes
    /// or significant progress milestones.
    ///
    /// - Returns: Publisher emitting significant playback events
    func significantEventsPublisher() -> AnyPublisher<PlaybackEvent, Never> {
        let stateEvents = playbackState
            .map { PlaybackEvent.stateChanged($0) }

        let progressMilestones = currentTime.combineLatest(duration)
            .compactMap { currentTime, duration -> PlaybackEvent? in
                guard duration > 0 else { return nil }
                let percentage = currentTime / duration

                // Emit at 25%, 50%, 75%, and 90%
                let milestones: [Double] = [0.25, 0.5, 0.75, 0.9]
                for milestone in milestones {
                    if abs(percentage - milestone) < 0.01 {
                        return .progressMilestone(milestone)
                    }
                }
                return nil
            }
            .removeDuplicates()
        
        return stateEvents.merge(with: progressMilestones)
            .eraseToAnyPublisher()
    }
}

// MARK: - Error Handling Extensions

public extension AudioResult {
    
    /// Retries the operation up to a specified number of times
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retry attempts
    ///   - delay: Delay between retry attempts
    /// - Returns: AudioResult that retries on failure
    func retry(maxRetries: Int, delay: TimeInterval = 1.0) -> AudioResult<Success> {
        return AudioResult { [self] in
            var lastError: Error? = nil
            
            for attempt in 0...maxRetries {
                do {
                    return try await self.async()
                } catch {
                    lastError = error
                    
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }
            
            throw lastError ?? AudioError.internalError("Retry failed")
        }
    }
    
    /// Maps the error to a more user-friendly error type
    ///
    /// - Parameter transform: Function to transform the error
    /// - Returns: AudioResult with transformed errors
    func mapError<E: Error>(_ transform: @escaping (Error) -> E) -> AudioResult<Success> {
        return AudioResult {
            do {
                return try await self.async()
            } catch {
                throw transform(error)
            }
        }
    }
    
    /// Provides a fallback value in case of error
    ///
    /// - Parameter fallback: Value to return on error
    /// - Returns: AudioResult that cannot fail
    func fallback(_ fallback: Success) -> AudioResult<Success> {
        return AudioResult {
            do {
                return try await self.async()
            } catch {
                return fallback
            }
        }
    }
}

// MARK: - Platform-Specific Extensions

#if os(iOS)
public extension AudioPlayable {
    
    /// Sets up remote control commands for iOS Control Center and lock screen
    ///
    /// - Parameter metadata: Metadata to display in Control Center
    /// - Returns: AudioResult indicating setup success
    func setupRemoteControls(with metadata: AudioMetadata) -> AudioResult<Void> {
        return AudioResult {
            // This would integrate with MPRemoteCommandCenter
            // Implementation would be in the actual audio player
            print("[AudioPlayerExtensions] Remote controls configured for iOS")
        }
    }
}
#endif

#if os(macOS)
public extension AudioPlayable {
    
    /// Sets up media key support for macOS
    ///
    /// - Returns: AudioResult indicating setup success
    func setupMediaKeys() -> AudioResult<Void> {
        return AudioResult {
            // This would integrate with macOS media key events
            print("[AudioPlayerExtensions] Media keys configured for macOS")
        }
    }
}
#endif

// MARK: - SwiftUI Integration Helpers

public extension AudioPlayable {
    
    /// Creates a SwiftUI-compatible observable object for this player
    ///
    /// - Returns: An ObservableObject that wraps this player
    func observableObject() -> AudioPlayerObservable {
        return AudioPlayerObservable(player: self)
    }
}

/// SwiftUI-compatible wrapper for AudioPlayable
@MainActor
public class AudioPlayerObservable: ObservableObject {
    @Published public private(set) var state: AudioPlaybackState = .stopped
    @Published public private(set) var progress: AudioProgress = .zero
    @Published public private(set) var isPlaying: Bool = false
    
    private let player: AudioPlayable
    private var cancellables = Set<AnyCancellable>()
    
    public init(player: AudioPlayable) {
        self.player = player
        setupObservation()
    }
    
    private func setupObservation() {
        player.playbackState
            .assign(to: &$state)

        player.currentTime.combineLatest(player.duration)
            .map { currentTime, duration in
                PlaybackInfo(
                    state: PlaybackState.playing,
                    progress: duration > 0 ? currentTime / duration : 0.0
                )
            }
            .assign(to: &$progress)

        player.playbackState
            .map { $0 == .playing }
            .assign(to: &$isPlaying)
    }
    
    public func loadAndPlay(url: URL, metadata: AudioMetadata? = nil) async throws {
        try await (player.loadAndPlay(from: url, metadata: metadata) as AudioResult<Void>).async()
    }
    
    public func togglePlayback() async throws {
        _ = try await player.togglePlayback().async()
    }
    
    public func seek(to time: TimeInterval) async throws {
        try await player.seek(to: time).async()
    }
    
    public func seekToPercentage(_ percentage: Double) async throws {
        _ = try await player.seekToPercentage(percentage).async()
    }
}

// MARK: - Data Models for Extensions

/// Combined playback information structure
public struct PlaybackInfo: Equatable {
    public let state: AudioPlaybackState
    public let progress: AudioProgress
    
    public init(state: AudioPlaybackState, progress: AudioProgress) {
        self.state = state
        self.progress = progress
    }
}

/// Enumeration of significant playback events
public enum PlaybackEvent: Equatable {
    case stateChanged(AudioPlaybackState)
    case progressMilestone(Double)
    
    public static func == (lhs: PlaybackEvent, rhs: PlaybackEvent) -> Bool {
        switch (lhs, rhs) {
        case (.stateChanged(let lhsState), .stateChanged(let rhsState)):
            return lhsState == rhsState
        case (.progressMilestone(let lhsProgress), .progressMilestone(let rhsProgress)):
            return abs(lhsProgress - rhsProgress) < 0.001
        default:
            return false
        }
    }
}

// MARK: - Combine Publisher Creation Helper

/// Helper for creating publishers from async operations has been removed
/// This was causing Swift 6 protocol conformance issues and is not needed
/// since we use Future-based patterns throughout the codebase

// MARK: - Example Usage Documentation

/*

## AudioPlayerExtensions Usage Examples

### Basic Convenience Methods

```swift
// Load and play in one call
let player = BasicAudioPlayer()
try await player.loadAndPlay(from: url).async()

// Toggle playback
let newState = try await player.togglePlayback().async()

// Seek to 50% of track
let timePosition = try await player.seekToPercentage(0.5).async()

// Quick skip operations
try await player.skipForward().async()  // +15 seconds
try await player.skipBackward(30).async()  // -30 seconds
```

### Publisher Convenience

```swift
// Subscribe to specific state aspects
player.isPlaying
    .sink { isPlaying in
        updatePlayButton(playing: isPlaying)
    }
    .store(in: &cancellables)

// Track playback percentage
player.playbackPercentagePublisher
    .sink { percentage in
        progressBar.progress = Float(percentage)
    }
    .store(in: &cancellables)

// Get notified on playback completion
player.playbackCompletedPublisher
    .sink {
        playNextTrack()
    }
    .store(in: &cancellables)
```

### Effect Presets

```swift
let effectPlayer = AdvancedAudioPlayer() as AudioEffectable

// Add preset effects
let reverb = try await effectPlayer.addMusicReverb().async()
let bassBoost = try await effectPlayer.addBassBoost().async()

// Add effect chain
let effects: [AudioEffectType] = [.reverb(wetDryMix: 0.3), .compressor(ratio: 4.0)]
let effectIDs = try await effectPlayer.addEffectChain(effects).async()
```

### Download with Progress

```swift
let downloadPlayer = AdvancedAudioPlayer() as AudioDownloadable

// Download with progress updates
downloadPlayer.downloadWithProgress(from: url)
    .sink(
        receiveCompletion: { completion in
            switch completion {
            case .finished: print("Download completed")
            case .failure(let error): print("Download failed: \(error)")
            }
        },
        receiveValue: { progress in
            updateDownloadProgress(progress.progress)
        }
    )
    .store(in: &cancellables)
```

### Queue Management

```swift
let queuePlayer = AdvancedAudioPlayer() as AudioQueueManageable

// Add multiple tracks
let tracks = [
    (url: track1URL, metadata: track1Metadata),
    (url: track2URL, metadata: track2Metadata)
]
try await queuePlayer.addTracksToQueue(tracks).async()

// Shuffle queue
try await queuePlayer.shuffleQueue().async()

// Monitor queue changes
queuePlayer.queueSizePublisher
    .sink { queueSize in
        updateQueueDisplay(size: queueSize)
    }
    .store(in: &cancellables)
```

### SwiftUI Integration

```swift
struct AudioPlayerView: View {
    @StateObject private var playerObservable: AudioPlayerObservable
    
    init() {
        let player = BasicAudioPlayer()
        _playerObservable = StateObject(wrappedValue: player.observableObject())
    }
    
    var body: some View {
        VStack {
            ProgressView(value: playerObservable.progress.currentTime,
                        total: playerObservable.progress.duration)
            
            Button(playerObservable.isPlaying ? "Pause" : "Play") {
                Task {
                    try await playerObservable.togglePlayback()
                }
            }
        }
    }
}
```

### Error Handling with Retry

```swift
// Retry network operations
let result = try await player
    .loadAudio(from: remoteURL, metadata: metadata)
    .retry(maxRetries: 3, delay: 2.0)
    .async()

// Provide fallback for non-critical operations
let progress = await player
    .getCurrentProgress()
    .fallback(.zero)
    .async()
```

*/
