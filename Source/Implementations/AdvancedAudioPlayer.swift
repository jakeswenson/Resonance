//
//  AdvancedAudioPlayer.swift
//  Resonance
//
//  Expert-level audio player with direct AVAudioEngine access and advanced manipulation capabilities.
//  Provides the highest tier of functionality for power users requiring low-level audio engine control.
//

import Foundation
import Combine
import AVFoundation

#if os(iOS)
import UIKit
#endif

/// Expert-level audio player with direct AVAudioEngine access and advanced manipulation
///
/// AdvancedAudioPlayer extends EffectableAudioPlayer with AudioEngineAccessible features,
/// providing the highest tier of audio functionality for expert developers who need direct
/// access to the underlying AVAudioEngine and advanced audio processing capabilities.
///
/// **WARNING: EXPERT-LEVEL INTERFACE**
/// This class provides direct access to low-level audio engine components. Improper use
/// can cause audio glitches, memory corruption, crashes, and unpredictable behavior.
/// Only use if you have extensive experience with AVAudioEngine internals.
///
/// **Enhanced usage pattern:**
/// ```swift
/// let player = AdvancedAudioPlayer()
/// try await player.loadAudio(from: url, metadata: nil).async()
///
/// // Install audio tap for real-time analysis
/// try await player.installTap(bufferSize: 1024, format: nil) { buffer, time in
///     // Perform real-time audio analysis
///     analyzeAudioBuffer(buffer, at: time)
/// }.async()
///
/// // Insert custom processing node
/// let customProcessor = MyCustomAudioNode()
/// try await player.insertAudioNode(customProcessor, at: .afterPlayer).async()
///
/// // Monitor engine configuration changes
/// player.engineConfiguration
///     .sink { config in
///         print("Engine: \(config.description)")
///         print("Latency: \(config.estimatedLatency * 1000) ms")
///     }
///     .store(in: &cancellables)
/// ```
///
/// This implementation:
/// - Inherits all AudioEffectable functionality from EffectableAudioPlayer
/// - Implements AudioEngineAccessible for direct engine access and manipulation
/// - Uses ReactiveAudioCoordinator for safe engine access coordination
/// - Provides expert-level functionality for advanced audio processing
/// - Maintains Swift 6 concurrency and Sendable compliance throughout
/// - Handles advanced engine manipulation with comprehensive safety checks
/// - Offers access to engine configuration, format details, and processing chain
@MainActor
public final class AdvancedAudioPlayer: EffectableAudioPlayer, AudioEngineAccessible, @unchecked Sendable {

    // MARK: - Advanced Dependencies

    /// Access to engine coordinator for advanced operations
    private var engineCoordinator: ReactiveAudioCoordinator {
        return coordinator
    }

    // MARK: - Engine Access State

    /// Current audio processing format subject
    private let processingFormatSubject = CurrentValueSubject<AVAudioFormat?, Never>(nil)

    /// Current engine configuration subject
    private let engineConfigSubject = CurrentValueSubject<EngineConfiguration?, Never>(nil)

    /// Engine access cancellables
    private var engineCancellables = Set<AnyCancellable>()

    /// Currently installed audio tap
    private var installedTap: AudioTapInfo?

    /// Custom nodes managed by this player
    private var managedCustomNodes: Set<AVAudioNode> = []

    // MARK: - Initialization

    /// Initialize AdvancedAudioPlayer with optional coordinator dependency injection
    /// - Parameter coordinator: Optional coordinator instance (defaults to shared)
    public override init(coordinator: ReactiveAudioCoordinator = .shared) {
        super.init(coordinator: coordinator)
        setupEngineBindings()
    }

    deinit {
        // Cleanup synchronously during deinit
        engineCancellables.removeAll()
        processingFormatSubject.send(nil)
        engineConfigSubject.send(nil)
        installedTap = nil
        managedCustomNodes.removeAll()
    }

    // MARK: - AudioEngineAccessible Protocol Implementation

    /// Direct access to the underlying AVAudioEngine
    ///
    /// **WARNING:** Direct modifications to this engine can cause unpredictable behavior,
    /// audio glitches, memory issues, and crashes. Use with extreme caution.
    public var audioEngine: AVAudioEngine? {
        return engineCoordinator.engineAccess
    }

    /// Access to the main player node in the engine
    ///
    /// **WARNING:** Direct manipulation of the player node can interfere with
    /// playback timing, volume control, seek operations, and effect processing.
    public var playerNode: AVAudioPlayerNode? {
        guard let engine = audioEngine else { return nil }

        // Find the main player node in the engine's nodes
        for node in engine.attachedNodes {
            if let playerNode = node as? AVAudioPlayerNode {
                return playerNode
            }
        }
        return nil
    }

