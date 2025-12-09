// AudioEngineAccessible.swift - Expert Protocol for Direct AVAudioEngine Access
// Contract Test: Must verify engine access and custom node integration

import Foundation
import Combine
import AVFoundation

/// Expert-level protocol providing direct access to the underlying AVAudioEngine
/// WARNING: This protocol bypasses safety guarantees - use with caution
/// Only adopt this protocol if you need direct engine manipulation
public protocol AudioEngineAccessible: AudioEffectable {

    /// Direct access to the underlying AVAudioEngine
    /// - Warning: Modifications to this engine can cause unpredictable behavior
    /// - Note: Engine may be nil if no audio is currently loaded
    var audioEngine: AVAudioEngine? { get }

    /// Access to the main player node in the engine
    /// - Warning: Direct manipulation can interfere with playback
    var playerNode: AVAudioPlayerNode? { get }

    /// Install a custom audio tap on the player node
    /// - Parameter bufferSize: Size of audio buffer for tap
    /// - Parameter format: Audio format for tap (nil uses player format)
    /// - Parameter tapBlock: Block called with each audio buffer
    /// - Returns: Publisher that completes when tap is installed or fails
    func installTap(bufferSize: AVAudioFrameCount,
                   format: AVAudioFormat?,
                   tapBlock: @escaping AVAudioNodeTapBlock) -> AnyPublisher<Void, AudioError>

    /// Remove audio tap from player node
    /// - Returns: Publisher that completes when tap is removed
    func removeTap() -> AnyPublisher<Void, AudioError>

    /// Insert a custom audio node into the processing chain
    /// - Parameter node: Custom AVAudioNode to insert
    /// - Parameter position: Where to insert in the chain
    /// - Returns: Publisher that completes when node is inserted or fails
    func insertAudioNode(_ node: AVAudioNode,
                        at position: NodePosition) -> AnyPublisher<Void, AudioError>

    /// Remove a custom audio node from the processing chain
    /// - Parameter node: AVAudioNode to remove
    /// - Returns: Publisher that completes when node is removed or fails
    func removeAudioNode(_ node: AVAudioNode) -> AnyPublisher<Void, AudioError>

    /// Get the current audio format being processed
    var processingFormat: AnyPublisher<AVAudioFormat?, Never> { get }

    /// Get the current engine configuration
    var engineConfiguration: AnyPublisher<EngineConfiguration, Never> { get }

    /// Manually start/stop the audio engine (advanced use only)
    /// - Parameter shouldStart: Whether to start or stop the engine
    /// - Returns: Publisher that completes when engine state changes
    func setEngineRunning(_ shouldStart: Bool) -> AnyPublisher<Void, AudioError>
}

// MARK: - Supporting Types

public enum NodePosition {
    /// Insert after the player node, before effects
    case afterPlayer

    /// Insert after all effects, before output
    case beforeOutput

    /// Insert at specific index in effect chain
    case atIndex(Int)

    /// Replace existing node at index
    case replacingIndex(Int)
}

public struct EngineConfiguration {
    /// Sample rate of the engine
    public let sampleRate: Double

    /// Number of audio channels
    public let channelCount: UInt32

    /// Audio format description
    public let format: AVAudioFormat

    /// Whether engine is currently running
    public let isRunning: Bool

    /// Buffer size being used
    public let bufferSize: AVAudioFrameCount

    /// Hardware sample rate
    public let hardwareSampleRate: Double

    /// Hardware I/O buffer duration
    public let hardwareBufferDuration: TimeInterval

    public init(sampleRate: Double,
                channelCount: UInt32,
                format: AVAudioFormat,
                isRunning: Bool,
                bufferSize: AVAudioFrameCount,
                hardwareSampleRate: Double,
                hardwareBufferDuration: TimeInterval) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.format = format
        self.isRunning = isRunning
        self.bufferSize = bufferSize
        self.hardwareSampleRate = hardwareSampleRate
        self.hardwareBufferDuration = hardwareBufferDuration
    }
}