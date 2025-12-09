//
//  ReactiveAudioCoordinator.swift
//  Resonance
//
//  Central orchestrator for reactive audio system coordination using Swift 6 actors
//  Provides a unified interface for protocol implementations to access all audio subsystems
//

import Foundation
import Combine
import AVFoundation

/// Central reactive coordinator for all audio system actors and cross-cutting concerns
///
/// ReactiveAudioCoordinator serves as the primary orchestration layer between the legacy system
/// and the new Swift 6 actor-based architecture. It coordinates interactions between all actors,
/// manages reactive state synchronization, and provides a clean interface for protocol implementations.
///
/// Key Responsibilities:
/// - Orchestrate interactions between AudioSessionActor, DownloadManagerActor, and EffectProcessorActor
/// - Provide unified reactive interface for all audio subsystems
/// - Handle cross-cutting concerns like state synchronization and lifecycle management
/// - Bridge legacy AudioUpdates system with modern actor architecture
/// - Manage dependency injection and actor lifecycle
/// - Coordinate reactive updates across all systems
/// - Provide thread-safe access to all audio functionality
///
/// The coordinator follows the mediator pattern, allowing protocol implementations to interact
/// with a single, well-defined interface rather than managing multiple actor references directly.
///
/// Usage:
/// ```swift
/// let coordinator = ReactiveAudioCoordinator.shared
///
/// // Session management
/// try await coordinator.configureAudioSession(category: .playback)
///
/// // Download management
/// coordinator.downloadAudio(from: url)
///     .sink { progress in updateUI(progress) }
///     .store(in: &cancellables)
///
/// // Effects management
/// try await coordinator.addEffect(reverb)
/// try await coordinator.updateEffectParameter(id: reverbId, key: "wetDryMix", value: 75.0)
/// ```
@available(iOS 13.0, macOS 11.0, tvOS 13.0, *)
@MainActor
public final class ReactiveAudioCoordinator: @unchecked Sendable {

    // MARK: - Singleton

    /// Shared coordinator instance
    public static let shared = ReactiveAudioCoordinator()

    // MARK: - Core Dependencies

    /// Central reactive updates hub
    nonisolated public let audioUpdates: AudioUpdates

    /// Audio session management actor
    private let sessionActor: AudioSessionActor

    /// Download management actor
    private let downloadActor: DownloadManagerActor

    /// Effects processing actor
    private let effectsActor: EffectProcessorActor

    /// AVAudioEngine for audio processing
    private let audioEngine: AVAudioEngine

    // MARK: - State Management

    /// Current coordinator state
    private var state: CoordinatorState = .inactive

    /// Active audio session tracking
    private var currentAudioSession: AudioSession?

    /// Cancellables for reactive subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// Actor binding cancellables (separate for cleanup)
    private var actorCancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle Management

    /// Coordinator initialization state tracking
    private var isInitialized = false

    /// Background task identifier for app lifecycle
    #if os(iOS) || os(tvOS)
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    #endif

    // MARK: - Performance Tracking

    /// Performance metrics collection
    private let performanceTracker = PerformanceTracker()

    /// Memory usage monitoring
    private let memoryMonitor = MemoryMonitor()

    // MARK: - Initialization

    private init() {
        // Initialize core dependencies
        self.audioEngine = AVAudioEngine()
        self.audioUpdates = AudioUpdates()

        // Initialize actors with dependencies
        self.sessionActor = AudioSessionActor()
        self.downloadActor = DownloadManagerActor.shared
        self.effectsActor = EffectProcessorActor(
            audioEngine: audioEngine,
            audioUpdates: audioUpdates
        )

        // Begin initialization process
        Task {
            try? await initialize()
        }
    }

    deinit {
        // Note: Cannot call async cleanup from deinit
        // Cleanup will be handled by actor deinitialization
    }

    // MARK: - Public Interface

    /// Current coordinator state
    public var coordinatorState: CoordinatorState {
        return state
    }

    /// Whether the coordinator is ready for use
    public var isReady: Bool {
        return state == .active && isInitialized
    }

