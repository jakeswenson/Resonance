// AudioEngineAccessible.swift - Expert-level protocol for direct AVAudioEngine access
// Swift 6 Sendable compliant protocol providing advanced audio engine manipulation capabilities

import Foundation
import Combine
import AVFoundation

/// Expert-level protocol providing direct access to the underlying AVAudioEngine
///
/// AudioEngineAccessible extends AudioEffectable with low-level engine access for advanced users
/// who need direct manipulation of the audio processing chain. This protocol bypasses many safety
/// guarantees and should only be used by experienced audio developers.
///
/// **WARNING:** Direct engine manipulation can cause unpredictable behavior, audio glitches,
/// memory issues, and crashes. Use with extreme caution and thorough testing.
///
/// This protocol provides:
/// - Direct AVAudioEngine and AVAudioPlayerNode access
/// - Custom audio node insertion and management
/// - Real-time audio tap installation for analysis
/// - Advanced audio session configuration
/// - Engine state management and monitoring
/// - Processing format and configuration publishers
/// - Swift 6 Sendable compliance for concurrent usage
///
/// Usage example:
/// ```swift
/// let player = SomeAudioEngineAccessible()
///
/// // Install audio tap for real-time analysis
/// player.installTap(bufferSize: 1024, format: nil) { buffer, time in
///     // Analyze audio buffer data
///     analyzeAudioBuffer(buffer, at: time)
/// }
/// .sink { _ in print("Tap installed") }
/// .store(in: &cancellables)
///
/// // Insert custom processing node
/// let customReverb = AVAudioUnitReverb()
/// player.insertAudioNode(customReverb, at: .beforeOutput)
///     .sink { _ in print("Custom reverb inserted") }
///     .store(in: &cancellables)
/// ```
@MainActor
public protocol AudioEngineAccessible: AudioEffectable {

    // MARK: - Direct Engine Access

    /// Direct access to the underlying AVAudioEngine
    ///
    /// Provides read-only access to the audio engine for advanced manipulation.
    /// The engine may be nil if no audio is currently loaded or the engine is not initialized.
    ///
    /// **WARNING:** Direct modifications to this engine can cause:
    /// - Audio processing interruptions
    /// - Memory corruption and crashes
    /// - Inconsistent internal state
    /// - Unpredictable behavior
    ///
    /// Only access this property if you understand the implications and have extensive
    /// experience with AVAudioEngine internals.
    ///
    /// - Returns: The underlying AVAudioEngine or nil if not available
    var audioEngine: AVAudioEngine? { get }

    /// Access to the main player node in the engine
    ///
    /// Provides read-only access to the primary AVAudioPlayerNode used for playback.
    /// The player node may be nil if no audio is loaded or the engine is not initialized.
    ///
    /// **WARNING:** Direct manipulation of the player node can interfere with:
    /// - Playback timing and synchronization
    /// - Volume and rate control
    /// - Seek operations
    /// - Effect processing
    ///
    /// Use this property primarily for read-only operations like installing taps
    /// or querying node state.
    ///
    /// - Returns: The main AVAudioPlayerNode or nil if not available
    var playerNode: AVAudioPlayerNode? { get }

    // MARK: - Audio Tap Management