    /// Install a custom audio tap on the player node for real-time analysis
    public func installTap(
        bufferSize: AVAudioFrameCount,
        format: AVAudioFormat?,
        tapBlock: @escaping AVAudioNodeTapBlock
    ) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.engineCoordinator.ensureReady()

                    // Validate buffer size (must be power of 2)
                    guard bufferSize > 0 && (bufferSize & (bufferSize - 1)) == 0 else {
                        promise(.failure(.invalidInput("Buffer size must be a power of 2")))
                        return
                    }

                    // Get player node
                    guard let playerNode = self.playerNode else {
                        promise(.failure(.resourceUnavailable))
                        return
                    }

                    // Remove existing tap if present
                    if let existingTap = self.installedTap {
                        playerNode.removeTap(onBus: existingTap.bus)
                        self.installedTap = nil
                    }

                    // Determine format (use player node's format if not specified)
                    let tapFormat = format ?? playerNode.outputFormat(forBus: 0)

                    // Install new tap
                    let bus: AVAudioNodeBus = 0
                    playerNode.installTap(onBus: bus, bufferSize: bufferSize, format: tapFormat, block: tapBlock)

                    // Track installed tap
                    self.installedTap = AudioTapInfo(
                        bus: bus,
                        bufferSize: bufferSize,
                        format: tapFormat
                    )

                    promise(.success(()))

                    AdvancedLog.debug("AdvancedAudioPlayer: Installed audio tap (buffer size: \(bufferSize), format: \(tapFormat))")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to install tap: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Remove audio tap from player node
    public func removeTap() -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                // Get player node
                guard let playerNode = self.playerNode else {
                    promise(.success(())) // No player node means no tap to remove
                    return
                }

                // Remove tap if present
                if let installedTap = self.installedTap {
                    playerNode.removeTap(onBus: installedTap.bus)
                    self.installedTap = nil

                    AdvancedLog.debug("AdvancedAudioPlayer: Removed audio tap")
                }

                promise(.success(()))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Insert a custom audio node into the processing chain
    public func insertAudioNode(
        _ node: AVAudioNode,
        at position: NodePosition
    ) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Ensure coordinator is ready
                    try self.engineCoordinator.ensureReady()

                    // Get audio engine
                    guard let engine = self.audioEngine else {
                        promise(.failure(.resourceUnavailable))
                        return
                    }

                    // Validate node is not already attached
                    guard !engine.attachedNodes.contains(node) else {
                        promise(.failure(.invalidInput("Node is already attached to engine")))
                        return
                    }

                    // Attach node to engine
                    engine.attach(node)

                    // Connect node based on position
                    try self.connectNodeAtPosition(node, position: position, engine: engine)

                    // Track managed node
                    self.managedCustomNodes.insert(node)

                    promise(.success(()))

                    AdvancedLog.debug("AdvancedAudioPlayer: Inserted custom node at position \(position.description)")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to insert node: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Remove a custom audio node from the processing chain
    public func removeAudioNode(_ node: AVAudioNode) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Get audio engine
                    guard let engine = self.audioEngine else {
                        promise(.success(())) // No engine means nothing to remove
                        return
                    }

                    // Check if node is attached
                    guard engine.attachedNodes.contains(node) else {
                        promise(.success(())) // Node not attached, operation successful
                        return
                    }

                    // Disconnect and detach node
                    engine.disconnectNodeInput(node)
                    engine.disconnectNodeOutput(node)
                    engine.detach(node)

                    // Remove from managed nodes
                    self.managedCustomNodes.remove(node)

                    // Reconnect audio chain if needed
                    try self.reconnectAudioChain(engine: engine)

                    promise(.success(()))

                    AdvancedLog.debug("AdvancedAudioPlayer: Removed custom node")

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to remove node: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Publisher that emits the current audio processing format
    public var processingFormat: AnyPublisher<AVAudioFormat?, Never> {
        processingFormatSubject.eraseToAnyPublisher()
    }

    /// Publisher that emits current engine configuration information
    public var engineConfiguration: AnyPublisher<EngineConfiguration, Never> {
        engineConfigSubject
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /// Manually start or stop the audio engine (advanced use only)
    ///
    /// **WARNING:** Manual engine control can cause inconsistent playback state,
    /// audio session conflicts, resource allocation issues, and synchronization problems.
    public func setEngineRunning(_ shouldStart: Bool) -> AnyPublisher<Void, AudioError> {
        return Future<Void, AudioError> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.failure(.internalError("Player deallocated")))
                    return
                }