    /// Direct access to the underlying AVAudioEngine (for advanced use)
    /// **WARNING:** Direct engine manipulation can cause unpredictable behavior
    public var engineAccess: AVAudioEngine? {
        guard isReady else { return nil }
        return audioEngine
    }

    /// Initialize the coordinator and all subsystems
    /// - Throws: AudioError if initialization fails
    public func initialize() async throws {
        guard !isInitialized else { return }

        Log.debug("ReactiveAudioCoordinator: Starting initialization")

        do {
            // Update state
            state = .initializing

            // Setup audio engine
            try await setupAudioEngine()

            // Configure default audio session
            try await sessionActor.configureSession()
            try await sessionActor.activate()

            // Setup reactive bindings
            await setupReactiveBindings()

            // Setup performance monitoring
            setupPerformanceMonitoring()

            // Setup app lifecycle handling
            setupAppLifecycleHandling()

            // Mark as initialized
            isInitialized = true
            state = .active

            Log.info("ReactiveAudioCoordinator: Initialization completed successfully")

        } catch {
            state = .error(AudioError.internalError("Coordinator initialization failed: \(error.localizedDescription)"))
            throw AudioError.internalError("Failed to initialize ReactiveAudioCoordinator: \(error.localizedDescription)")
        }
    }

    /// Shutdown the coordinator and cleanup resources
    public func shutdown() async {
        Log.debug("ReactiveAudioCoordinator: Starting shutdown")

        state = .shuttingDown

        // Stop audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        // Deactivate audio session
        try? await sessionActor.deactivate()

        // Cleanup reactive bindings
        await cleanup()

        state = .inactive
        isInitialized = false

        Log.info("ReactiveAudioCoordinator: Shutdown completed")
    }

    // MARK: - Audio Session Coordination

    /// Configure the audio session with specified parameters
    /// - Parameters:
    ///   - category: Audio session category
    ///   - mode: Audio session mode
    ///   - options: Category options
    /// - Throws: AudioError if configuration fails
    #if os(iOS) || os(tvOS)
    public func configureAudioSession(
        category: AVAudioSession.Category = .playback,
        mode: AVAudioSession.Mode = .default,
        options: AVAudioSession.CategoryOptions = []
    ) async throws {
        try await sessionActor.configureSession(category: category, mode: mode, options: options)
    }
    #else
    public func configureAudioSession() async throws {
        // macOS doesn't use AVAudioSession
    }
    #endif

    /// Activate the audio session
    /// - Parameter options: Activation options
    /// - Throws: AudioError if activation fails
    #if os(iOS) || os(tvOS)
    public func activateAudioSession(options: AVAudioSession.SetActiveOptions = .notifyOthersOnDeactivation) async throws {
        try await sessionActor.activate(options: options)
    }
    #else
    public func activateAudioSession() async throws {
        try await sessionActor.activate()
    }
    #endif

    /// Deactivate the audio session
    /// - Parameter options: Deactivation options
    /// - Throws: AudioError if deactivation fails
    #if os(iOS) || os(tvOS)
    public func deactivateAudioSession(options: AVAudioSession.SetActiveOptions = .notifyOthersOnDeactivation) async throws {
        try await sessionActor.deactivate(options: options)
    }
    #else
    public func deactivateAudioSession() async throws {
        try await sessionActor.deactivate()
    }
    #endif

    /// Set the current active audio session
    /// - Parameter session: The audio session to make active
    public func setActiveAudioSession(_ session: AudioSession?) async {
        currentAudioSession = session
        await sessionActor.setCurrentSession(session)

        // Update reactive state
        audioUpdates.updateActiveSession(session)
    }

    /// Get the current active audio session
    /// - Returns: Currently active audio session
    public func getActiveAudioSession() async -> AudioSession? {
        return await sessionActor.getCurrentSession()
    }

    /// Handle application state changes
    /// - Parameter state: New application state
    public func handleApplicationStateChange(_ appState: ApplicationState) async {
        await sessionActor.handleApplicationStateChange(appState)

        switch appState {
        case .background:
            await beginBackgroundTask()
        case .foreground:
            await endBackgroundTask()
        case .inactive:
            break
        }
    }

    // MARK: - Download Coordination

