@preconcurrency import Combine
import AVFoundation
import Foundation

/// Central reactive hub for all audio system updates
/// Integrates with the modern protocol-based architecture and Swift 6 actors
/// Provides backward compatibility while adding support for new reactive features
@available(iOS 13.0, macOS 11.0, tvOS 13.0, *)
public struct AudioUpdates: Sendable {

  // MARK: - Legacy Publishers (Backward Compatibility)

  private let _playingStatus = CurrentValueSubject<SAPlayingStatus, Never>(.buffering)
  private let _elapsedTime = CurrentValueSubject<TimeInterval, Never>(-1)
  private let _duration = CurrentValueSubject<TimeInterval, Never>(-1)
  private let _streamingBuffer = CurrentValueSubject<SAAudioAvailabilityRange?, Never>(nil)
  private let _audioDownloading = CurrentValueSubject<Double, Never>(0)
  private let _streamingDownloadProgress = CurrentValueSubject<(url: URL, progress: Double)?, Never>(nil)
  private let _audioQueue = CurrentValueSubject<URL?, Never>(nil)

  /// Current playback status (legacy)
  public var playingStatus: AnyPublisher<SAPlayingStatus, Never> { _playingStatus.eraseToAnyPublisher() }

  /// Current elapsed playback time (legacy)
  public var elapsedTime: AnyPublisher<TimeInterval, Never> { _elapsedTime.eraseToAnyPublisher() }

  /// Total audio duration (legacy)
  public var duration: AnyPublisher<TimeInterval, Never> { _duration.eraseToAnyPublisher() }

  /// Streaming buffer availability range (legacy)
  public var streamingBuffer: AnyPublisher<SAAudioAvailabilityRange?, Never> { _streamingBuffer.eraseToAnyPublisher() }

  /// Download progress percentage (legacy)
  public var audioDownloading: AnyPublisher<Double, Never> { _audioDownloading.eraseToAnyPublisher() }

  /// Streaming download progress with URL tracking (legacy)
  public var streamingDownloadProgress: AnyPublisher<(url: URL, progress: Double)?, Never> { _streamingDownloadProgress.eraseToAnyPublisher() }

  /// Current audio queue URL (legacy)
  public var audioQueue: AnyPublisher<URL?, Never> { _audioQueue.eraseToAnyPublisher() }

  // MARK: - Modern Protocol Publishers (New Architecture)

  private let _activeSession = CurrentValueSubject<AudioSession?, Never>(nil)
  private let _sessionState = PassthroughSubject<AudioSessionState, Never>()
  private let _interruptions = PassthroughSubject<AudioInterruption, Never>()
  private let _routeChanges = PassthroughSubject<AudioRouteChange, Never>()
  private let _sessionActivation = CurrentValueSubject<Bool, Never>(false)

  /// Current active audio session
  public var activeSession: AnyPublisher<AudioSession?, Never> { _activeSession.eraseToAnyPublisher() }

  /// Internal method to update active session - only for ReactiveAudioCoordinator
  internal func updateActiveSession(_ session: AudioSession?) {
    _activeSession.send(session)
  }

  /// Audio session state changes (activation, interruptions, route changes)
  public var sessionState: AnyPublisher<AudioSessionState, Never> { _sessionState.eraseToAnyPublisher() }

  /// Audio interruption events (calls, headphone disconnect, etc.)
  public var interruptions: AnyPublisher<AudioInterruption, Never> { _interruptions.eraseToAnyPublisher() }

  /// Audio route changes (bluetooth, headphones, speakers)
  public var routeChanges: AnyPublisher<AudioRouteChange, Never> { _routeChanges.eraseToAnyPublisher() }

  /// Session activation state
  public var sessionActivation: AnyPublisher<Bool, Never> { _sessionActivation.eraseToAnyPublisher() }

  // MARK: - Download System Publishers

