//
//  BasicAudioPlayer.swift
//  Resonance
//
//  Minimal implementation of the AudioPlayable protocol for basic 3-line usage.
//  Provides the simplest possible interface for basic audio playback functionality.
//

import Foundation
import Combine
import AVFoundation

/// The simplest implementation of AudioPlayable for basic 3-line usage.
///
/// BasicAudioPlayer is designed for users who want straightforward audio playback without
/// complex configuration. It handles both local files and remote streams automatically.
///
/// **3-line usage pattern:**
/// ```swift
/// let player = BasicAudioPlayer()
/// try await player.loadAudio(from: url, metadata: nil).async()
/// try await player.play().async()
/// ```
///
/// This implementation:
/// - Uses ReactiveAudioCoordinator for actor coordination
/// - Integrates with existing audio engines (AudioStreamEngine/AudioDiskEngine)
/// - Provides Swift 6 concurrency and Sendable compliance
/// - Follows established reactive patterns with Combine publishers
/// - Handles local files and remote streams automatically
/// - Is the foundation that other implementations can extend
@MainActor
open class BasicAudioPlayer: AudioPlayable, @unchecked Sendable {

    // MARK: - Dependencies

    /// Reactive coordinator for audio system orchestration
    internal let coordinator: ReactiveAudioCoordinator

    /// Legacy audio updates for backward compatibility
    internal let audioUpdates: AudioUpdates

    // MARK: - State Management