    /// Download audio from a remote URL with progress tracking
    /// - Parameters:
    ///   - url: Remote URL to download
    ///   - metadata: Optional metadata to associate with download
    /// - Returns: Publisher emitting download progress updates
    public func downloadAudio(from url: URL, metadata: AudioMetadata? = nil) -> AnyPublisher<DownloadProgress, AudioError> {
        return Future { [self] promise in
            Task {
                let publisher = await self.downloadActor.downloadAudio(from: url, metadata: metadata)
                promise(.success(publisher))
            }
        }
        .flatMap { $0 }
        .eraseToAnyPublisher()
    }

    /// Cancel an active download
    /// - Parameter url: URL of download to cancel
    /// - Returns: Publisher completing when cancellation is finished
    public func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Future { [self] promise in
            Task {
                let publisher = await self.downloadActor.cancelDownload(for: url)
                promise(.success(publisher))
            }
        }
        .flatMap { $0 }
        .eraseToAnyPublisher()
    }

    /// Pause an active download
    /// - Parameter url: URL of download to pause
    /// - Returns: Publisher completing when download is paused
    public func pauseDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Future { [self] promise in
            Task {
                let publisher = await self.downloadActor.pauseDownload(for: url)
                promise(.success(publisher))
            }
        }
        .flatMap { $0 }
        .eraseToAnyPublisher()
    }

    /// Resume a paused download
    /// - Parameter url: URL of download to resume
    /// - Returns: Publisher emitting progress updates as download continues
    public func resumeDownload(for url: URL) -> AnyPublisher<DownloadProgress, AudioError> {
        return downloadActor.resumeDownload(for: url)
    }

    /// Get local URL for a downloaded file
    /// - Parameter remoteURL: Original remote URL
    /// - Returns: Local file URL if downloaded, nil otherwise
    public func localURL(for remoteURL: URL) async -> URL? {
        return await downloadActor.localURL(for: remoteURL)
    }

    /// Delete a downloaded file
    /// - Parameter localURL: Local file URL to delete
    /// - Returns: Publisher completing when file is deleted
    public func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        return downloadActor.deleteDownload(at: localURL)
    }

    /// Get all downloaded files
    /// - Returns: Array of download information
    public func getAllDownloads() async -> [DownloadInfo] {
        return await downloadActor.getAllDownloads()
    }

    /// Configure cellular download permissions
    /// - Parameter allowed: Whether cellular downloads are allowed
    public func setCellularDownloadsAllowed(_ allowed: Bool) async {
        await downloadActor.allowsCellularDownloads = allowed
    }

    // MARK: - Effects Coordination

    /// Add an audio effect to the processing chain
    /// - Parameter effect: Effect to add
    /// - Throws: AudioError if addition fails
    public func addEffect(_ effect: AudioEffect) async throws {
        try await effectsActor.addEffect(effect)
    }

    /// Remove an effect from the processing chain
    /// - Parameter effectId: ID of effect to remove
    /// - Throws: AudioError if removal fails
    public func removeEffect(id effectId: UUID) async throws {
        try await effectsActor.removeEffect(id: effectId)
    }

    /// Update effect parameters in real-time
    /// - Parameters:
    ///   - effectId: ID of effect to update
    ///   - parameters: New parameter values
    /// - Throws: AudioError if update fails
    public func updateEffect(id effectId: UUID, parameters: [String: Any]) async throws {
        try await effectsActor.updateEffect(id: effectId, parameters: parameters)
    }

    /// Update a single effect parameter
    /// - Parameters:
    ///   - effectId: ID of effect to update
    ///   - key: Parameter key
    ///   - value: New parameter value
    /// - Throws: AudioError if update fails
    public func updateEffectParameter<T: Sendable>(id effectId: UUID, key: String, value: T) async throws {
        try await effectsActor.updateEffectParameter(id: effectId, key: key, value: value)
    }

    /// Enable or disable an effect
    /// - Parameters:
    ///   - effectId: ID of effect to modify
    ///   - enabled: New enabled state
    /// - Throws: AudioError if state change fails
    public func setEffectEnabled(id effectId: UUID, enabled: Bool) async throws {
        try await effectsActor.setEffectEnabled(id: effectId, enabled: enabled)
    }

    /// Reset all effects
    /// - Throws: AudioError if reset fails
    public func resetAllEffects() async throws {
        try await effectsActor.resetAllEffects()
    }

    /// Move effect to new position in chain
    /// - Parameters:
    ///   - effectId: ID of effect to move
    ///   - newIndex: New position in chain
    /// - Throws: AudioError if reorder fails
    public func moveEffect(id effectId: UUID, to newIndex: Int) async throws {
        try await effectsActor.moveEffect(id: effectId, to: newIndex)
    }

    /// Get information about a specific effect
    /// - Parameter effectId: ID of effect to retrieve
    /// - Returns: Effect information if found
    public func getEffect(id effectId: UUID) async -> AudioEffect? {
        return await effectsActor.getEffect(id: effectId)
    }

    /// Get effects of a specific type
    /// - Parameter effectType: Type of effects to retrieve
    /// - Returns: Array of matching effects
    public func getEffects(ofType effectType: EffectType) async -> [AudioEffect] {
        return await effectsActor.getEffects(ofType: effectType)
    }

    /// Get current effect count
    /// - Returns: Number of effects in chain
    public func effectCount() async -> Int {
        return await effectsActor.effectCount()
    }

    /// Get enabled effect count
    /// - Returns: Number of enabled effects
    public func enabledEffectCount() async -> Int {
        return await effectsActor.enabledEffectCount()
    }

    /// Perform batch effect operations
    /// - Parameter operations: Array of operations to perform
    /// - Throws: AudioError if any operation fails
    public func performBatchEffectOperations(_ operations: [EffectOperation]) async throws {
        try await effectsActor.performBatchEffectOperations(operations)
    }

    // MARK: - Cross-Cutting Coordination

    /// Synchronize state across all actors
    /// This method ensures all actors have consistent state information
    public func synchronizeActorState() async {
        // Get current session from session actor
        let session = await sessionActor.getCurrentSession()
        currentAudioSession = session

        // Update reactive state
        audioUpdates.updateActiveSession(session)

        // Synchronize download state
        let downloads = await downloadActor.getAllDownloads()
        audioUpdates.completedDownloads.send(downloads)

        // Update performance metrics
        await updatePerformanceMetrics()
    }

    /// Handle coordination errors from any subsystem
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - subsystem: Which subsystem reported the error
    ///   - context: Additional context about the error
    public func handleCoordinationError(_ error: AudioError, from subsystem: AudioSubsystem, context: String? = nil) {
        let systemError = AudioSystemError(error: error, subsystem: subsystem, context: context)
        audioUpdates.errorEvents.send(systemError)

        Log.error("ReactiveAudioCoordinator: Error from \(subsystem): \(error.localizedDescription)")

        // Handle critical errors
        if shouldHandleCriticalError(error, from: subsystem) {
            Task {
                await handleCriticalError(error, from: subsystem)
            }
        }
    }

    /// Get comprehensive system status
    /// - Returns: Current status of all subsystems
    public func getSystemStatus() async -> CoordinatorSystemStatus {
        let sessionActive = await sessionActor.isSessionActive()
        let sessionConfig = await sessionActor.getSessionConfiguration()
        let downloadCount = await downloadActor.getAllDownloads().count
        let effectCount = await effectsActor.effectCount()
        let enabledEffectCount = await effectsActor.enabledEffectCount()

        return CoordinatorSystemStatus(
            coordinatorState: state,
            audioEngineRunning: audioEngine.isRunning,
            sessionActive: sessionActive,
            sessionCategory: sessionConfig.category,
            sessionMode: sessionConfig.mode,
            activeSession: currentAudioSession,
            downloadCount: downloadCount,
            effectCount: effectCount,
            enabledEffectCount: enabledEffectCount,
            performanceMetrics: await performanceTracker.getCurrentMetrics(),
            memoryUsage: await memoryMonitor.getCurrentUsage()
        )
    }

    // MARK: - Publisher Access

    /// Publisher for current effects chain
    public var currentEffectsPublisher: AnyPublisher<[AudioEffect], Never> {
        return effectsActor.currentEffects
    }

    /// Publisher for download progress updates
    public var downloadProgressPublisher: AnyPublisher<[URL: DownloadProgress], Never> {
        return downloadActor.downloadProgress
    }

    /// Publisher for audio session state changes
    public var sessionStatePublisher: AnyPublisher<AudioSessionState, Never> {
        return sessionActor.sessionStatePublisher
    }

    /// Publisher for interruption events
    public var interruptionPublisher: AnyPublisher<AudioInterruption, Never> {
        return sessionActor.interruptionPublisher
    }

    /// Publisher for route changes
    public var routeChangePublisher: AnyPublisher<AudioRouteChange, Never> {
        return sessionActor.routeChangePublisher
    }

    // MARK: - Private Implementation

    /// Setup the audio engine with default configuration
    private func setupAudioEngine() async throws {
        // Configure audio engine nodes
        let inputNode = audioEngine.inputNode
        let outputNode = audioEngine.outputNode

        // Connect input to output (will be intercepted by effects chain)
        let format = inputNode.outputFormat(forBus: 0)
        audioEngine.connect(inputNode, to: outputNode, format: format)

        // Prepare engine
        audioEngine.prepare()

        // Start engine
        try audioEngine.start()

        Log.debug("ReactiveAudioCoordinator: Audio engine setup completed")
    }

    /// Setup reactive bindings between actors and AudioUpdates
    private func setupReactiveBindings() async {
        // Clear existing bindings
        actorCancellables.removeAll()

        // Bind session actor
        let sessionCancellables = await sessionActor.bindToAudioUpdates(audioUpdates)
        sessionCancellables.forEach { actorCancellables.insert($0) }

        // Bind session state changes
        sessionActor.sessionStatePublisher
            .sink { [weak self] state in
                self?.audioUpdates.sessionState.send(state)
            }
            .store(in: &actorCancellables)

        // Bind interruption events
        sessionActor.interruptionPublisher
            .sink { [weak self] interruption in
                self?.audioUpdates.interruptions.send(interruption)
            }
            .store(in: &actorCancellables)

        // Bind route changes
        sessionActor.routeChangePublisher
            .sink { [weak self] routeChange in
                self?.audioUpdates.routeChanges.send(routeChange)
            }
            .store(in: &actorCancellables)

        // Bind session activation
        sessionActor.activationPublisher
            .sink { [weak self] isActive in
                self?.audioUpdates.sessionActivation.send(isActive)
            }
            .store(in: &actorCancellables)

        // Bind download progress
        downloadActor.downloadProgress
            .sink { [weak self] progressMap in
                self?.audioUpdates.downloadProgress.send(progressMap)

                // Update legacy progress tracking
                if let firstProgress = progressMap.values.first(where: { $0.state.isActive }) {
                    self?.audioUpdates.audioDownloading.send(firstProgress.progress)
                    self?.audioUpdates.streamingDownloadProgress.send((firstProgress.remoteURL, firstProgress.progress))
                }
            }
            .store(in: &actorCancellables)

        // Bind effects updates
        effectsActor.currentEffects
            .sink { [weak self] effects in
                self?.audioUpdates.activeEffects.send(effects)
            }
            .store(in: &actorCancellables)

        Log.debug("ReactiveAudioCoordinator: Reactive bindings setup completed")
    }

    /// Setup performance monitoring
    private func setupPerformanceMonitoring() {
        // Monitor performance metrics every 5 seconds
        Timer.publish(every: 5.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.updatePerformanceMetrics()
                }
            }
            .store(in: &cancellables)

        // Monitor memory usage every 10 seconds
        Timer.publish(every: 10.0, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.updateMemoryMetrics()
                }
            }
            .store(in: &cancellables)
    }

    /// Setup application lifecycle event handling
    private func setupAppLifecycleHandling() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.handleApplicationStateChange(.background)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.handleApplicationStateChange(.foreground)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.handleApplicationStateChange(.inactive)
                }
            }
            .store(in: &cancellables)
        #endif
    }

    /// Begin background task for audio processing
    private func beginBackgroundTask() async {
        #if os(iOS)
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "ResonanceAudioProcessing") {
            Task {
                await self.endBackgroundTask()
            }
        }
        #endif
    }

    /// End background task
    private func endBackgroundTask() async {
        #if os(iOS)
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
        #endif
    }

    /// Update performance metrics
    private func updatePerformanceMetrics() async {
        let metrics = await performanceTracker.getCurrentMetrics()
        audioUpdates.performanceMetrics.send(metrics)
    }

    /// Update memory usage metrics
    private func updateMemoryMetrics() async {
        let usage = await memoryMonitor.getCurrentUsage()
        audioUpdates.memoryUsage.send(usage)
    }

    /// Determine if an error is critical and requires special handling
    private func shouldHandleCriticalError(_ error: AudioError, from subsystem: AudioSubsystem) -> Bool {
        switch error {
        case .audioSessionError, .resourceUnavailable:
            return true
        case .internalError:
            return subsystem == .playback || subsystem == .session
        default:
            return false
        }
    }

    /// Handle critical errors that may require coordinator intervention
    private func handleCriticalError(_ error: AudioError, from subsystem: AudioSubsystem) async {
        Log.error("ReactiveAudioCoordinator: Handling critical error from \(subsystem): \(error)")

        switch (error, subsystem) {
        case (.audioSessionError, .session):
            // Try to recover audio session
            do {
                try await sessionActor.deactivate()
                try await sessionActor.activate()
                Log.info("ReactiveAudioCoordinator: Audio session recovered")
            } catch {
                Log.error("ReactiveAudioCoordinator: Failed to recover audio session: \(error)")
                state = .error(AudioError.internalError("Audio session recovery failed"))
            }

        case (.resourceUnavailable, .playback):
            // Try to restart audio engine
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            do {
                try audioEngine.start()
                Log.info("ReactiveAudioCoordinator: Audio engine restarted")
            } catch {
                Log.error("ReactiveAudioCoordinator: Failed to restart audio engine: \(error)")
                state = .error(AudioError.internalError("Audio engine restart failed"))
            }

        default:
            // Log critical errors for other subsystems
            Log.error("ReactiveAudioCoordinator: Critical error in \(subsystem) - manual intervention may be required")
        }
    }

    /// Cleanup all resources
    private func cleanup() async {
        // Cancel all subscriptions
        cancellables.removeAll()
        actorCancellables.removeAll()

        // End background task if active
        await endBackgroundTask()

        Log.debug("ReactiveAudioCoordinator: Cleanup completed")
    }
}

