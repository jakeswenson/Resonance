//
//  AudioPlayerFactory.swift
//  Resonance
//
//  Factory for creating protocol-based audio player implementations with dependency injection
//  Provides convenient methods for instantiating players with ReactiveAudioCoordinator integration
//

import Foundation
import Combine
import AVFoundation

/// Factory for creating protocol-based audio player implementations
///
/// AudioPlayerFactory provides convenient methods for creating audio player instances
/// that conform to the various audio protocols (AudioPlayable, AudioConfigurable, etc.).
///
/// The factory handles:
/// - Dependency injection with ReactiveAudioCoordinator
/// - Proper initialization of engines and components
/// - Configuration of reactive updates and actor integration
/// - Default configurations for common use cases
///
/// Usage examples:
/// ```swift
/// // Basic player
/// let basicPlayer = AudioPlayerFactory.createBasicPlayer()
///
/// // Configurable player with coordinator
/// let coordinator = ReactiveAudioCoordinator.shared
/// let configurablePlayer = AudioPlayerFactory.createConfigurablePlayer(coordinator: coordinator)
///
/// // Downloadable player with custom configuration
/// let downloadablePlayer = AudioPlayerFactory.createDownloadablePlayer(
///     coordinator: coordinator,
///     allowsCellular: false
/// )
/// ```
@MainActor
public final class AudioPlayerFactory {

    // MARK: - Private Dependencies

    /// Shared coordinator instance for default configurations
    private static var sharedCoordinator: ReactiveAudioCoordinator? {
        return ReactiveAudioCoordinator.shared
    }

    // MARK: - Basic Audio Player Creation

