// AudioEffectable.swift - Protocol for real-time audio effects management
// Swift 6 Sendable compliant protocol extending AudioConfigurable with effects capabilities

import Foundation
import Combine

/// Enhanced protocol for real-time audio effects management and manipulation
///
/// AudioEffectable extends AudioConfigurable with comprehensive real-time audio effects
/// capabilities, enabling dynamic audio processing during playback without interruption.
///
/// This protocol provides:
/// - Real-time effect chain management (add, remove, update, reorder)
/// - Individual effect parameter manipulation during playback
/// - Effect enable/disable controls for A/B testing
/// - Reactive effect state monitoring through Combine publishers
/// - Type-safe effect parameter handling with validation
/// - Effect chain optimization and performance management
/// - Swift 6 Sendable compliance for concurrent usage
///
/// Usage example:
/// ```swift
/// let player = SomeAudioEffectable()
/// let reverb = AudioEffect(type: .reverb, parameters: [EffectParameterKeys.wetDryMix: 50.0])
///
/// player.addEffect(reverb)
///     .sink { _ in print("Reverb added") }
///     .store(in: &cancellables)
///
/// player.updateEffect(id: reverb.id, parameters: [EffectParameterKeys.wetDryMix: 75.0])
///     .sink { _ in print("Reverb updated") }
///     .store(in: &cancellables)
/// ```
@MainActor
public protocol AudioEffectable: AudioConfigurable {

    // MARK: - Effect State Publishers

    /// Publisher that emits the current effects chain
    ///
    /// Emits the complete array of currently active effects in chain order.
    /// Initial state should be an empty array for new instances.
    /// Updates whenever effects are added, removed, reordered, or modified.
    /// The order of effects in the array represents their processing order.
    ///
    /// - Returns: Publisher that never fails and emits [AudioEffect] values
    var currentEffects: AnyPublisher<[AudioEffect], Never> { get }

    // MARK: - Effect Management

    /// Adds an audio effect to the processing chain
    ///
    /// Appends the effect to the end of the current effect chain.
    /// The effect will be applied after all existing effects in the chain.
    /// Effect parameters are validated before addition and invalid effects are rejected.
    ///
    /// For real-time addition during playback:
    /// - Effect processing begins immediately upon successful addition
    /// - Audio processing may briefly pause during effect initialization
    /// - Invalid effects fail without affecting current playback
    ///
    /// - Parameter effect: The audio effect to add to the chain
    /// - Returns: Publisher that completes when effect is added or fails with AudioError
    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError>

    /// Removes an audio effect from the processing chain
    ///
    /// Removes the effect with the specified ID from the current effect chain.
    /// Remaining effects maintain their relative order and continue processing.
    /// If the effect is not found, the operation completes without error.
    ///
    /// For real-time removal during playback:
    /// - Effect processing stops immediately upon removal
    /// - Audio processing may briefly pause during effect cleanup
    /// - Chain continues processing with remaining effects
    ///
    /// - Parameter effectId: Unique identifier of the effect to remove
    /// - Returns: Publisher that completes when effect is removed or fails with AudioError
    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError>

    /// Updates parameters of an existing effect in real-time
    ///
    /// Modifies the parameters of the effect with the specified ID.
    /// Changes take effect immediately during playback without interruption.
    /// Only the specified parameters are updated; others remain unchanged.
    /// Parameter values are validated and invalid values are rejected.
    ///
    /// Real-time parameter updates enable:
    /// - Live effect manipulation during performance
    /// - Smooth parameter transitions and automation
    /// - A/B testing of different effect settings
    /// - User interface controls with immediate feedback
    ///
    /// - Parameters:
    ///   - effectId: Unique identifier of the effect to update
    ///   - parameters: Dictionary of parameter keys and new values
    /// - Returns: Publisher that completes when parameters are updated or fails with AudioError
    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError>

    /// Enables or disables an effect without removing it from the chain
    ///
    /// Changes the enabled state of the effect with the specified ID.
    /// Disabled effects remain in the chain but do not process audio.
    /// This allows for quick A/B testing and temporary effect bypass.
    ///
    /// Real-time enable/disable operations:
    /// - State changes take effect immediately during playback
    /// - No audio interruption or processing gaps
    /// - Effect parameters and position in chain are preserved
    /// - Useful for performance optimization and creative control
    ///
    /// - Parameters:
    ///   - effectId: Unique identifier of the effect to modify
    ///   - enabled: New enabled state for the effect
    /// - Returns: Publisher that completes when state is changed or fails with AudioError
    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError>

    /// Removes all effects from the processing chain
    ///
    /// Clears the entire effect chain, returning audio processing to the unprocessed signal.
    /// All effects are removed simultaneously and effect processing stops immediately.
    /// This operation is useful for:
    /// - Resetting effects to a clean state
    /// - Performance optimization when effects are not needed
    /// - Emergency bypass of problematic effects
    /// - Preparing for a new set of effects
    ///
    /// - Returns: Publisher that completes when all effects are removed or fails with AudioError
    func resetAllEffects() -> AnyPublisher<Void, AudioError>
}