// MARK: - Supporting Types

/// Current state of the reactive audio coordinator
public enum CoordinatorState: Sendable, Equatable {
    case inactive
    case initializing
    case active
    case shuttingDown
    case error(AudioError)

    public var isActive: Bool {
        return self == .active
    }

    public var error: AudioError? {
        if case .error(let audioError) = self {
            return audioError
        }
        return nil
    }
}

/// Comprehensive system status information
public struct CoordinatorSystemStatus: Sendable {
    public let coordinatorState: CoordinatorState
    public let audioEngineRunning: Bool
    public let sessionActive: Bool
    #if os(iOS) || os(tvOS)
    public let sessionCategory: AVAudioSession.Category
    public let sessionMode: AVAudioSession.Mode
    #endif
    public let activeSession: AudioSession?
    public let downloadCount: Int
    public let effectCount: Int
    public let enabledEffectCount: Int
    public let performanceMetrics: PerformanceMetrics?
    public let memoryUsage: MemoryUsage?

    #if os(iOS) || os(tvOS)
    public init(
        coordinatorState: CoordinatorState,
        audioEngineRunning: Bool,
        sessionActive: Bool,
        sessionCategory: AVAudioSession.Category,
        sessionMode: AVAudioSession.Mode,
        activeSession: AudioSession?,
        downloadCount: Int,
        effectCount: Int,
        enabledEffectCount: Int,
        performanceMetrics: PerformanceMetrics?,
        memoryUsage: MemoryUsage?
    ) {
        self.coordinatorState = coordinatorState
        self.audioEngineRunning = audioEngineRunning
        self.sessionActive = sessionActive
        self.sessionCategory = sessionCategory
        self.sessionMode = sessionMode
        self.activeSession = activeSession
        self.downloadCount = downloadCount
        self.effectCount = effectCount
        self.enabledEffectCount = enabledEffectCount
        self.performanceMetrics = performanceMetrics
        self.memoryUsage = memoryUsage
    }
    #else
    public init(
        coordinatorState: CoordinatorState,
        audioEngineRunning: Bool,
        sessionActive: Bool,
        activeSession: AudioSession?,
        downloadCount: Int,
        effectCount: Int,
        enabledEffectCount: Int,
        performanceMetrics: PerformanceMetrics?,
        memoryUsage: MemoryUsage?
    ) {
        self.coordinatorState = coordinatorState
        self.audioEngineRunning = audioEngineRunning
        self.sessionActive = sessionActive
        self.activeSession = activeSession
        self.downloadCount = downloadCount
        self.effectCount = effectCount
        self.enabledEffectCount = enabledEffectCount
        self.performanceMetrics = performanceMetrics
        self.memoryUsage = memoryUsage
    }
    #endif
}

