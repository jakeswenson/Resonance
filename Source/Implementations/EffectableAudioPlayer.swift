//
//  EffectableAudioPlayer.swift
//  Resonance
//
//  Enhanced audio player with real-time audio effects management.
//  Provides comprehensive effect chain control with live parameter manipulation.
//

import Foundation
import Combine
import AVFoundation

/// Enhanced audio player with real-time audio effects capabilities
///
/// EffectableAudioPlayer extends ConfigurableAudioPlayer with AudioEffectable features,
/// enabling sophisticated real-time audio processing with dynamic effect management.
///
/// **Enhanced usage pattern:**
/// ```swift
/// let player = EffectableAudioPlayer()
/// try await player.loadAudio(from: url, metadata: nil).async()
///
/// // Add effects to the chain
/// let reverb = AudioEffect(type: .reverb, parameters: [EffectParameterKeys.wetDryMix: 50.0])
/// try await player.addEffect(reverb).async()
///
/// // Real-time parameter control
/// try await player.updateEffectParameter(id: reverb.id, key: EffectParameterKeys.wetDryMix, value: 75.0).async()
/// ```
///
/// This implementation:
/// - Inherits all AudioConfigurable functionality from ConfigurableAudioPlayer
/// - Implements AudioEffectable for comprehensive effect management
/// - Uses EffectProcessorActor via ReactiveAudioCoordinator for thread safety
/// - Provides real-time effect processing without audio interruption
/// - Offers effect chain management with atomic operations
/// - Maintains Swift 6 concurrency and Sendable compliance
@MainActor
public class EffectableAudioPlayer: ConfigurableAudioPlayer, AudioEffectable, @unchecked Sendable {

    // MARK: - Enhanced Dependencies

    /// Access to effects processor through coordinator
    private var effectsCoordinator: ReactiveAudioCoordinator {
        return coordinator
    }

    // MARK: - Effects State Management

    /// Current effects chain subject for reactive updates
    private let effectsSubject = CurrentValueSubject<[AudioEffect], Never>([])

    /// Effects cancellables
    private var effectsCancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Initialize EffectableAudioPlayer with optional coordinator dependency injection
    /// - Parameter coordinator: Optional coordinator instance (defaults to shared)
    public override init(coordinator: ReactiveAudioCoordinator = .shared) {
        super.init(coordinator: coordinator)
        setupEffectsBindings()
    }

    deinit {
        // Note: Can't cleanup effectsCancellables from deinit due to Sendable requirements
        // Cancellables will be cleaned up automatically when the object is deallocated
    }

    // MARK: - AudioEffectable Protocol Implementation

    /// Publisher that emits the current effects chain
    public var currentEffects: AnyPublisher<[AudioEffect], Never> {
        effectsSubject.eraseToAnyPublisher()
    }

    /// Adds an audio effect to the processing chain
    public func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.effectsCoordinator.ensureReady()

                    // Validate effect before adding
                    guard effect.isValid else {
                        let missingParams = effect.missingRequiredParameters.joined(separator: ", ")
                        promise(.failure(.invalidInput("Effect missing required parameters: \(missingParams)")))
                        return
                    }

                    // Add effect through coordinator
                    try await self.effectsCoordinator.addEffect(effect)
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Added effect \(effect.displayName) (ID: \(effect.id))")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to add effect: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Removes an audio effect from the processing chain
    public func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.effectsCoordinator.ensureReady()

                    // Remove effect through coordinator
                    try await self.effectsCoordinator.removeEffect(id: effectId)
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Removed effect (ID: \(effectId))")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to remove effect: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Updates parameters of an existing effect in real-time
    public func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.effectsCoordinator.ensureReady()

                    // Validate parameters are not empty
                    guard !parameters.isEmpty else {
                        promise(.failure(.invalidInput("No parameters provided for update")))
                        return
                    }

                    // Update effect through coordinator
                    try await self.effectsCoordinator.updateEffect(id: effectId, parameters: parameters)
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Updated effect (ID: \(effectId)) with \(parameters.count) parameters")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to update effect: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Enables or disables an effect without removing it from the chain
    public func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.effectsCoordinator.ensureReady()

                    // Set effect enabled state through coordinator
                    try await self.effectsCoordinator.setEffectEnabled(id: effectId, enabled: enabled)
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Set effect (ID: \(effectId)) enabled: \(enabled)")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to set effect enabled state: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Removes all effects from the processing chain
    public func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.effectsCoordinator.ensureReady()