    /// Install a custom audio tap on the player node for real-time analysis
    ///
    /// Creates an audio tap that captures PCM audio data in real-time for analysis,
    /// visualization, or processing. The tap does not affect audio playback but
    /// provides access to the audio stream as it flows through the player node.
    ///
    /// **Performance Considerations:**
    /// - Tap blocks are called on a real-time audio thread
    /// - Keep processing minimal to avoid audio dropouts
    /// - Avoid allocations, locks, and complex operations in tap blocks
    /// - Use appropriate buffer sizes (powers of 2, typically 256-4096)
    ///
    /// **Thread Safety:**
    /// - Tap blocks execute on the audio render thread
    /// - Do not access UI elements or non-thread-safe APIs
    /// - Use atomic operations or thread-safe containers for data sharing
    ///
    /// - Parameters:
    ///   - bufferSize: Size of audio buffer for tap (must be power of 2)
    ///   - format: Audio format for tap data (nil uses player node's format)
    ///   - tapBlock: Block called with each audio buffer and timing information
    /// - Returns: Publisher that completes when tap is installed or fails with AudioError
    func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        tapBlock: @escaping AVAudioNodeTapBlock
    ) -> AnyPublisher<Void, AudioError>

    /// Remove audio tap from player node
    ///
    /// Removes any previously installed audio tap from the player node.
    /// This operation is safe to call even if no tap is currently installed.
    ///
    /// After removal:
    /// - Tap block will no longer be called
    /// - Audio processing overhead is reduced
    /// - Player node resources are freed
    ///
    /// - Returns: Publisher that completes when tap is removed or fails with AudioError
    func removeTap() -> AnyPublisher<Void, AudioError>

    // MARK: - Custom Node Management

    /// Insert a custom audio node into the processing chain
    ///
    /// Adds a custom AVAudioNode at the specified position in the audio processing
    /// chain. The node will process audio data in real-time according to its
    /// configuration and the position in the chain.
    ///
    /// **Supported Node Types:**
    /// - AVAudioUnit subclasses (reverb, delay, distortion, etc.)
    /// - Custom AVAudioNode implementations
    /// - AVAudioPlayerNode instances (advanced use cases)
    /// - Third-party audio unit nodes
    ///
    /// **Chain Position Behavior:**
    /// - `.afterPlayer`: Node processes audio immediately after the player
    /// - `.beforeOutput`: Node processes audio just before the output mixer
    /// - `.atIndex(n)`: Node is inserted at specific position in effect chain
    /// - `.replacingIndex(n)`: Node replaces existing node at position
    ///
    /// **Performance Impact:**
    /// - Each node adds processing overhead
    /// - Complex nodes may cause audio dropouts on older devices
    /// - Monitor CPU usage and latency when adding multiple nodes
    ///
    /// - Parameters:
    ///   - node: Custom AVAudioNode to insert into the processing chain
    ///   - position: Where to insert the node in the audio chain
    /// - Returns: Publisher that completes when node is inserted or fails with AudioError
    func insertAudioNode(
        _ node: AVAudioNode,
        at position: NodePosition
    ) -> AnyPublisher<Void, AudioError>

    /// Remove a custom audio node from the processing chain
    ///
    /// Removes the specified node from the audio processing chain and reconnects
    /// the chain to maintain audio flow. The node will no longer process audio
    /// after removal.
    ///
    /// **Removal Behavior:**
    /// - Node is disconnected from the audio graph
    /// - Audio chain is reconnected automatically
    /// - Node resources are released
    /// - Other nodes in the chain are unaffected
    ///
    /// If the node is not found in the current chain, the operation completes
    /// successfully without error.
    ///
    /// - Parameter node: AVAudioNode to remove from the processing chain
    /// - Returns: Publisher that completes when node is removed or fails with AudioError
    func removeAudioNode(_ node: AVAudioNode) -> AnyPublisher<Void, AudioError>

    // MARK: - Engine State Publishers

    /// Publisher that emits the current audio processing format
    ///
    /// Emits the AVAudioFormat currently being used for audio processing.
    /// This format represents the sample rate, channel count, and bit depth
    /// of audio data flowing through the engine.
    ///
    /// **Format Changes:**
    /// - Emits when audio is loaded with different characteristics
    /// - Updates when hardware configuration changes
    /// - Reflects real-time processing format (may differ from source format)
    /// - Initial state is nil for new instances
    ///
    /// **Usage:**
    /// - Configure custom nodes to match processing format
    /// - Adapt UI displays to show current audio characteristics
    /// - Monitor format changes for compatibility checks
    ///
    /// - Returns: Publisher that never fails and emits AVAudioFormat? values
    var processingFormat: AnyPublisher<AVAudioFormat?, Never> { get }

    /// Publisher that emits current engine configuration information
    ///
    /// Emits comprehensive information about the current state and configuration
    /// of the underlying audio engine. This includes sample rates, buffer sizes,
    /// channel configurations, and hardware-specific settings.
    ///
    /// **Configuration Updates:**
    /// - Emits when engine starts or stops
    /// - Updates when hardware configuration changes (e.g., headphone connection)
    /// - Reflects changes in buffer sizes or sample rates
    /// - Provides both engine and hardware characteristics
    ///
    /// **Usage:**
    /// - Monitor engine performance characteristics
    /// - Adapt processing to hardware capabilities
    /// - Display detailed audio information in debugging interfaces
    /// - Optimize node configurations based on current settings
    ///
    /// - Returns: Publisher that never fails and emits EngineConfiguration values
    var engineConfiguration: AnyPublisher<EngineConfiguration, Never> { get }

    // MARK: - Advanced Engine Control

    /// Manually start or stop the audio engine (advanced use only)
    ///
    /// Provides direct control over the audio engine's running state. This is
    /// an advanced operation that bypasses normal playback state management.
    ///
    /// **WARNING:** Manual engine control can cause:
    /// - Inconsistent playback state
    /// - Audio session conflicts
    /// - Resource allocation issues
    /// - Synchronization problems with other audio apps
    ///
    /// **Use Cases:**
    /// - Custom audio routing configurations
    /// - Performance optimization for specific scenarios
    /// - Advanced multi-engine setups
    /// - Debugging and testing scenarios
    ///
    /// **Engine State Behavior:**
    /// - `true`: Starts the engine and allocates audio resources
    /// - `false`: Stops the engine and releases audio resources
    /// - State changes may be asynchronous
    /// - Other audio apps may be affected
    ///
    /// - Parameter shouldStart: Whether to start (true) or stop (false) the engine
    /// - Returns: Publisher that completes when engine state changes or fails with AudioError
    func setEngineRunning(_ shouldStart: Bool) -> AnyPublisher<Void, AudioError>
}