// MARK: - Protocol Extensions

extension AudioEffectable {

    /// Convenience method for creating and adding common effects
    ///
    /// Creates an effect with the specified type and default parameters,
    /// then adds it to the processing chain. Uses the effect type's
    /// default parameter values and a generated display name.
    ///
    /// - Parameter effectType: Type of effect to create and add
    /// - Returns: Publisher that emits the created effect's ID or fails with AudioError
    func addEffect(type effectType: EffectType) -> AnyPublisher<UUID, AudioError> {
        let effect = AudioEffect(
            type: effectType,
            parameters: effectType.defaultParameters.mapValues { $0 },
            displayName: effectType.defaultDisplayName
        )

        return addEffect(effect)
            .map { effect.id }
            .eraseToAnyPublisher()
    }

    /// Convenience method for batch effect operations
    ///
    /// Performs multiple effect operations in sequence, ensuring proper
    /// ordering and error handling. If any operation fails, the entire
    /// batch fails and previous operations are not rolled back.
    ///
    /// - Parameter operations: Array of effect operations to perform
    /// - Returns: Publisher that completes when all operations succeed or fails with AudioError
    func performBatchEffectOperations(_ operations: [EffectOperation]) -> AnyPublisher<Void, AudioError> {
        operations.reduce(Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()) { result, operation in
            result.flatMap { _ -> AnyPublisher<Void, AudioError> in
                switch operation {
                case .add(let effect):
                    return self.addEffect(effect)
                case .remove(let id):
                    return self.removeEffect(id: id)
                case .update(let id, let parameters):
                    return self.updateEffect(id: id, parameters: parameters)
                case .setEnabled(let id, let enabled):
                    return self.setEffectEnabled(id: id, enabled: enabled)
                case .reset:
                    return self.resetAllEffects()
                }
            }
            .eraseToAnyPublisher()
        }
    }

    /// Convenience method for updating a single effect parameter
    ///
    /// Updates a single parameter of an existing effect with type safety.
    /// This is more convenient than creating a full parameter dictionary
    /// for single-value updates.
    ///
    /// - Parameters:
    ///   - effectId: Unique identifier of the effect
    ///   - key: Parameter key to update
    ///   - value: New parameter value
    /// - Returns: Publisher that completes when parameter is updated or fails with AudioError
    func updateEffectParameter<T: Sendable>(
        id effectId: UUID,
        key: String,
        value: T
    ) -> AnyPublisher<Void, AudioError> {
        return updateEffect(id: effectId, parameters: [key: value])
    }