                    // Reset all effects through coordinator
                    try await self.effectsCoordinator.resetAllEffects()
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Reset all effects")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to reset effects: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Enhanced Effect Management

    /// Create and add an effect with default parameters
    public func addEffect(type effectType: EffectType) -> AnyPublisher<UUID, AudioError> {
        let effect = AudioEffect(
            type: effectType,
            parameters: effectType.defaultParameters,
            displayName: effectType.defaultDisplayName
        )

        return addEffect(effect)
            .map { effect.id }
            .eraseToAnyPublisher()
    }

    /// Perform multiple effect operations in sequence
    public func performBatchEffectOperations(_ operations: [EffectOperation]) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.effectsCoordinator.ensureReady()

                    // Perform batch operations through coordinator
                    try await self.effectsCoordinator.performBatchEffectOperations(operations)
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Performed \(operations.count) batch effect operations")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to perform batch operations: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Update a single effect parameter with type safety
    public func updateEffectParameter<T: Sendable>(
        id effectId: UUID,
        key: String,
        value: T
    ) -> AnyPublisher<Void, AudioError> {
        return updateEffect(id: effectId, parameters: [key: value])
    }

    /// Toggle effect enabled state
    public func toggleEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Get current effect state
                    let currentEffect = await self.effectsCoordinator.getEffect(id: effectId)

                    guard let effect = currentEffect else {
                        promise(.failure(.internalError("Effect not found: \(effectId)")))
                        return
                    }

                    // Toggle the enabled state
                    let newEnabledState = !effect.isEnabled
                    try await self.effectsCoordinator.setEffectEnabled(id: effectId, enabled: newEnabledState)
                    promise(.success(()))

                    Log.debug("EffectableAudioPlayer: Toggled effect (ID: \(effectId)) to \(newEnabledState)")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to toggle effect: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Get information about a specific effect in the chain
    public func getEffect(id effectId: UUID) -> AnyPublisher<AudioEffect?, Never> {
        return Future<AudioEffect?, Never> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.success(nil))
                    return
                }

                let effect = await self.effectsCoordinator.getEffect(id: effectId)
                promise(.success(effect))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Check if a specific effect is currently in the chain
    public func hasEffect(id effectId: UUID) -> AnyPublisher<Bool, Never> {
        return getEffect(id: effectId)
            .map { $0 != nil }
            .eraseToAnyPublisher()
    }

    /// Get all effects of a specific type
    public func getEffects(ofType effectType: EffectType) -> AnyPublisher<[AudioEffect], Never> {
        return currentEffects
            .map { effects in
                effects.filter { $0.type == effectType }
            }
            .eraseToAnyPublisher()
    }

    /// Count the total number of active effects
    public func effectCount() -> AnyPublisher<Int, Never> {
        return currentEffects
            .map { effects in
                effects.count
            }
            .eraseToAnyPublisher()
    }

    /// Count the number of enabled effects
    public func enabledEffectCount() -> AnyPublisher<Int, Never> {
        return currentEffects
            .map { effects in
                effects.filter { $0.isEnabled }.count
            }
            .eraseToAnyPublisher()
    }

    // MARK: - Enhanced Loading with Effects

    /// Enhanced loadAudio that applies effects to new content
    public override func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return super.loadAudio(from: url, metadata: metadata)
            .handleEvents(receiveOutput: { _ in
                Task { @MainActor in
                    // Effects are automatically applied through the coordinator
                    // but we can perform any additional setup here if needed
                    Log.debug("EffectableAudioPlayer: Audio loaded, effects chain active")
                }
            })
            .eraseToAnyPublisher()
    }

    // MARK: - Private Implementation

    /// Setup reactive bindings for effects management
    private func setupEffectsBindings() {
        // Monitor effects updates from coordinator
        effectsCoordinator.currentEffectsPublisher
            .sink { [weak self] effects in
                self?.effectsSubject.send(effects)
            }
            .store(in: &effectsCancellables)
    }

    /// Cleanup effects-related resources
    private func cleanupEffects() {
        effectsCancellables.removeAll()
        effectsSubject.send([])
    }
}

// MARK: - Logging Support


// MARK: - Documentation