/// Performance tracking utility
private actor PerformanceTracker {
    private var lastCPUUsage: Double = 0.0
    private var lastLatency: TimeInterval = 0.0

    func getCurrentMetrics() async -> PerformanceMetrics? {
        // In a real implementation, this would collect actual performance data
        // For now, return mock data showing the structure
        return PerformanceMetrics(
            cpuUsage: lastCPUUsage,
            audioLatency: lastLatency,
            bufferUnderruns: 0,
            droppedFrames: 0,
            processingTime: 0.001
        )
    }
}

/// Memory usage monitoring utility
private actor MemoryMonitor {
    func getCurrentUsage() async -> MemoryUsage? {
        // In a real implementation, this would collect actual memory usage data
        // For now, return mock data showing the structure
        return MemoryUsage(
            audioBufferMemory: 1024 * 1024,
            downloadCache: 10 * 1024 * 1024,
            metadataCache: 512 * 1024,
            effectsMemory: 2 * 1024 * 1024,
            totalMemory: 14 * 1024 * 1024
        )
    }
}

// MARK: - Convenience Extensions

extension ReactiveAudioCoordinator {

    /// Create and add an effect with default parameters
    /// - Parameter effectType: Type of effect to create
    /// - Returns: ID of created effect
    /// - Throws: AudioError if creation or addition fails
    public func addEffect(type effectType: EffectType) async throws -> UUID {
        return try await effectsActor.addEffect(type: effectType)
    }