// MARK: - Supporting Types

/// Enumeration of positions for inserting custom audio nodes
///
/// Defines where custom nodes can be inserted in the audio processing chain
/// to achieve different processing orders and effects.
public enum NodePosition: Sendable, Equatable, Hashable {
    /// Insert node after the player node, before any effects
    ///
    /// Nodes in this position process the raw audio data immediately after
    /// the player but before any built-in effects. This is ideal for:
    /// - Audio analysis and visualization
    /// - Pre-processing effects
    /// - Dynamic range processing
    /// - Custom format conversion
    case afterPlayer

    /// Insert node after all effects, before the final output mixer
    ///
    /// Nodes in this position process audio after all other effects have
    /// been applied. This is ideal for:
    /// - Master bus processing
    /// - Final limiting and compression
    /// - Output formatting
    /// - Recording taps
    case beforeOutput

    /// Insert node at specific index in the effect chain
    ///
    /// Inserts the node at the specified index within the effect chain.
    /// Existing nodes at and after this index are shifted to higher indices.
    /// This allows precise control over effect ordering.
    ///
    /// - Parameter index: Zero-based index where to insert the node
    case atIndex(Int)

    /// Replace existing node at specific index in the effect chain
    ///
    /// Replaces the existing node at the specified index with the new node.
    /// The replaced node is removed from the chain and deallocated.
    /// This allows for dynamic effect swapping during playback.
    ///
    /// - Parameter index: Zero-based index of the node to replace
    case replacingIndex(Int)

    /// Human-readable description of the position
    public var description: String {
        switch self {
        case .afterPlayer:
            return "After Player"
        case .beforeOutput:
            return "Before Output"
        case .atIndex(let index):
            return "At Index \(index)"
        case .replacingIndex(let index):
            return "Replacing Index \(index)"
        }
    }
}

/// Comprehensive audio engine configuration information
///
/// Contains detailed information about the current state and configuration
/// of the audio engine, including both software and hardware characteristics.
public struct EngineConfiguration: Sendable, Equatable, Hashable {
    /// Current sample rate of the audio engine in Hz
    ///
    /// The sample rate at which the engine processes audio data.
    /// Common values include 44100, 48000, 88200, 96000 Hz.
    public let sampleRate: Double

    /// Number of audio channels being processed
    ///
    /// The channel count for audio processing:
    /// - 1: Mono
    /// - 2: Stereo
    /// - 6: 5.1 Surround
    /// - 8: 7.1 Surround
    public let channelCount: UInt32

    /// Current audio format description
    ///
    /// Complete format specification including sample rate, channel count,
    /// bit depth, and channel layout information.
    public let format: AVAudioFormat

    /// Whether the audio engine is currently running
    ///
    /// Indicates if the engine is actively processing audio:
    /// - `true`: Engine is running and can process audio
    /// - `false`: Engine is stopped and not processing audio
    public let isRunning: Bool

    /// Current buffer size being used for audio processing
    ///
    /// The size of audio buffers in frames. Smaller buffers provide lower
    /// latency but require more CPU overhead. Common values range from
    /// 256 to 4096 frames.
    public let bufferSize: AVAudioFrameCount

    /// Hardware sample rate of the audio output device
    ///
    /// The native sample rate of the current audio hardware. This may
    /// differ from the engine's processing sample rate, requiring
    /// sample rate conversion.
    public let hardwareSampleRate: Double

    /// Hardware I/O buffer duration in seconds
    ///
    /// The time duration of hardware audio buffers. This affects overall
    /// system latency and is typically between 0.005 and 0.1 seconds.
    public let hardwareBufferDuration: TimeInterval