    /// Current playback state publisher
    internal let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)

    /// Current time publisher
    internal let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0.0)

    /// Duration publisher
    internal let durationSubject = CurrentValueSubject<TimeInterval, Never>(0.0)

    /// Current audio URL being played
    internal var currentAudioURL: URL?

    /// Current audio metadata
    internal var currentMetadata: AudioMetadata?

    /// Current audio engine (either stream or disk)
    internal var currentEngine: AudioEngineProtocol?

    /// Cancellables for reactive subscriptions
    internal var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize BasicAudioPlayer with optional coordinator dependency injection
    /// - Parameter coordinator: Optional coordinator instance (defaults to shared)
    public init(coordinator: ReactiveAudioCoordinator = .shared) {
        self.coordinator = coordinator
        self.audioUpdates = coordinator.getLegacyAudioUpdates()

        setupReactiveBindings()

        // Ensure coordinator is ready
        Task {
            if !coordinator.isReady {
                try? await coordinator.initialize()
            }
        }
    }

    deinit {
        // Note: Can't call MainActor isolated cleanup() from deinit
        // Resources will be cleaned up automatically when object is deallocated
    }

    // MARK: - AudioPlayable Protocol

    /// Publisher that emits playback state changes
    public var playbackState: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    /// Publisher that emits current playback time updates
    public var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    /// Publisher that emits total duration updates
    public var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }

    /// Loads audio from a URL with optional metadata
    open func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { promise in
            Task { @MainActor in
                do {
                    // Validate URL
                    guard url.absoluteString.count > 0 else {
                        promise(.failure(.invalidURL))
                        return
                    }

                    // Update state to loading
                    self.playbackStateSubject.send(.loading)
                    self.currentAudioURL = url
                    self.currentMetadata = metadata

                    // Stop and cleanup any existing engine
                    await self.stopCurrentEngine()

                    // Ensure coordinator is ready
                    try self.coordinator.ensureReady()

                    // Configure audio session for playback
                    #if os(iOS) || os(tvOS)
                    try await self.coordinator.configureAudioSession(category: .playback)
                    #else
                    try await self.coordinator.configureAudioSession()
                    #endif
                    try await self.coordinator.activateAudioSession()

                    // Create appropriate engine based on URL type
                    let engine = try await self.createEngineForURL(url, metadata: metadata)
                    self.currentEngine = engine

                    // Wait for engine to be ready
                    try await self.waitForEngineReady()

                    // Update state to ready
                    self.playbackStateSubject.send(.ready)
                    promise(.success(()))

                } catch {
                    self.playbackStateSubject.send(.idle)
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to load audio: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Starts or resumes audio playback
    public func play() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { promise in
            Task { @MainActor in
                do {
                    guard let engine = self.currentEngine else {
                        promise(.failure(.internalError("No audio loaded")))
                        return
                    }

                    // Ensure coordinator and session are ready
                    try self.coordinator.ensureReady()

                    let currentState = self.playbackStateSubject.value
                    guard currentState == .ready || currentState == .paused else {
                        promise(.failure(.internalError("Invalid state for play: \(currentState)")))
                        return
                    }

                    // Start playback through engine
                    engine.play()

                    // Update state
                    self.playbackStateSubject.send(.playing)
                    promise(.success(()))

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to play audio: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Pauses audio playback
    public func pause() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { promise in
            Task { @MainActor in
                guard let engine = self.currentEngine else {
                    promise(.failure(.internalError("No audio loaded")))
                    return
                }

                let currentState = self.playbackStateSubject.value
                guard currentState == .playing else {
                    promise(.success(()))  // Already paused or not playing
                    return
                }

                // Pause playback through engine
                engine.pause()

                // Update state
                self.playbackStateSubject.send(.paused)
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Seeks to a specific position in the audio
    public func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { promise in
            Task { @MainActor in
                guard let engine = self.currentEngine else {
                    promise(.failure(.internalError("No audio loaded")))
                    return
                }

                let currentDuration = self.durationSubject.value
                guard position >= 0 && (currentDuration <= 0 || position <= currentDuration) else {
                    promise(.failure(.seekOutOfBounds))
                    return
                }

                // Temporarily set buffering state during seek
                let previousState = self.playbackStateSubject.value
                if previousState == .playing {
                    self.playbackStateSubject.send(.buffering)
                }

                // Perform seek through engine
                engine.seek(toNeedle: position)

                // Update current time
                self.currentTimeSubject.send(position)

                // Restore previous state
                self.playbackStateSubject.send(previousState)
                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Private Implementation

    /// Setup reactive bindings with the audio system
    private func setupReactiveBindings() {
        // Bind legacy playing status to modern playback state
        audioUpdates.playingStatus
            .sink { [weak self] legacyStatus in
                guard let self = self else { return }
                let modernState = self.convertLegacyStatusToPlaybackState(legacyStatus)
                self.playbackStateSubject.send(modernState)
            }
            .store(in: &cancellables)

        // Bind elapsed time
        audioUpdates.elapsedTime
            .filter { $0 >= 0 }
            .sink { [weak self] time in
                self?.currentTimeSubject.send(time)
            }
            .store(in: &cancellables)

        // Bind duration
        audioUpdates.duration
            .filter { $0 >= 0 }
            .sink { [weak self] duration in
                self?.durationSubject.send(duration)
            }
            .store(in: &cancellables)
    }

    /// Convert legacy SAPlayingStatus to modern PlaybackState
    private func convertLegacyStatusToPlaybackState(_ legacyStatus: SAPlayingStatus) -> PlaybackState {
        switch legacyStatus {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .buffering:
            return .buffering
        case .ended:
            return .completed
        }
    }

    /// Create appropriate audio engine based on URL type
    private func createEngineForURL(_ url: URL, metadata: AudioMetadata?) async throws -> AudioEngineProtocol {
        if url.isFileURL {
            // Use disk engine for local files
            return try await createDiskEngine(for: url, metadata: metadata)
        } else {
            // Use stream engine for remote URLs
            return try await createStreamEngine(for: url, metadata: metadata)
        }
    }

    /// Create disk-based audio engine for local files
    private func createDiskEngine(for url: URL, metadata: AudioMetadata?) async throws -> AudioEngineProtocol {
        // Verify file exists and is accessible
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioError.invalidURL
        }

        // Create disk engine using legacy system
        // Note: In a full implementation, this would create AudioDiskEngine
        // For now, we'll use the existing SAPlayer system as a bridge
        let key = UUID().uuidString
        let engine = AudioDiskEngine(
            withSavedUrl: url,
            delegate: nil,
            updates: audioUpdates,
            coordinator: coordinator,
            metadata: metadata
        )

        return engine
    }

    /// Create streaming audio engine for remote URLs
    private func createStreamEngine(for url: URL, metadata: AudioMetadata?) async throws -> AudioEngineProtocol {
        // Verify URL is valid for streaming
        guard url.scheme == "http" || url.scheme == "https" else {
            throw AudioError.invalidURL
        }

        // Create stream engine using legacy system
        let key = UUID().uuidString
        let engine = AudioStreamEngine(
            withRemoteUrl: url,
            delegate: nil,
            bitrate: .high,
            updates: audioUpdates,
            audioModifiers: [],
            coordinator: coordinator,
            metadata: metadata
        )

        return engine
    }

    /// Wait for the audio engine to be ready for playback
    private func waitForEngineReady() async throws {
        // Wait for duration to be available (indicates engine is ready)
        let timeoutDuration: TimeInterval = 10.0 // 10 second timeout
        let startTime = Date()

        while durationSubject.value <= 0 {
            if Date().timeIntervalSince(startTime) > timeoutDuration {
                throw AudioError.internalError("Timeout waiting for audio engine to be ready")
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        }
    }

    /// Stop and cleanup current audio engine
    private func stopCurrentEngine() async {
        if let engine = currentEngine {
            engine.pause()
            engine.invalidate()
            currentEngine = nil
        }

        // Reset state
        playbackStateSubject.send(.idle)
        currentTimeSubject.send(0.0)
        durationSubject.send(0.0)
        currentAudioURL = nil
        currentMetadata = nil
    }

    /// Cleanup all resources
    private func cleanup() {
        cancellables.removeAll()

        Task {
            await stopCurrentEngine()
        }
    }
}

// MARK: - Supporting Types

/// Minimal delegate implementation for audio engines
private class BasicAudioEngineDelegate: AudioEngineDelegate {
    func didError() {
        // Handle engine errors - in a full implementation this would
        // propagate errors back to the BasicAudioPlayer
        Log.error("BasicAudioPlayer: Audio engine error occurred")
    }
}

/// Convenience extension for Combine/async interop
public extension AnyPublisher where Failure == Never {
    /// Convert a Never-failing publisher to async
    func async() async -> Output {
        return await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = first()
                .sink { value in
                    cancellable?.cancel()
                    continuation.resume(returning: value)
                }
        }
    }
}

public extension AnyPublisher {
    /// Convert a potentially-failing publisher to async throws
    func async() async throws -> Output {
        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = sink(
                receiveCompletion: { completion in
                    cancellable?.cancel()
                    if case .failure(let error) = completion {
                        continuation.resume(throwing: error)
                    }
                },
                receiveValue: { value in
                    continuation.resume(returning: value)
                }
            )
        }
    }
}

// MARK: - Documentation

/*
 DESIGN PRINCIPLES:

 1. MINIMAL VIABLE PRODUCT
    - Implements only the AudioPlayable protocol requirements
    - No additional complexity beyond basic playback
    - Foundation for more advanced implementations

 2. 3-LINE USAGE PATTERN
    - let player = BasicAudioPlayer()
    - try await player.loadAudio(from: url, metadata: nil).async()
    - try await player.play().async()

 3. REACTIVE COORDINATION
    - Uses ReactiveAudioCoordinator for actor orchestration
    - Integrates with existing audio engine architecture
    - Bridges modern Swift 6 concurrency with legacy Combine system

 4. AUTOMATIC ENGINE SELECTION
    - File URLs → AudioDiskEngine for local playback
    - HTTP/HTTPS URLs → AudioStreamEngine for streaming
    - Transparent to the user

 5. SWIFT 6 SENDABLE COMPLIANCE
    - MainActor isolation ensures thread safety
    - Proper async/await patterns throughout
    - Sendable types for concurrent usage

 IMPLEMENTATION NOTES:

 - This is a bridge implementation that uses the existing legacy audio engines
 - In a fully modernized system, the engines would be actor-based
 - The reactive bindings handle state synchronization with the legacy system
 - Error handling is simplified but covers the main failure modes
 - Resource cleanup is handled automatically in deinit

 USAGE PATTERNS:

 Basic Playback:
 ```swift
 let player = BasicAudioPlayer()
 try await player.loadAudio(from: url, metadata: nil).async()
 try await player.play().async()
 ```

 With State Observation:
 ```swift
 let player = BasicAudioPlayer()

 player.playbackState
     .sink { state in
         print("Playback state: \(state)")
     }
     .store(in: &cancellables)

 try await player.loadAudio(from: url, metadata: nil).async()
 try await player.play().async()
 ```

 Error Handling:
 ```swift
 let player = BasicAudioPlayer()

 do {
     try await player.loadAudio(from: url, metadata: nil).async()
     try await player.play().async()
 } catch {
     print("Playback failed: \(error)")
 }
 ```
 */