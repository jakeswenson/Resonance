// AudioEffect.swift - Audio effect and effect type definitions
// Swift 6 Sendable compliant types for audio effect management

import Foundation
import AVFoundation

/// Represents a configurable audio processing effect
/// This struct is Sendable for use across concurrency boundaries
public struct AudioEffect: Sendable, Identifiable, Equatable, Hashable {
    /// Unique identifier for this effect instance
    public let id: UUID

    /// Type of audio effect
    public let type: EffectType

    /// Effect-specific parameters
    public let parameters: [String: EffectParameterValue]

    /// Whether effect is currently enabled
    public let isEnabled: Bool

    /// Display name for user interfaces
    public let displayName: String

    /// When this effect was created
    public let createdAt: Date

    /// When this effect was last modified
    public let modifiedAt: Date

    /// Creates a new audio effect
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - type: Type of audio effect
    ///   - parameters: Effect-specific parameters
    ///   - isEnabled: Whether effect is active
    ///   - displayName: Custom display name (uses type default if nil)
    ///   - createdAt: Creation timestamp
    ///   - modifiedAt: Modification timestamp
    public init(
        id: UUID = UUID(),
        type: EffectType,
        parameters: [String: EffectParameterValue] = [:],
        isEnabled: Bool = true,
        displayName: String? = nil,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.parameters = parameters
        self.isEnabled = isEnabled
        self.displayName = displayName ?? type.defaultDisplayName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }

    /// Creates a copy with updated values
    /// - Parameters:
    ///   - parameters: Updated parameters
    ///   - isEnabled: Updated enabled state
    ///   - displayName: Updated display name
    /// - Returns: New effect instance with updated values
    public func updated(
        parameters: [String: EffectParameterValue]? = nil,
        isEnabled: Bool? = nil,
        displayName: String? = nil
    ) -> AudioEffect {
        AudioEffect(
            id: self.id,
            type: self.type,
            parameters: parameters ?? self.parameters,
            isEnabled: isEnabled ?? self.isEnabled,
            displayName: displayName ?? self.displayName,
            createdAt: self.createdAt,
            modifiedAt: Date() // Always update modification time
        )
    }

    /// Get a parameter value with type safety
    /// - Parameters:
    ///   - key: Parameter key
    ///   - type: Expected parameter type
    /// - Returns: Parameter value if exists and matches type
    public func parameter<T>(_ key: String, as type: T.Type) -> T? where T: Sendable {
        return parameters[key]?.value as? T
    }

    /// Set a parameter value with type safety
    /// - Parameters:
    ///   - key: Parameter key
    ///   - value: Parameter value
    /// - Returns: Updated effect with new parameter
    public func withParameter<T>(_ key: String, value: T) -> AudioEffect where T: Sendable {
        var newParameters = parameters
        newParameters[key] = EffectParameterValue(value)
        return updated(parameters: newParameters)
    }

    /// Validate that all required parameters are present for this effect type
    /// - Returns: Array of missing required parameter keys
    public var missingRequiredParameters: [String] {
        return type.requiredParameters.filter { !parameters.keys.contains($0) }
    }

    /// Whether this effect has all required parameters
    public var isValid: Bool {
        return missingRequiredParameters.isEmpty
    }
}

// MARK: - EffectType

/// Enumeration of supported audio effect types
/// This enum is Sendable for use across concurrency boundaries
public enum EffectType: Sendable, Equatable, Hashable {
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

    /// Delay/echo effect
    case delay

    /// High/low pass filter
    case filter

    /// Pitch shift effect
    case pitchShift

    /// Custom AVAudioUnit
    case custom(description: AudioComponentDescription)

    /// Default display name for effect type
    public var defaultDisplayName: String {
        switch self {
        case .timePitch: return "Time/Pitch"
        case .reverb: return "Reverb"
        case .equalizer: return "Equalizer"
        case .compressor: return "Compressor"
        case .distortion: return "Distortion"
        case .delay: return "Delay"
        case .filter: return "Filter"
        case .pitchShift: return "Pitch Shift"
        case .custom: return "Custom Effect"
        }
    }

