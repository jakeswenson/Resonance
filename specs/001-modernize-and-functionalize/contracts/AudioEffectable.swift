// AudioEffectable.swift - Advanced Protocol for Real-time Audio Effects
// Contract Test: Must verify effect application and real-time parameter changes

import Foundation
import Combine
import AVFoundation

/// Advanced protocol for real-time audio effects and processing
/// Provides access to AVAudioEngine effect chain for professional audio manipulation
public protocol AudioEffectable: AudioConfigurable {

    /// Apply an audio effect to the processing chain
    /// - Parameter effect: Audio effect to add
    /// - Returns: Publisher that completes when effect is applied or fails
    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError>

    /// Remove an audio effect from the processing chain
    /// - Parameter effectId: Unique identifier of effect to remove
    /// - Returns: Publisher that completes when effect is removed or fails
    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError>

    /// Update parameters of an existing effect in real-time
    /// - Parameter effectId: Unique identifier of effect to modify
    /// - Parameter parameters: New parameter values
    /// - Returns: Publisher that completes when parameters are updated
    func updateEffect(id effectId: UUID,
                     parameters: [String: Any]) -> AnyPublisher<Void, AudioError>

    /// Enable or disable an effect without removing it
    /// - Parameter effectId: Unique identifier of effect
    /// - Parameter enabled: Whether effect should be active
    /// - Returns: Publisher that completes when effect state changes
    func setEffectEnabled(id effectId: UUID,
                         enabled: Bool) -> AnyPublisher<Void, AudioError>

    /// Get current list of applied effects
    var currentEffects: AnyPublisher<[AudioEffect], Never> { get }

    /// Reset all effects to default state
    /// - Returns: Publisher that completes when all effects are reset
    func resetAllEffects() -> AnyPublisher<Void, AudioError>
}

// MARK: - Supporting Types

public struct AudioEffect {
    /// Unique identifier for this effect instance
    public let id: UUID

    /// Type of audio effect
    public let type: EffectType

    /// Effect-specific parameters
    public let parameters: [String: Any]

    /// Whether effect is currently enabled
    public let isEnabled: Bool

    /// Display name for user interfaces
    public let displayName: String

    public init(id: UUID = UUID(),
                type: EffectType,
                parameters: [String: Any] = [:],
                isEnabled: Bool = true,
                displayName: String? = nil) {
        self.id = id
        self.type = type
        self.parameters = parameters
        self.isEnabled = isEnabled
        self.displayName = displayName ?? type.defaultDisplayName
    }
}

public enum EffectType {
    /// Time/pitch manipulation (rate without pitch change)
    case timePitch

    /// Reverb effect
    case reverb

    /// Parametric equalizer
    case equalizer

    /// Audio compression/limiting
    case compressor

    /// Distortion effect
    case distortion

    /// Custom AVAudioUnit
    case custom(description: AudioComponentDescription)

    /// Default display name for effect type
    var defaultDisplayName: String {
        switch self {
        case .timePitch: return "Time/Pitch"
        case .reverb: return "Reverb"
        case .equalizer: return "Equalizer"
        case .compressor: return "Compressor"
        case .distortion: return "Distortion"
        case .custom: return "Custom Effect"
        }
    }
}

/// Standard effect parameter keys for consistency across implementations
public struct EffectParameterKeys {
    // Time/Pitch parameters
    public static let rate = "rate"           // Float: 0.5 to 4.0
    public static let pitch = "pitch"         // Float: -2400 to 2400 cents

    // Reverb parameters
    public static let wetDryMix = "wetDryMix" // Float: 0.0 to 100.0

    // Equalizer parameters
    public static let bands = "bands"         // [EQBand]
    public static let globalGain = "globalGain" // Float: -96.0 to 24.0 dB

    // Compressor parameters
    public static let threshold = "threshold" // Float: -40.0 to 20.0 dB
    public static let ratio = "ratio"         // Float: 1.0 to 20.0
    public static let attack = "attack"       // Float: 0.0001 to 0.2 seconds
    public static let release = "release"     // Float: 0.01 to 3.0 seconds
}

public struct EQBand {
    /// Center frequency in Hz
    public let frequency: Float

    /// Gain in dB (-96.0 to 24.0)
    public let gain: Float

    /// Bandwidth (0.05 to 5.0)
    public let bandwidth: Float

    /// Whether this band is enabled
    public let isEnabled: Bool

    public init(frequency: Float, gain: Float, bandwidth: Float = 1.0, isEnabled: Bool = true) {
        self.frequency = frequency
        self.gain = gain
        self.bandwidth = bandwidth
        self.isEnabled = isEnabled
    }
}