    /// Creates a basic audio player with minimal dependencies
    ///
    /// Provides basic playback functionality through the AudioPlayable protocol.
    /// Suitable for simple audio playback without advanced features.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Basic player configuration
    /// - Returns: A new BasicAudioPlayer instance
    public static func createBasicPlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: BasicPlayerConfiguration = .default
    ) -> BasicAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        return BasicAudioPlayer(
            coordinator: coord,
            configuration: configuration
        )
    }

    // MARK: - Configurable Audio Player Creation

    /// Creates a configurable audio player with enhanced features
    ///
    /// Provides configurable playback through the AudioConfigurable protocol.
    /// Includes volume control, playback rate, and metadata management.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Configurable player configuration
    /// - Returns: A new ConfigurableAudioPlayer instance
    public static func createConfigurablePlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: ConfigurablePlayerConfiguration = .default
    ) -> ConfigurableAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        return ConfigurableAudioPlayer(
            coordinator: coord,
            configuration: configuration
        )
    }

    // MARK: - Downloadable Audio Player Creation

    /// Creates a downloadable audio player with offline capabilities
    ///
    /// Provides download management through the AudioDownloadable protocol.
    /// Includes caching, offline playback, and download progress tracking.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Downloadable player configuration
    ///   - allowsCellular: Whether cellular downloads are permitted
    /// - Returns: A new DownloadableAudioPlayer instance
    public static func createDownloadablePlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: DownloadablePlayerConfiguration = .default,
        allowsCellular: Bool = true
    ) -> DownloadableAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        var config = configuration
        config.allowsCellularDownloads = allowsCellular

        return DownloadableAudioPlayer(
            coordinator: coord,
            configuration: config
        )
    }

    // MARK: - Effect-Enhanced Audio Player Creation

    /// Creates an audio player with real-time effects capabilities
    ///
    /// Provides effects processing through the AudioEffectable protocol.
    /// Includes reverb, EQ, pitch shifting, and custom audio unit support.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Effects player configuration
    ///   - initialEffects: Effects to add during initialization
    /// - Returns: A new EffectableAudioPlayer instance
    public static func createEffectablePlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: EffectablePlayerConfiguration = .default,
        initialEffects: [AudioEffect] = []
    ) -> EffectableAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        var config = configuration
        config.initialEffects = initialEffects

        return EffectableAudioPlayer(
            coordinator: coord,
            configuration: config
        )
    }

    // MARK: - Queue-Managed Audio Player Creation

    /// Creates an audio player with queue management capabilities
    ///
    /// Provides queue management through the AudioQueueManageable protocol.
    /// Includes playlist support, autoplay, and queue manipulation.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Queue player configuration
    ///   - initialQueue: Initial queue items
    /// - Returns: A new QueueableAudioPlayer instance
    public static func createQueueablePlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: QueueablePlayerConfiguration = .default,
        initialQueue: [URL] = []
    ) -> QueueableAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        var config = configuration
        config.initialQueue = initialQueue

        return QueueableAudioPlayer(
            coordinator: coord,
            configuration: config
        )
    }

    // MARK: - Engine-Accessible Audio Player Creation

    /// Creates an audio player with direct engine access
    ///
    /// Provides low-level engine access through the AudioEngineAccessible protocol.
    /// Suitable for advanced users who need direct AVAudioEngine manipulation.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Engine-accessible player configuration
    /// - Returns: A new EngineAccessibleAudioPlayer instance
    public static func createEngineAccessiblePlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: EngineAccessiblePlayerConfiguration = .default
    ) -> EngineAccessibleAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        return EngineAccessibleAudioPlayer(
            coordinator: coord,
            configuration: configuration
        )
    }

    // MARK: - Full-Featured Audio Player Creation

    /// Creates a full-featured audio player with all capabilities
    ///
    /// Combines all protocols for maximum functionality.
    /// Includes all features: playback, configuration, downloads, effects, queue, and engine access.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Full-featured player configuration
    /// - Returns: A new FullFeaturedAudioPlayer instance
    public static func createFullFeaturedPlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: FullFeaturedPlayerConfiguration = .default
    ) -> FullFeaturedAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        return FullFeaturedAudioPlayer(
            coordinator: coord,
            configuration: configuration
        )
    }

    // MARK: - Custom Configuration Factory Methods

    /// Creates a player with custom engine configuration
    ///
    /// Allows customization of the underlying audio engine setup.
    /// Useful for specialized audio processing requirements.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - engineType: Type of audio engine to use
    ///   - bitrate: Audio bitrate for streaming content
    ///   - audioFormat: Custom audio format specification
    /// - Returns: A configured audio player instance
    public static func createWithCustomEngine<T: AudioPlayable>(
        playerType: T.Type,
        coordinator: ReactiveAudioCoordinator? = nil,
        engineType: AudioEngineType = .stream,
        bitrate: SAPlayerBitrate = .high,
        audioFormat: AVAudioFormat? = nil
    ) -> T {
        let coord = coordinator ?? sharedCoordinator

        // This is a placeholder - in a real implementation, this would use
        // reflection or a registry pattern to create the appropriate player type
        fatalError("Custom engine creation not yet implemented - requires player type registration system")
    }

    // MARK: - Legacy Integration Factory Methods

    /// Creates a player that bridges to legacy SAPlayer functionality
    ///
    /// Provides compatibility with existing SAPlayer-based code while
    /// offering protocol-based interfaces for new features.
    ///
    /// - Parameters:
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - legacyDelegate: Legacy delegate for backward compatibility
    /// - Returns: A legacy-compatible audio player
    public static func createLegacyCompatiblePlayer(
        coordinator: ReactiveAudioCoordinator? = nil,
        legacyDelegate: AudioEngineDelegate? = nil
    ) -> LegacyCompatibleAudioPlayer {
        let coord = coordinator ?? sharedCoordinator
        return LegacyCompatibleAudioPlayer(
            coordinator: coord,
            legacyDelegate: legacyDelegate
        )
    }

    // MARK: - Batch Creation Methods

    /// Creates multiple players of the same type with shared configuration
    ///
    /// Useful for applications that need multiple concurrent audio players
    /// with consistent configuration.
    ///
    /// - Parameters:
    ///   - count: Number of players to create
    ///   - coordinator: Optional coordinator for actor system integration
    ///   - configuration: Shared configuration for all players
    /// - Returns: Array of configured audio players
    public static func createMultipleBasicPlayers(
        count: Int,
        coordinator: ReactiveAudioCoordinator? = nil,
        configuration: BasicPlayerConfiguration = .default
    ) -> [BasicAudioPlayer] {
        let coord = coordinator ?? sharedCoordinator
        return (0..<count).map { _ in
            BasicAudioPlayer(coordinator: coord, configuration: configuration)
        }
    }

    // MARK: - Configuration Validation

    /// Validates a player configuration before creation
    ///
    /// Checks that the configuration is valid and all dependencies are available.
    /// Throws an error if the configuration is invalid.
    ///
    /// - Parameter configuration: Configuration to validate
    /// - Throws: AudioError if configuration is invalid
    public static func validateConfiguration<T: PlayerConfiguration>(_ configuration: T) throws {
        // Validate basic requirements
        guard configuration.isValid else {
            throw AudioError.invalidConfiguration("Player configuration is invalid")
        }

        // Check coordinator availability if required
        if configuration.requiresCoordinator && sharedCoordinator == nil {
            throw AudioError.internalError("ReactiveAudioCoordinator is required but not available")
        }

        // Validate audio session requirements
        if configuration.requiresAudioSession {
            #if os(iOS) || os(tvOS)
            // Check if audio session can be configured
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [])
            } catch {
                throw AudioError.internalError("Cannot configure audio session: \(error.localizedDescription)")
            }
            #endif
        }
    }
}

// MARK: - Supporting Types