    /// Required parameters for this effect type
    public var requiredParameters: [String] {
        switch self {
        case .timePitch:
            return [EffectParameterKeys.rate]
        case .reverb:
            return [EffectParameterKeys.wetDryMix]
        case .equalizer:
            return [EffectParameterKeys.bands]
        case .compressor:
            return [EffectParameterKeys.threshold, EffectParameterKeys.ratio]
        case .distortion:
            return [EffectParameterKeys.preGain]
        case .delay:
            return [EffectParameterKeys.delayTime, EffectParameterKeys.feedback]
        case .filter:
            return [EffectParameterKeys.cutoffFrequency]
        case .pitchShift:
            return [EffectParameterKeys.pitch]
        case .custom:
            return [] // Custom effects define their own parameters
        }
    }

    /// Default parameter values for this effect type
    public var defaultParameters: [String: EffectParameterValue] {
        switch self {
        case .timePitch:
            return [
                EffectParameterKeys.rate: EffectParameterValue(1.0),
                EffectParameterKeys.pitch: EffectParameterValue(0.0)
            ]
        case .reverb:
            return [
                EffectParameterKeys.wetDryMix: EffectParameterValue(20.0)
            ]
        case .equalizer:
            return [
                EffectParameterKeys.bands: EffectParameterValue([EQBand]()),
                EffectParameterKeys.globalGain: EffectParameterValue(0.0)
            ]
        case .compressor:
            return [
                EffectParameterKeys.threshold: EffectParameterValue(-20.0),
                EffectParameterKeys.ratio: EffectParameterValue(4.0),
                EffectParameterKeys.attack: EffectParameterValue(0.003),
                EffectParameterKeys.release: EffectParameterValue(0.1)
            ]
        case .distortion:
            return [
                EffectParameterKeys.preGain: EffectParameterValue(0.0),
                EffectParameterKeys.wetDryMix: EffectParameterValue(50.0)
            ]
        case .delay:
            return [
                EffectParameterKeys.delayTime: EffectParameterValue(0.3),
                EffectParameterKeys.feedback: EffectParameterValue(0.3),
                EffectParameterKeys.wetDryMix: EffectParameterValue(25.0)
            ]
        case .filter:
            return [
                EffectParameterKeys.cutoffFrequency: EffectParameterValue(1000.0),
                EffectParameterKeys.resonance: EffectParameterValue(1.0)
            ]
        case .pitchShift:
            return [
                EffectParameterKeys.pitch: EffectParameterValue(0.0)
            ]
        case .custom:
            return [:]
        }
    }

    /// AVAudioUnit type for this effect (if available)
    public var audioUnitType: OSType? {
        switch self {
        case .timePitch: return kAudioUnitSubType_AUiPodTimeOther
        case .reverb: return kAudioUnitSubType_Reverb2
        case .equalizer: return kAudioUnitSubType_ParametricEQ
        case .compressor: return kAudioUnitSubType_DynamicsProcessor
        case .distortion: return kAudioUnitSubType_Distortion
        case .delay: return kAudioUnitSubType_Delay
        case .filter: return kAudioUnitSubType_LowPassFilter
        case .pitchShift: return kAudioUnitSubType_NewTimePitch
        case .custom(let description): return description.componentSubType
        }
    }
}

// MARK: - EffectParameterValue

/// Type-safe wrapper for effect parameter values
/// This struct is Sendable for use across concurrency boundaries
public struct EffectParameterValue: Sendable, Equatable, Hashable {
    /// The wrapped value
    public let value: any Sendable

    /// Creates a new parameter value
    /// - Parameter value: The value to wrap
    public init<T: Sendable>(_ value: T) {
        self.value = value
    }

    /// Get the value as a specific type
    /// - Parameter type: Expected type
    /// - Returns: Value if it matches the type
    public func `as`<T>(_ type: T.Type) -> T? {
        return value as? T
    }
}

// MARK: - EffectParameterKeys

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

    // Distortion parameters
    public static let preGain = "preGain"     // Float: -40.0 to 40.0 dB

    // Delay parameters
    public static let delayTime = "delayTime" // Float: 0.0 to 2.0 seconds
    public static let feedback = "feedback"   // Float: 0.0 to 1.0

    // Filter parameters
    public static let cutoffFrequency = "cutoffFrequency" // Float: 20.0 to 20000.0 Hz
    public static let resonance = "resonance" // Float: 0.1 to 20.0
}