  private let _downloadProgress = CurrentValueSubject<[URL: DownloadProgress], Never>([:])
  private let _completedDownloads = CurrentValueSubject<[DownloadInfo], Never>([])
  private let _downloadStateChanges = PassthroughSubject<DownloadProgress, Never>()
  private let _networkStatus = CurrentValueSubject<NetworkStatus, Never>(.unknown)

  /// Individual download progress updates by URL
  public var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> { _downloadProgress.eraseToAnyPublisher() }

  /// Completed downloads information
  public var completedDownloads: AnyPublisher<[DownloadInfo], Never> { _completedDownloads.eraseToAnyPublisher() }

  /// Download state changes (started, completed, failed, cancelled)
  public var downloadStateChanges: AnyPublisher<DownloadProgress, Never> { _downloadStateChanges.eraseToAnyPublisher() }

  /// Network connectivity status for downloads
  public var networkStatus: AnyPublisher<NetworkStatus, Never> { _networkStatus.eraseToAnyPublisher() }

  // MARK: - Effects System Publishers

  private let _activeEffects = CurrentValueSubject<[AudioEffect], Never>([])
  private let _effectUpdates = PassthroughSubject<EffectUpdate, Never>()
  private let _effectChainChanges = PassthroughSubject<EffectChainUpdate, Never>()
  private let _processingLatency = CurrentValueSubject<TimeInterval?, Never>(nil)

  /// Current effects chain state
  public var activeEffects: AnyPublisher<[AudioEffect], Never> { _activeEffects.eraseToAnyPublisher() }

  /// Effect parameter updates in real-time
  public var effectUpdates: AnyPublisher<EffectUpdate, Never> { _effectUpdates.eraseToAnyPublisher() }

  /// Effect chain modifications (add, remove, reorder)
  public var effectChainChanges: AnyPublisher<EffectChainUpdate, Never> { _effectChainChanges.eraseToAnyPublisher() }

  /// Audio processing latency monitoring
  public var processingLatency: AnyPublisher<TimeInterval?, Never> { _processingLatency.eraseToAnyPublisher() }

  // MARK: - Queue Management Publishers

  private let _queueState = CurrentValueSubject<QueueState, Never>(.empty)
  private let _queueChanges = PassthroughSubject<QueueOperation, Never>()
  private let _autoplayEvents = PassthroughSubject<AutoplayEvent, Never>()

  /// Audio queue state and contents
  public var queueState: AnyPublisher<QueueState, Never> { _queueState.eraseToAnyPublisher() }

  /// Queue modifications (add, remove, reorder)
  public var queueChanges: AnyPublisher<QueueOperation, Never> { _queueChanges.eraseToAnyPublisher() }

  /// Automatic queue progression events
  public var autoplayEvents: AnyPublisher<AutoplayEvent, Never> { _autoplayEvents.eraseToAnyPublisher() }

  // MARK: - Enhanced Playback Publishers

  private let _detailedPlaybackState = CurrentValueSubject<DetailedPlaybackState, Never>(.idle)
  private let _precisePosition = CurrentValueSubject<TimeInterval, Never>(0)
  private let _audioQuality = CurrentValueSubject<AudioQualityMetrics?, Never>(nil)
  private let _bufferingEvents = PassthroughSubject<BufferingEvent, Never>()

  /// Detailed playback state with context
  public var detailedPlaybackState: AnyPublisher<DetailedPlaybackState, Never> { _detailedPlaybackState.eraseToAnyPublisher() }

  /// Playback position with high precision
  public var precisePosition: AnyPublisher<TimeInterval, Never> { _precisePosition.eraseToAnyPublisher() }

  /// Audio quality metrics
  public var audioQuality: AnyPublisher<AudioQualityMetrics?, Never> { _audioQuality.eraseToAnyPublisher() }

  /// Buffering events and progress
  public var bufferingEvents: AnyPublisher<BufferingEvent, Never> { _bufferingEvents.eraseToAnyPublisher() }

  // MARK: - System Publishers

  private let _errorEvents = PassthroughSubject<AudioSystemError, Never>()
  private let _performanceMetrics = CurrentValueSubject<PerformanceMetrics?, Never>(nil)
  private let _memoryUsage = CurrentValueSubject<MemoryUsage?, Never>(nil)