/// Types of audio engines available
public enum AudioEngineType: Sendable {
    case stream      // For remote streaming content
    case disk        // For local file playback
    case hybrid      // Supports both streaming and local playback
}

/// Extended AudioError cases for factory operations
extension AudioError {
    /// Configuration validation failed
    static func invalidConfiguration(_ message: String) -> AudioError {
        return .internalError("Invalid configuration: \(message)")
    }
}

// MARK: - Configuration Protocols

/// Base protocol for all player configurations
public protocol PlayerConfiguration: Sendable {
    /// Whether this configuration is valid
    var isValid: Bool { get }

    /// Whether this configuration requires a coordinator
    var requiresCoordinator: Bool { get }

    /// Whether this configuration requires an audio session
    var requiresAudioSession: Bool { get }
}

/// Basic player configuration
public struct BasicPlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public let enableLogging: Bool

    public var isValid: Bool {
        return bufferSize > 0
    }

    public var requiresCoordinator: Bool { return false }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = BasicPlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        enableLogging: false
    )

    public init(audioFormat: AVAudioFormat?, bufferSize: UInt32, enableLogging: Bool) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.enableLogging = enableLogging
    }
}

/// Configurable player configuration
public struct ConfigurablePlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public let defaultVolume: Float
    public let defaultRate: Float
    public let enableMetadata: Bool
    public let enableBufferStatusTracking: Bool

    public var isValid: Bool {
        return bufferSize > 0 &&
               defaultVolume >= 0.0 && defaultVolume <= 1.0 &&
               defaultRate >= 0.5 && defaultRate <= 4.0
    }

    public var requiresCoordinator: Bool { return true }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = ConfigurablePlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        defaultVolume: 1.0,
        defaultRate: 1.0,
        enableMetadata: true,
        enableBufferStatusTracking: true
    )

    public init(
        audioFormat: AVAudioFormat?,
        bufferSize: UInt32,
        defaultVolume: Float,
        defaultRate: Float,
        enableMetadata: Bool,
        enableBufferStatusTracking: Bool
    ) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.defaultVolume = defaultVolume
        self.defaultRate = defaultRate
        self.enableMetadata = enableMetadata
        self.enableBufferStatusTracking = enableBufferStatusTracking
    }
}

/// Downloadable player configuration
public struct DownloadablePlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public let downloadDirectory: FileManager.SearchPathDirectory
    public var allowsCellularDownloads: Bool
    public let maxConcurrentDownloads: Int
    public let downloadTimeout: TimeInterval

    public var isValid: Bool {
        return bufferSize > 0 &&
               maxConcurrentDownloads > 0 &&
               downloadTimeout > 0
    }

    public var requiresCoordinator: Bool { return true }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = DownloadablePlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        downloadDirectory: .downloadsDirectory,
        allowsCellularDownloads: true,
        maxConcurrentDownloads: 3,
        downloadTimeout: 60.0
    )

    public init(
        audioFormat: AVAudioFormat?,
        bufferSize: UInt32,
        downloadDirectory: FileManager.SearchPathDirectory,
        allowsCellularDownloads: Bool,
        maxConcurrentDownloads: Int,
        downloadTimeout: TimeInterval
    ) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.downloadDirectory = downloadDirectory
        self.allowsCellularDownloads = allowsCellularDownloads
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.downloadTimeout = downloadTimeout
    }
}

/// Effects player configuration
public struct EffectablePlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public var initialEffects: [AudioEffect]
    public let maxEffects: Int
    public let enableRealTimeProcessing: Bool

    public var isValid: Bool {
        return bufferSize > 0 && maxEffects > 0
    }

    public var requiresCoordinator: Bool { return true }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = EffectablePlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        initialEffects: [],
        maxEffects: 10,
        enableRealTimeProcessing: true
    )

    public init(
        audioFormat: AVAudioFormat?,
        bufferSize: UInt32,
        initialEffects: [AudioEffect],
        maxEffects: Int,
        enableRealTimeProcessing: Bool
    ) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.initialEffects = initialEffects
        self.maxEffects = maxEffects
        self.enableRealTimeProcessing = enableRealTimeProcessing
    }
}

/// Queue player configuration
public struct QueueablePlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public var initialQueue: [URL]
    public let maxQueueSize: Int
    public let enableAutoplay: Bool
    public let enableShuffle: Bool
    public let enableRepeat: Bool

    public var isValid: Bool {
        return bufferSize > 0 && maxQueueSize > 0
    }

    public var requiresCoordinator: Bool { return true }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = QueueablePlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        initialQueue: [],
        maxQueueSize: 1000,
        enableAutoplay: true,
        enableShuffle: false,
        enableRepeat: false
    )

    public init(
        audioFormat: AVAudioFormat?,
        bufferSize: UInt32,
        initialQueue: [URL],
        maxQueueSize: Int,
        enableAutoplay: Bool,
        enableShuffle: Bool,
        enableRepeat: Bool
    ) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.initialQueue = initialQueue
        self.maxQueueSize = maxQueueSize
        self.enableAutoplay = enableAutoplay
        self.enableShuffle = enableShuffle
        self.enableRepeat = enableRepeat
    }
}