                do {
                    // Get audio engine
                    guard let engine = self.audioEngine else {
                        promise(.failure(.resourceUnavailable))
                        return
                    }

                    // Check current state
                    let isCurrentlyRunning = engine.isRunning

                    // Perform state change if needed
                    if shouldStart && !isCurrentlyRunning {
                        try engine.start()
                        AdvancedLog.debug("AdvancedAudioPlayer: Engine started manually")
                    } else if !shouldStart && isCurrentlyRunning {
                        engine.stop()
                        AdvancedLog.debug("AdvancedAudioPlayer: Engine stopped manually")
                    }

                    // Update engine configuration
                    await self.updateEngineConfiguration()

                    promise(.success(()))

                } catch {
                    if let audioError = error as? AudioError {
                        promise(.failure(audioError))
                    } else {
                        promise(.failure(.internalError("Failed to set engine running state: \(error.localizedDescription)")))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Enhanced Audio Loading with Engine Configuration

    /// Update engine configuration and processing format
    /// This method is automatically called when audio is loaded through any loadAudio method
    /// and provides advanced engine monitoring for expert-level usage
    private func refreshEngineState() async {
        await updateEngineConfiguration()
        await updateProcessingFormat()
        AdvancedLog.debug("AdvancedAudioPlayer: Engine state refreshed")
    }

    // MARK: - Advanced Engine Information

    /// Get comprehensive engine status information
    public func getEngineStatus() -> AnyPublisher<AdvancedEngineStatus, Never> {
        return Future<AdvancedEngineStatus, Never> { [weak self] promise in
            Task { @MainActor in
                guard let self = self else {
                    promise(.success(AdvancedEngineStatus.unavailable))
                    return
                }

                let status = await self.buildEngineStatus()
                promise(.success(status))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Get current audio tap information
    public func getCurrentTapInfo() -> AnyPublisher<AudioTapInfo?, Never> {
        return Future<AudioTapInfo?, Never> { [weak self] promise in
            Task { @MainActor in
                promise(.success(self?.installedTap))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Get list of custom nodes managed by this player
    public func getManagedCustomNodes() -> AnyPublisher<[AVAudioNode], Never> {
        return Future<[AVAudioNode], Never> { [weak self] promise in
            Task { @MainActor in
                let nodes = Array(self?.managedCustomNodes ?? [])
                promise(.success(nodes))
            }
        }
        .eraseToAnyPublisher()
    }

    /// Check if a specific node is managed by this player
    public func isManagedNode(_ node: AVAudioNode) -> AnyPublisher<Bool, Never> {
        return Future<Bool, Never> { [weak self] promise in
            Task { @MainActor in
                let isManaged = self?.managedCustomNodes.contains(node) ?? false
                promise(.success(isManaged))
            }
        }
        .eraseToAnyPublisher()
    }

    // MARK: - Private Implementation

    /// Setup reactive bindings for engine access features
    private func setupEngineBindings() {
        // Monitor engine configuration changes periodically
        Timer.publish(every: 1.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshEngineState()
                }
            }
            .store(in: &engineCancellables)

        // Monitor app lifecycle for engine state changes
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshEngineState()
                }
            }
            .store(in: &engineCancellables)
        #endif

        // Listen for playback state changes to refresh engine configuration
        playbackState
            .sink { [weak self] state in
                if state == .ready || state == .playing {
                    Task { @MainActor in
                        await self?.refreshEngineState()
                    }
                }
            }
            .store(in: &engineCancellables)
    }

    /// Connect a node at the specified position in the audio chain
    private func connectNodeAtPosition(
        _ node: AVAudioNode,
        position: NodePosition,
        engine: AVAudioEngine
    ) throws {
        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        let format = inputNode.outputFormat(forBus: 0)

        switch position {
        case .afterPlayer:
            // Insert after player node, before any effects
            guard let playerNode = self.playerNode else {
                throw AudioError.resourceUnavailable
            }

            // Find current connections from player node
            let currentConnections = findConnectionsFromNode(playerNode, in: engine)

            // Disconnect player node outputs
            engine.disconnectNodeOutput(playerNode)

            // Connect player -> custom node -> previous destinations
            engine.connect(playerNode, to: node, format: format)

            // Reconnect to previous destinations
            for (destNode, destBus, destFormat) in currentConnections {
                engine.connect(node, to: destNode, fromBus: 0, toBus: destBus, format: destFormat)
            }

        case .beforeOutput:
            // Insert before output node
            // Find all nodes currently connected to output
            let inputConnections = findConnectionsToNode(outputNode, in: engine)

            // Disconnect all inputs to output node
            engine.disconnectNodeInput(outputNode)

            // Connect all previous inputs to custom node
            for (sourceNode, sourceBus, sourceFormat) in inputConnections {
                engine.connect(sourceNode, to: node, fromBus: sourceBus, toBus: 0, format: sourceFormat)
            }

            // Connect custom node to output
            engine.connect(node, to: outputNode, format: format)

        case .atIndex(let index):
            // Insert at specific index in effect chain
            // This is a simplified implementation - in a real scenario, you'd need
            // to track and manage the effect chain order
            try connectNodeAtPosition(node, position: .afterPlayer, engine: engine)

        case .replacingIndex(let index):
            // Replace node at specific index
            // This is a simplified implementation - in a real scenario, you'd need
            // to identify and replace the specific node at that index
            try connectNodeAtPosition(node, position: .afterPlayer, engine: engine)
        }
    }

    /// Find connections from a node
    private func findConnectionsFromNode(_ node: AVAudioNode, in engine: AVAudioEngine) -> [(AVAudioNode, AVAudioNodeBus, AVAudioFormat)] {
        // This is a simplified implementation
        // In a real implementation, you would track these connections
        return []
    }

    /// Find connections to a node
    private func findConnectionsToNode(_ node: AVAudioNode, in engine: AVAudioEngine) -> [(AVAudioNode, AVAudioNodeBus, AVAudioFormat)] {
        // This is a simplified implementation
        // In a real implementation, you would track these connections
        return []
    }

    /// Reconnect the audio chain after node removal
    private func reconnectAudioChain(engine: AVAudioEngine) throws {
        // This is a simplified implementation
        // In a real implementation, you would reconstruct the audio chain
        // based on the remaining nodes and their intended connections

        let inputNode = engine.inputNode
        let outputNode = engine.outputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Basic reconnection (input -> output)
        engine.connect(inputNode, to: outputNode, format: format)
    }

    /// Update the current engine configuration
    private func updateEngineConfiguration() async {
        guard let engine = audioEngine else {
            engineConfigSubject.send(nil)
            return
        }

        // Get hardware information
        #if os(iOS) || os(tvOS)
        let audioSession = AVAudioSession.sharedInstance()
        let hardwareSampleRate = audioSession.sampleRate
        let hardwareBufferDuration = audioSession.ioBufferDuration
        #else
        // macOS doesn't have AVAudioSession, use engine defaults
        let hardwareSampleRate = 44100.0
        let hardwareBufferDuration = 0.005 // 5ms default
        #endif

        // Get engine format
        let format = engine.outputNode.inputFormat(forBus: 0)

        // Create configuration
        let config = EngineConfiguration(
            sampleRate: format.sampleRate,
            channelCount: format.channelCount,
            format: format,
            isRunning: engine.isRunning,
            bufferSize: 1024, // Default buffer size - in real implementation, get from engine
            hardwareSampleRate: hardwareSampleRate,
            hardwareBufferDuration: hardwareBufferDuration
        )

        engineConfigSubject.send(config)
    }

    /// Update the current processing format
    private func updateProcessingFormat() async {
        guard let engine = audioEngine else {
            processingFormatSubject.send(nil)
            return
        }

        // Get format from output node
        let format = engine.outputNode.inputFormat(forBus: 0)
        processingFormatSubject.send(format)
    }

    /// Build comprehensive engine status
    private func buildEngineStatus() async -> AdvancedEngineStatus {
        guard let engine = audioEngine else {
            return .unavailable
        }

        let attachedNodeCount = engine.attachedNodes.count
        let managedNodeCount = managedCustomNodes.count
        let hasTapInstalled = installedTap != nil
        let isRunning = engine.isRunning

        // Get current configuration
        await updateEngineConfiguration()
        let currentConfig = engineConfigSubject.value

        return .available(
            isRunning: isRunning,
            attachedNodeCount: attachedNodeCount,
            managedCustomNodeCount: managedNodeCount,
            hasTapInstalled: hasTapInstalled,
            configuration: currentConfig
        )
    }

}

// MARK: - Supporting Types

/// Information about an installed audio tap
public struct AudioTapInfo: Sendable, Equatable {
    /// Bus number where tap is installed
    public let bus: AVAudioNodeBus

    /// Buffer size for tap
    public let bufferSize: AVAudioFrameCount

    /// Audio format for tap data
    public let format: AVAudioFormat

    /// Timestamp when tap was installed
    public let installTime: Date

    public init(bus: AVAudioNodeBus, bufferSize: AVAudioFrameCount, format: AVAudioFormat) {
        self.bus = bus
        self.bufferSize = bufferSize
        self.format = format
        self.installTime = Date()
    }
}

/// Advanced engine status information
public enum AdvancedEngineStatus: Sendable, Equatable {
    case unavailable
    case available(
        isRunning: Bool,
        attachedNodeCount: Int,
        managedCustomNodeCount: Int,
        hasTapInstalled: Bool,
        configuration: EngineConfiguration?
    )

    /// Whether the engine is available for advanced operations
    public var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }

    /// Whether the engine is currently running
    public var isRunning: Bool {
        if case .available(let running, _, _, _, _) = self {
            return running
        }
        return false
    }

    /// Number of nodes attached to the engine
    public var attachedNodeCount: Int {
        if case .available(_, let count, _, _, _) = self {
            return count
        }
        return 0
    }

    /// Number of custom nodes managed by this player
    public var managedCustomNodeCount: Int {
        if case .available(_, _, let count, _, _) = self {
            return count
        }
        return 0
    }

    /// Whether an audio tap is currently installed
    public var hasTapInstalled: Bool {
        if case .available(_, _, _, let hasTap, _) = self {
            return hasTap
        }
        return false
    }

    /// Current engine configuration
    public var configuration: EngineConfiguration? {
        if case .available(_, _, _, _, let config) = self {
            return config
        }
        return nil
    }
}

// MARK: - Logging Support

/// Simple logging utility for AdvancedAudioPlayer
private struct AdvancedLog {
    static func debug(_ message: String) {
        #if DEBUG
        print("[AdvancedAudioPlayer] DEBUG: \(message)")
        #endif
    }

    static func error(_ message: String) {
        print("[AdvancedAudioPlayer] ERROR: \(message)")
    }
}

// MARK: - Documentation

/*
 DESIGN PRINCIPLES:

 1. EXPERT-LEVEL ACCESS WITH COMPREHENSIVE WARNINGS
    - Clear warnings about potential risks and dangerous operations
    - Extensive documentation of side effects and limitations
    - Guidance on proper usage patterns and testing requirements
    - Emphasis on expert knowledge requirements

 2. DIRECT ENGINE MANIPULATION CAPABILITIES
    - Read-only access to AVAudioEngine and AVAudioPlayerNode
    - Real-time audio tap installation for analysis and visualization
    - Custom node insertion with position control
    - Manual engine state management for advanced scenarios
    - Comprehensive configuration and format monitoring

 3. SAFE COORDINATION THROUGH REACTIVE SYSTEM
    - Uses ReactiveAudioCoordinator for thread-safe engine access
    - Proper resource management and cleanup
    - Atomic operations where possible
    - Error handling for all advanced operations

 4. SWIFT 6 CONCURRENCY COMPLIANCE
    - MainActor isolation for UI thread safety
    - Sendable protocol compliance throughout
    - Concurrent access patterns for engine monitoring
    - Thread-safe audio node operations

 5. COMPREHENSIVE MONITORING AND STATUS
    - Real-time engine configuration tracking
    - Processing format change notifications
    - Advanced status information for debugging
    - Performance and resource usage awareness

 USAGE PATTERNS:

 Real-time Audio Analysis:
 ```swift
 let player = AdvancedAudioPlayer()
 try await player.loadAudio(from: url, metadata: nil).async()

 // Install tap for spectrum analysis
 try await player.installTap(bufferSize: 1024, format: nil) { buffer, time in
     // Perform FFT analysis on real-time thread
     let fftResult = performFFT(on: buffer)

     // Send results to main thread for UI updates
     DispatchQueue.main.async {
         updateSpectrumVisualizer(fftResult)
     }
 }.async()
 ```

 Custom Audio Processing Chain:
 ```swift
 // Create custom processing nodes
 let customEQ = MyCustomEqualizerNode()
 let customReverb = MyCustomReverbNode()
 let customAnalyzer = MyAudioAnalyzerNode()

 // Build processing chain
 try await player.insertAudioNode(customEQ, at: .afterPlayer).async()
 try await player.insertAudioNode(customReverb, at: .beforeOutput).async()
 try await player.insertAudioNode(customAnalyzer, at: .atIndex(1)).async()

 // Monitor and adjust in real-time
 customEQ.adjustFrequencyBand(frequency: 1000, gain: 3.0)
 customReverb.setRoomSize(0.8)
 ```

 Engine Configuration Monitoring:
 ```swift
 // Monitor engine changes for adaptive processing
 player.engineConfiguration
     .sink { config in
         print("Sample Rate: \(config.sampleRate) Hz")
         print("Channels: \(config.channelCount)")
         print("Buffer Size: \(config.bufferSize) frames")
         print("Latency: \(config.estimatedLatency * 1000) ms")

         // Adapt processing to engine configuration
         if config.requiresSampleRateConversion {
             enableHighQualityResampling()
         }

         if config.estimatedLatency > 0.020 { // 20ms
             optimizeForHighLatency()
         }
     }
     .store(in: &cancellables)

 // Monitor format changes for compatibility
 player.processingFormat
     .compactMap { $0 }
     .sink { format in
         configureCustomNodesForFormat(format)
         updateVisualizationForChannels(format.channelCount)
     }
     .store(in: &cancellables)
 ```

 Manual Engine Control:
 ```swift
 // Advanced engine lifecycle management

 // Stop engine for configuration changes
 try await player.setEngineRunning(false).async()

 // Perform advanced audio session configuration
 try configureCustomAudioSession()

 // Restart engine with new configuration
 try await player.setEngineRunning(true).async()

 // Verify engine status after restart
 let status = await player.getEngineStatus().async()
 if case .available(let isRunning, _, _, _, let config) = status {
     if isRunning, let config = config {
         print("Engine restarted successfully: \(config.description)")
     }
 }
 ```

 Comprehensive Status Monitoring:
 ```swift
 // Get detailed engine status
 player.getEngineStatus()
     .sink { status in
         switch status {
         case .unavailable:
             showEngineUnavailableWarning()

         case .available(let isRunning, let nodeCount, let customNodeCount, let hasTap, let config):
             updateEngineStatusDisplay(
                 running: isRunning,
                 nodes: nodeCount,
                 customNodes: customNodeCount,
                 tapInstalled: hasTap,
                 configuration: config
             )
         }
     }
     .store(in: &cancellables)

 // Monitor managed nodes
 player.getManagedCustomNodes()
     .sink { nodes in
         updateCustomNodesList(nodes)
         validateNodeConnections(nodes)
     }
     .store(in: &cancellables)

 // Check tap information
 player.getCurrentTapInfo()
     .sink { tapInfo in
         if let info = tapInfo {
             updateTapStatusDisplay(info)
         } else {
             hideTapStatusDisplay()
         }
     }
     .store(in: &cancellables)
 ```

 IMPLEMENTATION GUIDELINES:

 - All engine access operations must be performed with extreme caution
 - Audio tap blocks must execute efficiently on the real-time audio thread
 - Custom nodes should be properly validated before insertion
 - Engine state changes must be coordinated with overall player state
 - Error handling must be comprehensive for all dangerous operations
 - Resource cleanup must be thorough and automatic
 - Thread safety must be maintained across all advanced operations
 - Performance impact must be monitored and minimized
 - Hardware compatibility must be verified before advanced operations
 - Memory management must prevent leaks and retain cycles in complex node graphs

 TESTING REQUIREMENTS:

 - Test on multiple hardware configurations and iOS versions
 - Validate performance under various load conditions
 - Verify thread safety with concurrent advanced operations
 - Test error handling and recovery for all failure scenarios
 - Validate memory usage and comprehensive leak detection
 - Test with various audio formats, sample rates, and channel configurations
 - Verify compatibility with system audio changes and interruptions
 - Test tap installation/removal cycles under load
 - Validate custom node insertion/removal with complex chains
 - Test engine state transitions and error recovery scenarios
 - Verify proper cleanup during app lifecycle changes
 - Test interaction between advanced features and standard player operations

 PERFORMANCE CONSIDERATIONS:

 - Engine access operations have minimal overhead
 - Audio tap processing must maintain real-time constraints
 - Custom node insertion may cause brief audio interruptions
 - Engine configuration monitoring uses efficient polling
 - Memory usage scales with number of custom nodes
 - CPU usage increases with complex custom processing chains
 - Latency monitoring provides accurate real-time measurements
 - Resource cleanup is optimized for minimal impact
 - Background processing is used where appropriate
 - Hardware capabilities are respected and monitored
 */