  /// Error events from all subsystems
  public var errorEvents: AnyPublisher<AudioSystemError, Never> { _errorEvents.eraseToAnyPublisher() }

  /// Performance metrics
  public var performanceMetrics: AnyPublisher<PerformanceMetrics?, Never> { _performanceMetrics.eraseToAnyPublisher() }

  /// Memory usage tracking
  public var memoryUsage: AnyPublisher<MemoryUsage?, Never> { _memoryUsage.eraseToAnyPublisher() }

  // MARK: - Internal State

  /// Cancellables for actor integrations
  private var cancellables = Set<AnyCancellable>()

  // MARK: - Initialization

  public init() {
    // AudioUpdates is now a pure data structure for reactive publishers
    // Protocol implementations will bind to these publishers directly
  }

  // MARK: - Internal Update Methods
  // These methods are internal to allow the audio system to update publishers

  /// Update playing status (internal use only)
  internal func updatePlayingStatus(_ status: SAPlayingStatus) {
    _playingStatus.send(status)
  }

  /// Update elapsed time (internal use only)
  internal func updateElapsedTime(_ time: TimeInterval) {
    _elapsedTime.send(time)
  }

  /// Update duration (internal use only)
  internal func updateDuration(_ duration: TimeInterval) {
    _duration.send(duration)
  }

  /// Update streaming buffer (internal use only)
  internal func updateStreamingBuffer(_ buffer: SAAudioAvailabilityRange?) {
    _streamingBuffer.send(buffer)
  }

  /// Update download progress (internal use only)
  internal func updateAudioDownloading(_ progress: Double) {
    _audioDownloading.send(progress)
  }

  /// Update streaming download progress (internal use only)
  internal func updateStreamingDownloadProgress(_ progress: (url: URL, progress: Double)?) {
    _streamingDownloadProgress.send(progress)
  }

  /// Update audio queue (internal use only)
  internal func updateAudioQueue(_ url: URL?) {
    _audioQueue.send(url)
  }
}

// MARK: - Supporting Types

/// Network connectivity status for download management
public enum NetworkStatus: Sendable, Equatable {
  case unknown
  case notReachable
  case reachableViaWiFi
  case reachableViaCellular
}

/// Effect update event
public struct EffectUpdate: Sendable, Equatable {
  public let effectId: UUID
  public let parameterKey: String
  public let oldValue: EffectParameterValue?
  public let newValue: EffectParameterValue
  public let timestamp: Date

  public init(effectId: UUID, parameterKey: String, oldValue: EffectParameterValue?, newValue: EffectParameterValue) {
    self.effectId = effectId
    self.parameterKey = parameterKey
    self.oldValue = oldValue
    self.newValue = newValue
    self.timestamp = Date()
  }
}

/// Effect chain update event
public enum EffectChainUpdate: Sendable, Equatable {
  case effectAdded(AudioEffect)
  case effectRemoved(UUID)
  case effectMoved(UUID, from: Int, to: Int)
  case chainReset
  case effectEnabled(UUID, Bool)
}

/// Queue state information
public enum QueueState: Sendable, Equatable {
  case empty
  case single(AudioSession)
  case multiple(current: AudioSession, queue: [AudioSession])

  public var currentSession: AudioSession? {
    switch self {
    case .empty: return nil
    case .single(let session): return session
    case .multiple(let current, _): return current
    }
  }

  public var queueCount: Int {
    switch self {
    case .empty: return 0
    case .single: return 1
    case .multiple(_, let queue): return 1 + queue.count
    }
  }
}

/// Queue operation event
public enum QueueOperation: Sendable, Equatable {
  case added(AudioSession, at: Int?)
  case removed(UUID)
  case moved(UUID, from: Int, to: Int)
  case cleared
  case next
  case previous
}