/// Engine-accessible player configuration
public struct EngineAccessiblePlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public let allowDirectEngineAccess: Bool
    public let enableEngineMonitoring: Bool

    public var isValid: Bool {
        return bufferSize > 0
    }

    public var requiresCoordinator: Bool { return true }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = EngineAccessiblePlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        allowDirectEngineAccess: false,
        enableEngineMonitoring: true
    )

    public init(
        audioFormat: AVAudioFormat?,
        bufferSize: UInt32,
        allowDirectEngineAccess: Bool,
        enableEngineMonitoring: Bool
    ) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.allowDirectEngineAccess = allowDirectEngineAccess
        self.enableEngineMonitoring = enableEngineMonitoring
    }
}

/// Full-featured player configuration
public struct FullFeaturedPlayerConfiguration: PlayerConfiguration {
    public let audioFormat: AVAudioFormat?
    public let bufferSize: UInt32
    public let defaultVolume: Float
    public let defaultRate: Float
    public let downloadDirectory: FileManager.SearchPathDirectory
    public let allowsCellularDownloads: Bool
    public let maxConcurrentDownloads: Int
    public let initialEffects: [AudioEffect]
    public let maxEffects: Int
    public let initialQueue: [URL]
    public let maxQueueSize: Int
    public let enableAutoplay: Bool
    public let allowDirectEngineAccess: Bool

    public var isValid: Bool {
        return bufferSize > 0 &&
               defaultVolume >= 0.0 && defaultVolume <= 1.0 &&
               defaultRate >= 0.5 && defaultRate <= 4.0 &&
               maxConcurrentDownloads > 0 &&
               maxEffects > 0 &&
               maxQueueSize > 0
    }

    public var requiresCoordinator: Bool { return true }
    public var requiresAudioSession: Bool { return true }

    public static let `default` = FullFeaturedPlayerConfiguration(
        audioFormat: nil,
        bufferSize: 4096,
        defaultVolume: 1.0,
        defaultRate: 1.0,
        downloadDirectory: .downloadsDirectory,
        allowsCellularDownloads: true,
        maxConcurrentDownloads: 3,
        initialEffects: [],
        maxEffects: 10,
        initialQueue: [],
        maxQueueSize: 1000,
        enableAutoplay: true,
        allowDirectEngineAccess: false
    )

    public init(
        audioFormat: AVAudioFormat?,
        bufferSize: UInt32,
        defaultVolume: Float,
        defaultRate: Float,
        downloadDirectory: FileManager.SearchPathDirectory,
        allowsCellularDownloads: Bool,
        maxConcurrentDownloads: Int,
        initialEffects: [AudioEffect],
        maxEffects: Int,
        initialQueue: [URL],
        maxQueueSize: Int,
        enableAutoplay: Bool,
        allowDirectEngineAccess: Bool
    ) {
        self.audioFormat = audioFormat
        self.bufferSize = bufferSize
        self.defaultVolume = defaultVolume
        self.defaultRate = defaultRate
        self.downloadDirectory = downloadDirectory
        self.allowsCellularDownloads = allowsCellularDownloads
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.initialEffects = initialEffects
        self.maxEffects = maxEffects
        self.initialQueue = initialQueue
        self.maxQueueSize = maxQueueSize
        self.enableAutoplay = enableAutoplay
        self.allowDirectEngineAccess = allowDirectEngineAccess
    }
}

// MARK: - Player Type Implementations

// Note: The actual player implementations are now defined in Resonance.swift
// and their respective implementation files.
// Player types are now implemented in their respective files

// Mock implementations for compilation
public struct MockBasicAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: BasicPlayerConfiguration) {}
}
public struct MockConfigurableAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: ConfigurablePlayerConfiguration) {}
}
public struct MockDownloadableAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: DownloadablePlayerConfiguration) {}
}
public struct MockEffectableAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: EffectablePlayerConfiguration) {}
}
public struct MockQueueableAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: QueueablePlayerConfiguration) {}
}
public struct MockEngineAccessibleAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: EngineAccessiblePlayerConfiguration) {}
}
public struct MockFullFeaturedAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, configuration: FullFeaturedPlayerConfiguration) {}
}
public struct MockLegacyCompatibleAudioPlayer {
    init(coordinator: ReactiveAudioCoordinator?, legacyDelegate: AudioEngineDelegate?) {}
}