// MARK: - EQBand

/// Represents a single equalizer band
/// This struct is Sendable for use across concurrency boundaries
public struct EQBand: Sendable, Equatable, Hashable, Identifiable {
    /// Unique identifier
    public let id: UUID

    /// Center frequency in Hz
    public let frequency: Float

    /// Gain in dB (-96.0 to 24.0)
    public let gain: Float

    /// Bandwidth (0.05 to 5.0)
    public let bandwidth: Float

    /// Whether this band is enabled
    public let isEnabled: Bool

    /// Creates a new EQ band
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - frequency: Center frequency in Hz
    ///   - gain: Gain in dB
    ///   - bandwidth: Bandwidth value
    ///   - isEnabled: Whether band is active
    public init(
        id: UUID = UUID(),
        frequency: Float,
        gain: Float,
        bandwidth: Float = 1.0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.frequency = max(20.0, min(20000.0, frequency))
        self.gain = max(-96.0, min(24.0, gain))
        self.bandwidth = max(0.05, min(5.0, bandwidth))
        self.isEnabled = isEnabled
    }

    /// Creates a copy with updated values
    /// - Parameters:
    ///   - frequency: Updated frequency
    ///   - gain: Updated gain
    ///   - bandwidth: Updated bandwidth
    ///   - isEnabled: Updated enabled state
    /// - Returns: New EQ band with updated values
    public func updated(
        frequency: Float? = nil,
        gain: Float? = nil,
        bandwidth: Float? = nil,
        isEnabled: Bool? = nil
    ) -> EQBand {
        EQBand(
            id: self.id,
            frequency: frequency ?? self.frequency,
            gain: gain ?? self.gain,
            bandwidth: bandwidth ?? self.bandwidth,
            isEnabled: isEnabled ?? self.isEnabled
        )
    }
}

// MARK: - CustomStringConvertible

extension AudioEffect: CustomStringConvertible {
    public var description: String {
        let enabledText = isEnabled ? "enabled" : "disabled"
        return "\(displayName) (\(enabledText))"
    }
}

extension EffectType: CustomStringConvertible {
    public var description: String {
        return defaultDisplayName
    }
}

extension EQBand: CustomStringConvertible {
    public var description: String {
        let enabledText = isEnabled ? "" : " (disabled)"
        return String(format: "%.0f Hz: %.1f dB%@", frequency, gain, enabledText)
    }
}

// MARK: - Equatable/Hashable Implementation

extension EffectParameterValue {
    public static func == (lhs: EffectParameterValue, rhs: EffectParameterValue) -> Bool {
        // This is a simplified equality check - in practice, you might need more sophisticated comparison
        return String(describing: lhs.value) == String(describing: rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}

extension EffectType {
    public static func == (lhs: EffectType, rhs: EffectType) -> Bool {
        switch (lhs, rhs) {
        case (.timePitch, .timePitch), (.reverb, .reverb), (.equalizer, .equalizer),
             (.compressor, .compressor), (.distortion, .distortion), (.delay, .delay),
             (.filter, .filter), (.pitchShift, .pitchShift):
            return true
        case (.custom(let lhsDesc), .custom(let rhsDesc)):
            return lhsDesc.componentType == rhsDesc.componentType &&
                   lhsDesc.componentSubType == rhsDesc.componentSubType &&
                   lhsDesc.componentManufacturer == rhsDesc.componentManufacturer
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .timePitch: hasher.combine("timePitch")
        case .reverb: hasher.combine("reverb")
        case .equalizer: hasher.combine("equalizer")
        case .compressor: hasher.combine("compressor")
        case .distortion: hasher.combine("distortion")
        case .delay: hasher.combine("delay")
        case .filter: hasher.combine("filter")
        case .pitchShift: hasher.combine("pitchShift")
        case .custom(let desc):
            hasher.combine("custom")
            hasher.combine(desc.componentType)
            hasher.combine(desc.componentSubType)
            hasher.combine(desc.componentManufacturer)
        }
    }
}