    /// Convenience method for toggling effect enabled state
    ///
    /// Switches the enabled state of an effect based on its current state.
    /// If the effect is currently enabled, it will be disabled, and vice versa.
    /// This is useful for UI toggle controls and keyboard shortcuts.
    ///
    /// - Parameter effectId: Unique identifier of the effect to toggle
    /// - Returns: Publisher that completes when state is toggled or fails with AudioError
    func toggleEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        currentEffects
            .first()
            .compactMap { effects in
                effects.first { $0.id == effectId }
            }
            .flatMap { effect -> AnyPublisher<Void, AudioError> in
                return self.setEffectEnabled(id: effectId, enabled: !effect.isEnabled)
            }
            .eraseToAnyPublisher()
    }

    /// Gets information about a specific effect in the chain
    ///
    /// Retrieves the current state and parameters of an effect by its ID.
    /// This is useful for UI synchronization and effect state monitoring.
    ///
    /// - Parameter effectId: Unique identifier of the effect
    /// - Returns: Publisher that emits the effect or nil if not found
    func getEffect(id effectId: UUID) -> AnyPublisher<AudioEffect?, Never> {
        currentEffects
            .map { effects in
                effects.first { $0.id == effectId }
            }
            .eraseToAnyPublisher()
    }

    /// Checks if a specific effect is currently in the chain
    ///
    /// Determines whether an effect with the specified ID is currently
    /// active in the processing chain, regardless of its enabled state.
    ///
    /// - Parameter effectId: Unique identifier of the effect
    /// - Returns: Publisher that emits true if effect exists, false otherwise
    func hasEffect(id effectId: UUID) -> AnyPublisher<Bool, Never> {
        currentEffects
            .map { effects in
                effects.contains { $0.id == effectId }
            }
            .eraseToAnyPublisher()
    }

    /// Gets all effects of a specific type
    ///
    /// Filters the current effect chain to return only effects of the specified type.
    /// This is useful for managing groups of similar effects or enforcing limits.
    ///
    /// - Parameter effectType: Type of effects to retrieve
    /// - Returns: Publisher that emits array of matching effects
    func getEffects(ofType effectType: EffectType) -> AnyPublisher<[AudioEffect], Never> {
        currentEffects
            .map { effects in
                effects.filter { $0.type == effectType }
            }
            .eraseToAnyPublisher()
    }

    /// Counts the total number of active effects
    ///
    /// Returns the number of effects currently in the processing chain,
    /// including both enabled and disabled effects.
    ///
    /// - Returns: Publisher that emits the effect count
    func effectCount() -> AnyPublisher<Int, Never> {
        currentEffects
            .map { effects in
                effects.count
            }
            .eraseToAnyPublisher()
    }

    /// Counts the number of enabled effects
    ///
    /// Returns the number of effects that are currently enabled and
    /// actively processing audio in the chain.
    ///
    /// - Returns: Publisher that emits the enabled effect count
    func enabledEffectCount() -> AnyPublisher<Int, Never> {
        currentEffects
            .map { effects in
                effects.filter { $0.isEnabled }.count
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - Supporting Types

/// Enumeration of batch effect operations
public enum EffectOperation: Sendable {
    /// Add an effect to the chain
    case add(AudioEffect)

    /// Remove an effect by ID
    case remove(UUID)

    /// Update effect parameters
    case update(UUID, [String: EffectParameterValue])

    /// Set effect enabled state
    case setEnabled(UUID, Bool)

    /// Reset all effects
    case reset
}

// MARK: - Documentation Notes

/*
 DESIGN PRINCIPLES:

 1. REAL-TIME PROCESSING
    - All effect operations take place during active playback
    - Minimal audio interruption during effect changes
    - Immediate parameter feedback for user interfaces
    - Smooth transitions between effect states

 2. TYPE-SAFE EFFECT MANAGEMENT
    - Effect parameters use strongly-typed wrappers
    - Parameter validation prevents invalid configurations
    - Comprehensive error handling for effect operations
    - Clear separation between effect types and instances

 3. REACTIVE EFFECT MONITORING
    - Current effects exposed as Combine publisher
    - Real-time updates for UI synchronization
    - Batch operations for complex effect sequences
    - Convenient helper methods for common operations

 4. SWIFT 6 SENDABLE COMPLIANCE
    - All effect types maintain Sendable conformance
    - Thread-safe parameter updates and state changes
    - MainActor isolation for UI thread safety
    - Concurrent effect processing support

 5. PERFORMANCE OPTIMIZATION
    - Effect enable/disable for performance management
    - Batch operations reduce processing overhead
    - Lazy effect loading and cleanup
    - Efficient effect chain management

 USAGE PATTERNS:

 Basic Effect Addition:
 ```swift
 // Add reverb with default parameters
 player.addEffect(type: .reverb)
     .sink { reverbId in
         print("Reverb added with ID: \(reverbId)")
     }
     .store(in: &cancellables)

 // Add custom equalizer
 let eq = AudioEffect(
     type: .equalizer,
     parameters: [
         EffectParameterKeys.bands: [
             EQBand(frequency: 1000, gain: 3.0),
             EQBand(frequency: 5000, gain: -2.0)
         ]
     ]
 )
 player.addEffect(eq)
 ```

 Real-time Parameter Control:
 ```swift
 // Update reverb wet/dry mix in real-time
 player.updateEffectParameter(id: reverbId, key: EffectParameterKeys.wetDryMix, value: 75.0)
     .sink { _ in print("Reverb updated") }
     .store(in: &cancellables)

 // Bind UI slider to effect parameter
 wetDrySlider.publisher(for: \.value)
     .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
     .flatMap { value in
         player.updateEffectParameter(id: reverbId, key: EffectParameterKeys.wetDryMix, value: value)
     }
     .sink { _ in }
     .store(in: &cancellables)
 ```

 Effect Chain Monitoring:
 ```swift
 // Monitor effect changes for UI updates
 player.currentEffects
     .sink { effects in
         updateEffectList(effects)
         updatePerformanceIndicator(enabledCount: effects.filter(\.isEnabled).count)
     }
     .store(in: &cancellables)

 // React to effect count changes
 player.effectCount()
     .sink { count in
         showEffectPanel(visible: count > 0)
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

 player.performBatchEffectOperations(operations)
     .sink(receiveCompletion: { completion in
         if case .failure(let error) = completion {
             print("Batch operation failed: \(error)")
         }
     }, receiveValue: { _ in
         print("All effects applied successfully")
     })
     .store(in: &cancellables)
 ```

 Effect Management:
 ```swift
 // Toggle effect on/off
 player.toggleEffect(id: effectId)
     .sink { _ in print("Effect toggled") }
     .store(in: &cancellables)

 // Reset all effects for clean state
 player.resetAllEffects()
     .sink { _ in print("All effects cleared") }
     .store(in: &cancellables)

 // Check if specific effect exists
 player.hasEffect(id: effectId)
     .sink { exists in
         enableEffectControls(exists)
     }
     .store(in: &cancellables)
 ```

 IMPLEMENTATION GUIDELINES:

 - Effect changes should take place immediately during playback
 - Parameter validation should prevent invalid configurations
 - Effect chain order affects the final audio output
 - Disabled effects should remain in chain but not process audio
 - Batch operations should be atomic where possible
 - UI controls should reflect current effect states accurately
 - Performance monitoring should track effect processing overhead
 - Error handling should be comprehensive but not disruptive
 - Memory management should clean up unused effects promptly
 - Thread safety must be maintained across all effect operations
 */