    /// Creates new engine configuration information
    ///
    /// - Parameters:
    ///   - sampleRate: Engine sample rate in Hz
    ///   - channelCount: Number of audio channels
    ///   - format: Complete audio format description
    ///   - isRunning: Whether engine is currently running
    ///   - bufferSize: Audio buffer size in frames
    ///   - hardwareSampleRate: Hardware sample rate in Hz
    ///   - hardwareBufferDuration: Hardware buffer duration in seconds
    public init(
        sampleRate: Double,
        channelCount: UInt32,
        format: AVAudioFormat,
        isRunning: Bool,
        bufferSize: AVAudioFrameCount,
        hardwareSampleRate: Double,
        hardwareBufferDuration: TimeInterval
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.format = format
        self.isRunning = isRunning
        self.bufferSize = bufferSize
        self.hardwareSampleRate = hardwareSampleRate
        self.hardwareBufferDuration = hardwareBufferDuration
    }

    /// Estimated processing latency in seconds
    ///
    /// Calculates the approximate latency introduced by the current
    /// configuration, including buffer delays and processing overhead.
    public var estimatedLatency: TimeInterval {
        let bufferLatency = Double(bufferSize) / sampleRate
        return bufferLatency + hardwareBufferDuration
    }

    /// Whether sample rate conversion is required
    ///
    /// Indicates if the engine's sample rate differs from the hardware
    /// sample rate, requiring real-time sample rate conversion.
    public var requiresSampleRateConversion: Bool {
        return abs(sampleRate - hardwareSampleRate) > 1.0
    }

    /// Formatted description of the current configuration
    public var description: String {
        let formatStr = String(format: "%.0f Hz, %d ch", sampleRate, channelCount)
        let bufferStr = String(format: "%d frames", bufferSize)
        let runningStr = isRunning ? "running" : "stopped"
        return "Engine: \(formatStr), \(bufferStr), \(runningStr)"
    }
}

// MARK: - Protocol Extensions

extension AudioEngineAccessible {

    /// Convenience method for installing tap with default buffer size
    ///
    /// Installs an audio tap using a standard buffer size of 1024 frames,
    /// which provides a good balance between latency and processing efficiency.
    ///
    /// - Parameter tapBlock: Block called with each audio buffer
    /// - Returns: Publisher that completes when tap is installed or fails with AudioError
    func installTap(tapBlock: @escaping AVAudioNodeTapBlock) -> AnyPublisher<Void, AudioError> {
        return installTap(bufferSize: 1024, format: nil, tapBlock: tapBlock)
    }

    /// Convenience method for checking if engine is available
    ///
    /// Determines whether the audio engine is available and ready for
    /// advanced operations. This is useful for enabling/disabling UI
    /// controls that depend on engine access.
    ///
    /// - Returns: True if engine is available, false otherwise
    var isEngineAvailable: Bool {
        return audioEngine != nil
    }

    /// Convenience method for checking if player node is available
    ///
    /// Determines whether the player node is available for tap installation
    /// or other advanced operations.
    ///
    /// - Returns: True if player node is available, false otherwise
    var isPlayerNodeAvailable: Bool {
        return playerNode != nil
    }

    /// Convenience method for getting current engine sample rate
    ///
    /// Retrieves the current sample rate from the processing format or
    /// returns a default value if no format is available.
    ///
    /// - Returns: Publisher that emits the current sample rate
    func currentSampleRate() -> AnyPublisher<Double, Never> {
        return processingFormat
            .map { format in
                return format?.sampleRate ?? 44100.0
            }
            .eraseToAnyPublisher()
    }

    /// Convenience method for monitoring engine running state
    ///
    /// Provides a boolean publisher that tracks whether the engine is
    /// currently running, derived from the engine configuration.
    ///
    /// - Returns: Publisher that emits engine running state
    func isEngineRunning() -> AnyPublisher<Bool, Never> {
        return engineConfiguration
            .map { config in
                return config.isRunning
            }
            .eraseToAnyPublisher()
    }

    /// Convenience method for monitoring format compatibility
    ///
    /// Checks if the current processing format is compatible with a
    /// specific sample rate and channel count requirement.
    ///
    /// - Parameters:
    ///   - sampleRate: Required sample rate
    ///   - channelCount: Required channel count
    /// - Returns: Publisher that emits compatibility status
    func isFormatCompatible(
        sampleRate: Double,
        channelCount: UInt32
    ) -> AnyPublisher<Bool, Never> {
        return processingFormat
            .map { format in
                guard let format = format else { return false }
                return abs(format.sampleRate - sampleRate) < 1.0 &&
                       format.channelCount == channelCount
            }
            .eraseToAnyPublisher()
    }
}

// MARK: - CustomStringConvertible

extension NodePosition: CustomStringConvertible {}

