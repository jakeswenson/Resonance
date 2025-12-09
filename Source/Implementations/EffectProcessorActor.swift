// EffectProcessorActor.swift - Thread-safe real-time audio effects processing
// Swift 6 Sendable compliant actor for managing AVAudioEngine effect chains

import Foundation
import AVFoundation
@preconcurrency import Combine

/// Thread-safe actor for managing real-time audio effects processing
///
/// EffectProcessorActor isolates all AVAudioEngine effect operations to prevent
/// audio glitches and threading issues while providing smooth real-time effect processing.
/// The actor manages the complete effect chain lifecycle, from creation to cleanup.
///
/// Key Features:
/// - Thread-safe effect chain management
/// - Real-time parameter updates without audio interruption
/// - Atomic effect chain modifications
/// - Reactive effect state monitoring via Combine
/// - Support for all AudioEffect types and custom AVAudioUnits
/// - Automatic effect ordering and connection management
/// - Live parameter validation and range clamping
/// - Efficient memory management with proper cleanup
///
/// Usage:
/// ```swift
/// let processor = EffectProcessorActor(audioEngine: engine, audioUpdates: updates)
/// let reverb = AudioEffect(type: .reverb, parameters: [EffectParameterKeys.wetDryMix: 50.0])
///
/// Task {
///     try await processor.addEffect(reverb)
///     try await processor.updateEffectParameter(reverb.id, key: EffectParameterKeys.wetDryMix, value: 75.0)
/// }
/// ```
@globalActor
public actor EffectProcessorActor {

    // MARK: - Actor Properties

    /// The audio engine managing the effect chain
    private let audioEngine: AVAudioEngine

    /// Central reactive updates hub
    private let audioUpdates: AudioUpdates

    /// Current effects chain in processing order
    private var effectsChain: [AudioEffect] = []

    /// Map of effect IDs to their corresponding AVAudioUnit instances
    private var effectUnits: [UUID: AVAudioUnit] = [:]

    /// Input node that feeds into the effect chain
    private let inputNode: AVAudioNode

    /// Output node that receives processed audio from the chain
    private let outputNode: AVAudioNode

    /// Subject for publishing current effects state
    private let effectsSubject = CurrentValueSubject<[AudioEffect], Never>([])

    /// Cancellables for internal subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a new effect processor actor
    /// - Parameters:
    ///   - audioEngine: The AVAudioEngine instance to manage effects on
    ///   - audioUpdates: Central reactive updates hub for publishing state changes
    ///   - inputNode: Input node for the effect chain (defaults to engine's inputNode)
    ///   - outputNode: Output node for the effect chain (defaults to engine's outputNode)
    public init(
        audioEngine: AVAudioEngine,
        audioUpdates: AudioUpdates,
        inputNode: AVAudioNode? = nil,
        outputNode: AVAudioNode? = nil
    ) {
        self.audioEngine = audioEngine
        self.audioUpdates = audioUpdates
        self.inputNode = inputNode ?? audioEngine.inputNode
        self.outputNode = outputNode ?? audioEngine.outputNode

        // Initial empty chain connection
        Task {
            await self.connectEffectChain()
        }
    }

    deinit {
        Task { [weak self] in
            await self?.cleanup()
        }
    }

    // MARK: - Public Interface

    /// Current effects chain as a publisher
    public var currentEffects: AnyPublisher<[AudioEffect], Never> {
        effectsSubject.eraseToAnyPublisher()
    }

    /// Adds an audio effect to the processing chain
    /// - Parameter effect: The audio effect to add
    /// - Throws: AudioError if effect creation or insertion fails
    public func addEffect(_ effect: AudioEffect) async throws {
        // Validate effect before processing
        guard effect.isValid else {
            throw AudioError.internalError("Effect missing required parameters: \(effect.missingRequiredParameters)")
        }

        // Create the AVAudioUnit for this effect
        let audioUnit = try await createAudioUnit(for: effect)

        // Safely modify the effect chain
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    // Stop engine temporarily to modify connections
                    let wasRunning = audioEngine.isRunning
                    if wasRunning {
                        audioEngine.stop()
                    }

                    // Add effect to chain and store unit reference
                    effectsChain.append(effect)
                    effectUnits[effect.id] = audioUnit

                    // Attach unit to engine and reconnect chain
                    audioEngine.attach(audioUnit)
                    connectEffectChain()

                    // Restart engine if it was running
                    if wasRunning {
                        try audioEngine.start()
                    }

                    // Update reactive state
                    effectsSubject.send(effectsChain)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AudioError.internalError("Failed to add effect: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Removes an audio effect from the processing chain
    /// - Parameter effectId: Unique identifier of the effect to remove
    /// - Throws: AudioError if effect removal fails
    public func removeEffect(id effectId: UUID) async throws {
        guard let effectIndex = effectsChain.firstIndex(where: { $0.id == effectId }),
              let audioUnit = effectUnits[effectId] else {
            // Effect not found - complete silently per protocol contract
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    // Stop engine temporarily to modify connections
                    let wasRunning = audioEngine.isRunning
                    if wasRunning {
                        audioEngine.stop()
                    }

                    // Remove effect from chain and clean up unit
                    effectsChain.remove(at: effectIndex)
                    effectUnits.removeValue(forKey: effectId)

                    // Detach unit from engine and reconnect chain
                    audioEngine.detach(audioUnit)
                    connectEffectChain()

                    // Restart engine if it was running
                    if wasRunning {
                        try audioEngine.start()
                    }

                    // Update reactive state
                    effectsSubject.send(effectsChain)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AudioError.internalError("Failed to remove effect: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Updates parameters of an existing effect in real-time
    /// - Parameters:
    ///   - effectId: Unique identifier of the effect to update
    ///   - parameters: Dictionary of parameter keys and new values
    /// - Throws: AudioError if parameter update fails
    public func updateEffect(id effectId: UUID, parameters: [String: any Sendable]) async throws {
        guard let effectIndex = effectsChain.firstIndex(where: { $0.id == effectId }),
              let audioUnit = effectUnits[effectId] else {
            throw AudioError.internalError("Effect with ID \(effectId) not found")
        }

        let currentEffect = effectsChain[effectIndex]

        // Convert parameters to EffectParameterValue
        var convertedParameters: [String: EffectParameterValue] = [:]
        for (key, value) in parameters {
            convertedParameters[key] = EffectParameterValue(value)
        }

        // Create updated effect
        let updatedEffect = currentEffect.updated(parameters: convertedParameters)

        // Validate updated effect
        guard updatedEffect.isValid else {
            throw AudioError.internalError("Updated effect missing required parameters: \(updatedEffect.missingRequiredParameters)")
        }

        // Apply parameters to the audio unit
        try await applyParameters(updatedEffect, to: audioUnit)

        // Update the effect in our chain
        effectsChain[effectIndex] = updatedEffect

        // Update reactive state
        effectsSubject.send(effectsChain)
    }

    /// Updates a single effect parameter with type safety
    /// - Parameters:
    ///   - effectId: Unique identifier of the effect to update
    ///   - key: Parameter key to update
    ///   - value: New parameter value
    /// - Throws: AudioError if parameter update fails
    public func updateEffectParameter<T: Sendable>(id effectId: UUID, key: String, value: T) async throws {
        try await updateEffect(id: effectId, parameters: [key: value])
    }

    /// Enables or disables an effect without removing it from the chain
    /// - Parameters:
    ///   - effectId: Unique identifier of the effect to modify
    ///   - enabled: New enabled state for the effect
    /// - Throws: AudioError if state change fails
    public func setEffectEnabled(id effectId: UUID, enabled: Bool) async throws {
        guard let effectIndex = effectsChain.firstIndex(where: { $0.id == effectId }),
              let audioUnit = effectUnits[effectId] else {
            throw AudioError.internalError("Effect with ID \(effectId) not found")
        }

        let currentEffect = effectsChain[effectIndex]
        let updatedEffect = currentEffect.updated(isEnabled: enabled)

        // Apply bypass state to the audio unit
        audioUnit.bypass = !enabled

        // Update the effect in our chain
        effectsChain[effectIndex] = updatedEffect

        // Update reactive state
        effectsSubject.send(effectsChain)
    }

    /// Removes all effects from the processing chain
    /// - Throws: AudioError if reset operation fails
    public func resetAllEffects() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    // Stop engine temporarily to modify connections
                    let wasRunning = audioEngine.isRunning
                    if wasRunning {
                        audioEngine.stop()
                    }

                    // Detach all effect units
                    for (_, audioUnit) in effectUnits {
                        audioEngine.detach(audioUnit)
                    }

                    // Clear all effects and units
                    effectsChain.removeAll()
                    effectUnits.removeAll()

                    // Reconnect clean chain
                    connectEffectChain()

                    // Restart engine if it was running
                    if wasRunning {
                        try audioEngine.start()
                    }

                    // Update reactive state
                    effectsSubject.send(effectsChain)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AudioError.internalError("Failed to reset effects: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Reorders effects in the processing chain
    /// - Parameters:
    ///   - effectId: Effect to move
    ///   - newIndex: New position in the chain
    /// - Throws: AudioError if reorder operation fails
    public func moveEffect(id effectId: UUID, to newIndex: Int) async throws {
        guard let currentIndex = effectsChain.firstIndex(where: { $0.id == effectId }) else {
            throw AudioError.internalError("Effect with ID \(effectId) not found")
        }

        guard newIndex >= 0 && newIndex < effectsChain.count else {
            throw AudioError.internalError("Invalid target index: \(newIndex)")
        }

        guard currentIndex != newIndex else {
            // No change needed
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Task {
                do {
                    // Stop engine temporarily to modify connections
                    let wasRunning = audioEngine.isRunning
                    if wasRunning {
                        audioEngine.stop()
                    }

                    // Move effect in chain
                    let effect = effectsChain.remove(at: currentIndex)
                    effectsChain.insert(effect, at: newIndex)

                    // Reconnect chain with new order
                    connectEffectChain()

                    // Restart engine if it was running
                    if wasRunning {
                        try audioEngine.start()
                    }

                    // Update reactive state
                    effectsSubject.send(effectsChain)

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: AudioError.internalError("Failed to reorder effects: \(error.localizedDescription)"))
                }
            }
        }
    }

    /// Gets information about a specific effect in the chain
    /// - Parameter effectId: Unique identifier of the effect
    /// - Returns: The effect if found, nil otherwise
    public func getEffect(id effectId: UUID) async -> AudioEffect? {
        return effectsChain.first { $0.id == effectId }
    }

    /// Gets all effects of a specific type
    /// - Parameter effectType: Type of effects to retrieve
    /// - Returns: Array of matching effects
    public func getEffects(ofType effectType: EffectType) async -> [AudioEffect] {
        return effectsChain.filter { $0.type == effectType }
    }

    /// Returns the current number of effects in the chain
    /// - Returns: Effect count
    public func effectCount() async -> Int {
        return effectsChain.count
    }

    /// Returns the number of enabled effects
    /// - Returns: Enabled effect count
    public func enabledEffectCount() async -> Int {
        return effectsChain.filter { $0.isEnabled }.count
    }

    // MARK: - Private Implementation

    /// Creates an AVAudioUnit for the specified effect
    /// - Parameter effect: The audio effect to create a unit for
    /// - Returns: Configured AVAudioUnit
    /// - Throws: AudioError if unit creation fails
    private func createAudioUnit(for effect: AudioEffect) async throws -> AVAudioUnit {
        let audioUnit: AVAudioUnit

        switch effect.type {
        case .timePitch:
            let unit = AVAudioUnitTimePitch()
            audioUnit = unit

        case .reverb:
            let unit = AVAudioUnitReverb()
            audioUnit = unit

        case .equalizer:
            let unit = AVAudioUnitEQ(numberOfBands: 10) // Default 10-band EQ
            audioUnit = unit

        case .compressor:
            let unit = AVAudioUnitDistortion()
            unit.loadFactoryPreset(.speechCosmicInterfere)
            audioUnit = unit

        case .distortion:
            let unit = AVAudioUnitDistortion()
            audioUnit = unit

        case .delay:
            let unit = AVAudioUnitDelay()
            audioUnit = unit

        case .filter:
            let unit = AVAudioUnitEQ(numberOfBands: 1)
            unit.bands[0].filterType = .lowPass
            audioUnit = unit

        case .pitchShift:
            let unit = AVAudioUnitTimePitch()
            audioUnit = unit

        case .custom(let description):
            // Load custom audio unit
            audioUnit = try await withCheckedThrowingContinuation { continuation in
                AVAudioUnit.instantiate(with: description, options: []) { audioUnit, error in
                    if let error = error {
                        continuation.resume(throwing: AudioError.internalError("Failed to create custom audio unit: \(error.localizedDescription)"))
                        return
                    }
                    guard let audioUnit = audioUnit else {
                        continuation.resume(throwing: AudioError.internalError("Custom audio unit creation returned nil"))
                        return
                    }
                    continuation.resume(returning: audioUnit)
                }
            }
        }

        // Apply initial parameters
        try await applyParameters(effect, to: audioUnit)

        // Set initial enabled state
        audioUnit.bypass = !effect.isEnabled

        return audioUnit
    }

    /// Applies effect parameters to an audio unit
    /// - Parameters:
    ///   - effect: The effect containing parameters to apply
    ///   - audioUnit: The audio unit to configure
    /// - Throws: AudioError if parameter application fails
    private func applyParameters(_ effect: AudioEffect, to audioUnit: AVAudioUnit) async throws {
        switch effect.type {
        case .timePitch:
            guard let timePitchUnit = audioUnit as? AVAudioUnitTimePitch else {
                throw AudioError.internalError("Invalid audio unit type for time/pitch effect")
            }

            if let rate = effect.parameter(EffectParameterKeys.rate, as: Float.self) {
                timePitchUnit.rate = max(0.5, min(4.0, rate))
            }
            if let pitch = effect.parameter(EffectParameterKeys.pitch, as: Float.self) {
                timePitchUnit.pitch = max(-2400, min(2400, pitch))
            }

        case .reverb:
            guard let reverbUnit = audioUnit as? AVAudioUnitReverb else {
                throw AudioError.internalError("Invalid audio unit type for reverb effect")
            }

            if let wetDryMix = effect.parameter(EffectParameterKeys.wetDryMix, as: Float.self) {
                reverbUnit.wetDryMix = max(0.0, min(100.0, wetDryMix))
            }

        case .equalizer:
            guard let eqUnit = audioUnit as? AVAudioUnitEQ else {
                throw AudioError.internalError("Invalid audio unit type for equalizer effect")
            }

            if let bands = effect.parameter(EffectParameterKeys.bands, as: [EQBand].self) {
                for (index, band) in bands.prefix(eqUnit.bands.count).enumerated() {
                    let eqBand = eqUnit.bands[index]
                    eqBand.frequency = band.frequency
                    eqBand.gain = band.gain
                    eqBand.bandwidth = band.bandwidth
                    eqBand.bypass = !band.isEnabled
                }
            }

            if let globalGain = effect.parameter(EffectParameterKeys.globalGain, as: Float.self) {
                eqUnit.globalGain = max(-96.0, min(24.0, globalGain))
            }

        case .compressor:
            // Note: AVAudioUnitDistortion with compressor preset
            // Parameters would need to be mapped to distortion unit parameters
            break

        case .distortion:
            guard let distortionUnit = audioUnit as? AVAudioUnitDistortion else {
                throw AudioError.internalError("Invalid audio unit type for distortion effect")
            }

            if let preGain = effect.parameter(EffectParameterKeys.preGain, as: Float.self) {
                distortionUnit.preGain = max(-40.0, min(40.0, preGain))
            }
            if let wetDryMix = effect.parameter(EffectParameterKeys.wetDryMix, as: Float.self) {
                distortionUnit.wetDryMix = max(0.0, min(100.0, wetDryMix))
            }

        case .delay:
            guard let delayUnit = audioUnit as? AVAudioUnitDelay else {
                throw AudioError.internalError("Invalid audio unit type for delay effect")
            }

            if let delayTime = effect.parameter(EffectParameterKeys.delayTime, as: Float.self) {
                delayUnit.delayTime = TimeInterval(max(0.0, min(2.0, delayTime)))
            }
            if let feedback = effect.parameter(EffectParameterKeys.feedback, as: Float.self) {
                delayUnit.feedback = max(0.0, min(1.0, feedback))
            }
            if let wetDryMix = effect.parameter(EffectParameterKeys.wetDryMix, as: Float.self) {
                delayUnit.wetDryMix = max(0.0, min(100.0, wetDryMix))
            }

        case .filter:
            guard let eqUnit = audioUnit as? AVAudioUnitEQ else {
                throw AudioError.internalError("Invalid audio unit type for filter effect")
            }

            if let cutoffFrequency = effect.parameter(EffectParameterKeys.cutoffFrequency, as: Float.self) {
                eqUnit.bands[0].frequency = max(20.0, min(20000.0, cutoffFrequency))
            }
            if let resonance = effect.parameter(EffectParameterKeys.resonance, as: Float.self) {
                eqUnit.bands[0].bandwidth = max(0.05, min(5.0, resonance))
            }

        case .pitchShift:
            guard let pitchUnit = audioUnit as? AVAudioUnitTimePitch else {
                throw AudioError.internalError("Invalid audio unit type for pitch shift effect")
            }

            if let pitch = effect.parameter(EffectParameterKeys.pitch, as: Float.self) {
                pitchUnit.pitch = max(-2400, min(2400, pitch))
            }

        case .custom:
            // Custom audio units would need specific parameter handling
            // This would typically involve AU parameter trees
            break
        }
    }

    /// Connects the effect chain by wiring audio nodes together
    private func connectEffectChain() {
        // Disconnect all existing connections to this chain
        audioEngine.disconnectNodeInput(outputNode)

        if effectsChain.isEmpty {
            // Direct connection when no effects
            let format = inputNode.outputFormat(forBus: 0)
            audioEngine.connect(inputNode, to: outputNode, format: format)
        } else {
            // Chain effects together
            var previousNode: AVAudioNode = inputNode
            let format = inputNode.outputFormat(forBus: 0)

            for effect in effectsChain {
                guard let audioUnit = effectUnits[effect.id] else { continue }

                // Connect previous node to this effect
                audioEngine.connect(previousNode, to: audioUnit, format: format)
                previousNode = audioUnit
            }

            // Connect final effect to output
            audioEngine.connect(previousNode, to: outputNode, format: format)
        }
    }

    /// Cleanup resources
    private func cleanup() {
        // Clean up all effect units
        for (_, audioUnit) in effectUnits {
            if audioEngine.attachedNodes.contains(audioUnit) {
                audioEngine.detach(audioUnit)
            }
        }

        effectsChain.removeAll()
        effectUnits.removeAll()
        cancellables.removeAll()

        // Send final empty state
        effectsSubject.send([])
        effectsSubject.send(completion: .finished)
    }
}

// MARK: - Global Actor Definition

extension EffectProcessorActor: GlobalActor {
    public static let shared = EffectProcessorActor(
        audioEngine: AVAudioEngine(),
        audioUpdates: AudioUpdates()
    )
}

// MARK: - AudioEffectable Protocol Integration

extension EffectProcessorActor {

    /// Performs multiple effect operations in sequence
    /// - Parameter operations: Array of effect operations to perform
    /// - Returns: Publisher that completes when all operations succeed or fails with AudioError
    public func performBatchEffectOperations(_ operations: [EffectOperation]) async throws {
        for operation in operations {
            switch operation {
            case .add(let effect):
                try await addEffect(effect)
            case .remove(let id):
                try await removeEffect(id: id)
            case .update(let id, let parameters):
                try await updateEffect(id: id, parameters: parameters)
            case .setEnabled(let id, let enabled):
                try await setEffectEnabled(id: id, enabled: enabled)
            case .reset:
                try await resetAllEffects()
            }
        }
    }

    /// Convenience method for creating and adding common effects
    /// - Parameter effectType: Type of effect to create and add
    /// - Returns: The ID of the created effect
    /// - Throws: AudioError if effect creation or addition fails
    public func addEffect(type effectType: EffectType) async throws -> UUID {
        let effect = AudioEffect(
            type: effectType,
            parameters: effectType.defaultParameters,
            displayName: effectType.defaultDisplayName
        )

        try await addEffect(effect)
        return effect.id
    }
}