/// Autoplay event
public enum AutoplayEvent: Sendable, Equatable {
  case queueAdvanced(from: AudioSession?, to: AudioSession?)
  case queueCompleted
  case repeatModeChanged(RepeatMode)
  case shuffleModeChanged(Bool)
}


/// Detailed playback state with context
public enum DetailedPlaybackState: Sendable, Equatable {
  case idle
  case loading(URL)
  case ready(AudioSession)
  case playing(AudioSession)
  case paused(AudioSession)
  case buffering(AudioSession, progress: Double)
  case completed(AudioSession)
  case error(AudioError, context: String?)

  public var session: AudioSession? {
    switch self {
    case .idle, .loading: return nil
    case .ready(let session), .playing(let session), .paused(let session),
         .buffering(let session, _), .completed(let session): return session
    case .error: return nil
    }
  }

  public var isPlaying: Bool {
    if case .playing = self { return true }
    return false
  }
}

/// Audio quality metrics
public struct AudioQualityMetrics: Sendable, Equatable {
  public let sampleRate: Double
  public let bitRate: Int?
  public let channels: Int
  public let format: String?
  public let codecName: String?
  public let dynamicRange: Double?
  public let peakLevel: Double?
  public let rmsLevel: Double?

  public init(sampleRate: Double, bitRate: Int? = nil, channels: Int, format: String? = nil,
              codecName: String? = nil, dynamicRange: Double? = nil, peakLevel: Double? = nil, rmsLevel: Double? = nil) {
    self.sampleRate = sampleRate
    self.bitRate = bitRate
    self.channels = channels
    self.format = format
    self.codecName = codecName
    self.dynamicRange = dynamicRange
    self.peakLevel = peakLevel
    self.rmsLevel = rmsLevel
  }
}

/// Buffering event information
public enum BufferingEvent: Sendable, Equatable {
  case started(reason: BufferingReason)
  case progress(Double)
  case completed
  case failed(AudioError)
}

/// Reason for buffering
public enum BufferingReason: Sendable, Equatable {
  case initialLoad
  case networkStarvation
  case seeking
  case qualityChange
  case underrun
}

/// Audio system error with context
public struct AudioSystemError: Sendable, Equatable {
  public let error: AudioError
  public let subsystem: AudioSubsystem
  public let context: String?
  public let timestamp: Date

  public init(error: AudioError, subsystem: AudioSubsystem, context: String? = nil) {
    self.error = error
    self.subsystem = subsystem
    self.context = context
    self.timestamp = Date()
  }
}

/// Audio subsystem identifier
public enum AudioSubsystem: Sendable, Equatable {
  case session
  case playback
  case download
  case effects
  case queue
  case network
  case decoder
}

/// Performance metrics
public struct PerformanceMetrics: Sendable, Equatable {
  public let cpuUsage: Double
  public let audioLatency: TimeInterval
  public let bufferUnderruns: Int
  public let droppedFrames: Int
  public let processingTime: TimeInterval
  public let timestamp: Date

  public init(cpuUsage: Double, audioLatency: TimeInterval, bufferUnderruns: Int,
              droppedFrames: Int, processingTime: TimeInterval) {
    self.cpuUsage = cpuUsage
    self.audioLatency = audioLatency
    self.bufferUnderruns = bufferUnderruns
    self.droppedFrames = droppedFrames
    self.processingTime = processingTime
    self.timestamp = Date()
  }
}

/// Memory usage tracking
public struct MemoryUsage: Sendable, Equatable {
  public let audioBufferMemory: Int64
  public let downloadCache: Int64
  public let metadataCache: Int64
  public let effectsMemory: Int64
  public let totalMemory: Int64
  public let timestamp: Date

  public init(audioBufferMemory: Int64, downloadCache: Int64, metadataCache: Int64,
              effectsMemory: Int64, totalMemory: Int64) {
    self.audioBufferMemory = audioBufferMemory
    self.downloadCache = downloadCache
    self.metadataCache = metadataCache
    self.effectsMemory = effectsMemory
    self.totalMemory = totalMemory
    self.timestamp = Date()
  }
}