    /// Toggle an effect's enabled state
    /// - Parameter effectId: ID of effect to toggle
    /// - Throws: AudioError if toggle fails
    public func toggleEffect(id effectId: UUID) async throws {
        if let effect = await getEffect(id: effectId) {
            try await setEffectEnabled(id: effectId, enabled: !effect.isEnabled)
        }
    }

    /// Check if coordinator is ready and throw if not
    /// - Throws: AudioError if coordinator is not ready
    public func ensureReady() throws {
        guard isReady else {
            if case .error(let error) = state {
                throw error
            } else {
                throw AudioError.internalError("ReactiveAudioCoordinator is not ready (state: \(state))")
            }
        }
    }
}

// MARK: - Legacy Integration

extension ReactiveAudioCoordinator {

    /// Bridge to legacy AudioUpdates for backward compatibility
    /// This method provides access to the legacy reactive system
    /// - Returns: The AudioUpdates instance used by this coordinator
    nonisolated public func getLegacyAudioUpdates() -> AudioUpdates {
        return audioUpdates
    }

    /// Update legacy playback status (for backward compatibility)
    /// - Parameter status: Legacy playback status
    public func updateLegacyPlaybackStatus(_ status: SAPlayingStatus) {
        audioUpdates.playingStatus.send(status)
    }

    /// Update legacy elapsed time (for backward compatibility)
    /// - Parameter time: Elapsed time in seconds
    public func updateLegacyElapsedTime(_ time: TimeInterval) {
        audioUpdates.elapsedTime.send(time)
        audioUpdates.precisePosition.send(time)
    }

    /// Update legacy duration (for backward compatibility)
    /// - Parameter duration: Total duration in seconds
    public func updateLegacyDuration(_ duration: TimeInterval) {
        audioUpdates.duration.send(duration)
    }
}

#if os(iOS)
import UIKit
#endif