extension EngineConfiguration: CustomStringConvertible {}

// MARK: - Documentation Notes

/*
 DESIGN PRINCIPLES:

 1. EXPERT-LEVEL ACCESS WITH SAFETY WARNINGS
    - Clear warnings about potential risks and side effects
    - Comprehensive documentation of dangerous operations
    - Guidance on proper usage patterns and limitations
    - Emphasis on testing and validation requirements

 2. COMPREHENSIVE ENGINE EXPOSURE
    - Direct access to AVAudioEngine and AVAudioPlayerNode
    - Real-time audio tap capabilities for analysis
    - Custom node insertion and management
    - Engine state monitoring and control
    - Hardware configuration information

 3. PERFORMANCE-CONSCIOUS DESIGN
    - Efficient publisher-based monitoring
    - Minimal overhead for engine access
    - Guidance on real-time operation constraints
    - Buffer size and latency considerations

 4. SWIFT 6 SENDABLE COMPLIANCE
    - All types maintain Sendable conformance
    - Thread-safe audio node operations
    - MainActor isolation for UI thread safety
    - Concurrent engine access support

 5. EXTENSIBLE ARCHITECTURE
    - Protocol-based design for multiple implementations
    - Supporting types for complex operations
    - Convenience methods for common use cases
    - Integration with existing AudioEffectable hierarchy

 USAGE PATTERNS:

 Audio Analysis and Visualization:
 ```swift
 // Install tap for real-time audio analysis
 player.installTap(bufferSize: 1024, format: nil) { buffer, time in
     // Perform FFT analysis on audio buffer
     let fftResult = performFFT(on: buffer)

     // Update UI with spectrum data (on main thread)
     DispatchQueue.main.async {
         updateSpectrumDisplay(fftResult)
     }
 }
 .sink { _ in print("Audio analysis tap installed") }
 .store(in: &cancellables)
 ```

 Custom Effect Chain:
 ```swift
 // Create custom effect chain
 let customReverb = AVAudioUnitReverb()
 let customDelay = AVAudioUnitDelay()

 // Insert effects in specific order
 player.insertAudioNode(customReverb, at: .afterPlayer)
     .flatMap { _ in
         player.insertAudioNode(customDelay, at: .beforeOutput)
     }
     .sink { _ in print("Custom effect chain created") }
     .store(in: &cancellables)

 // Configure effects in real-time
 customReverb.wetDryMix = 40.0
 customDelay.delayTime = 0.3
 ```

 Engine State Monitoring:
 ```swift
 // Monitor engine configuration changes
 player.engineConfiguration
     .sink { config in
         print("Engine: \(config.description)")
         print("Estimated latency: \(config.estimatedLatency * 1000) ms")

         if config.requiresSampleRateConversion {
             print("Warning: Sample rate conversion active")
         }
     }
     .store(in: &cancellables)

 // React to format changes
 player.processingFormat
     .compactMap { $0 }
     .sink { format in
         configureCustomNodes(for: format)
         updateUIForFormat(format)
     }
     .store(in: &cancellables)
 ```

 Advanced Engine Control:
 ```swift
 // Manually control engine for custom scenarios
 player.setEngineRunning(false)
     .delay(for: .seconds(1), scheduler: DispatchQueue.main)
     .flatMap { _ in
         // Reconfigure audio session
         configureCustomAudioSession()
         return player.setEngineRunning(true)
     }
     .sink(
         receiveCompletion: { completion in
             if case .failure(let error) = completion {
                 print("Engine restart failed: \(error)")
             }
         },
         receiveValue: { _ in
             print("Engine restarted successfully")
         }
     )
     .store(in: &cancellables)
 ```

 IMPLEMENTATION GUIDELINES:

 - Engine access should be read-only except for documented operations
 - All audio tap blocks must execute efficiently on the audio thread
 - Custom nodes should be properly configured before insertion
 - Engine state changes should be coordinated with playback state
 - Error handling must be comprehensive for all advanced operations
 - Resource cleanup should be automatic when possible
 - Thread safety must be maintained across all engine operations
 - Performance impact should be minimized and documented
 - Hardware compatibility should be validated before use
 - Memory management must prevent leaks and retain cycles

 TESTING RECOMMENDATIONS:

 - Test on multiple hardware configurations
 - Validate performance under different load conditions
 - Verify thread safety with concurrent operations
 - Test error handling and recovery scenarios
 - Validate memory usage and leak detection
 - Test with various audio formats and sample rates
 - Verify compatibility with system audio changes
 - Test tap installation and removal cycles
 - Validate custom node insertion and removal
 - Test engine state transitions and error conditions
 */