/*
 DESIGN PRINCIPLES:

 1. REAL-TIME EFFECTS PROCESSING
    - All effect operations take place during active playback
    - Minimal audio interruption during effect changes
    - Immediate parameter feedback for user interfaces
    - Smooth transitions between effect states

 2. PROGRESSIVE ENHANCEMENT
    - Builds upon ConfigurableAudioPlayer foundation
    - Adds effects capabilities without breaking existing functionality
    - Compatible with any AudioConfigurable usage patterns
    - Maintains volume and playback rate controls alongside effects

 3. TYPE-SAFE EFFECT MANAGEMENT
    - Effect parameters use strongly-typed wrappers
    - Parameter validation prevents invalid configurations
    - Comprehensive error handling for effect operations
    - Clear separation between effect types and instances

 4. REACTIVE EFFECTS MONITORING
    - Current effects exposed as Combine publisher
    - Real-time updates for UI synchronization
    - Batch operations for complex effect sequences
    - Convenient helper methods for common operations

 5. THREAD-SAFE COORDINATION
    - Uses ReactiveAudioCoordinator to access EffectProcessorActor
    - All effect operations isolated to prevent audio glitches
    - Proper cleanup and resource management
    - MainActor isolation for UI thread safety

 USAGE PATTERNS:

 Basic Effect Usage:
 ```swift
 let player = EffectableAudioPlayer()
 try await player.loadAudio(from: url, metadata: nil).async()

 // Add reverb with default parameters
 let reverbId = try await player.addEffect(type: .reverb).async()

 // Add custom equalizer
 let eq = AudioEffect(
     type: .equalizer,
     parameters: [
         EffectParameterKeys.bands: EffectParameterValue([
             EQBand(frequency: 1000, gain: 3.0),
             EQBand(frequency: 5000, gain: -2.0)
         ])
     ]
 )
 try await player.addEffect(eq).async()
 ```

 Real-time Parameter Control:
 ```swift
 // Update reverb wet/dry mix in real-time
 try await player.updateEffectParameter(
     id: reverbId,
     key: EffectParameterKeys.wetDryMix,
     value: 75.0
 ).async()

 // Bind UI slider to effect parameter
 wetDrySlider.publisher(for: \.value)
     .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
     .sink { value in
         player.updateEffectParameter(
             id: reverbId,
             key: EffectParameterKeys.wetDryMix,
             value: value
         )
         .sink { _ in }
         .store(in: &cancellables)
     }
     .store(in: &cancellables)
 ```

 Effect Chain Monitoring:
 ```swift
 // Monitor effect changes for UI updates
 player.currentEffects
     .sink { effects in
         updateEffectsList(effects)
         updatePerformanceIndicator(enabledCount: effects.filter(\.isEnabled).count)
     }
     .store(in: &cancellables)

 // React to effect count changes
 player.effectCount()
     .sink { count in
         showEffectsPanel(visible: count > 0)
     }
     .store(in: &cancellables)
 ```

 Batch Operations:
 ```swift
 // Apply multiple effects at once
 let operations: [EffectOperation] = [
     .add(reverbEffect),
     .add(eqEffect),
     .update(reverbEffect.id, [EffectParameterKeys.wetDryMix: 30.0])
 ]

 try await player.performBatchEffectOperations(operations).async()
 ```

 Effect Management:
 ```swift
 // Toggle effect on/off
 try await player.toggleEffect(id: effectId).async()

 // Reset all effects for clean state
 try await player.resetAllEffects().async()

 // Check if specific effect exists
 let hasReverb = await player.hasEffect(id: reverbId).async()
 ```

 IMPLEMENTATION NOTES:

 - Effect changes take place immediately during playback
 - Parameter validation prevents invalid configurations
 - Effect chain order affects the final audio output
 - Disabled effects remain in chain but don't process audio
 - Batch operations are atomic where possible
 - UI controls should reflect current effect states accurately
 - Performance monitoring tracks effect processing overhead
 - Error handling is comprehensive but not disruptive
 - Memory management cleans up unused effects promptly
 - Thread safety is maintained across all effect operations

 PERFORMANCE CONSIDERATIONS:

 - Effects are processed in real-time with minimal CPU overhead
 - Parameter updates are optimized for smooth UI interaction
 - Effect enable/disable allows for performance management
 - Batch operations reduce processing overhead for complex changes
 - Memory usage is monitored and optimized automatically
 - Audio latency is kept minimal during effect processing
 */