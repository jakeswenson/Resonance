//
//  AudioSessionActor.swift
//  Resonance
//
//  Thread-safe audio session management with Swift 6 actor isolation
//  Manages AVAudioSession configuration, interruptions, and state transitions
//

import AVFoundation
import Combine
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Actor providing thread-safe management of AVAudioSession operations
/// Isolates all audio session configuration and state management to prevent threading issues
@available(iOS 13.0, macOS 11.0, tvOS 13.0, *)
public actor AudioSessionActor {

    // MARK: - Session State

    /// Current session configuration
    private var currentSession: AudioSession?

    /// Audio session category and mode tracking
    #if os(iOS) || os(tvOS) || os(watchOS)
    private var configuredCategory: AVAudioSession.Category = .playback
    private var configuredMode: AVAudioSession.Mode = .default
    private var configuredOptions: AVAudioSession.CategoryOptions = []
    #endif

    /// Session activation state
    private var isActivated: Bool = false

    /// Background/foreground state tracking
    private var applicationState: ApplicationState = .foreground

    // MARK: - Reactive Publishers

    /// Publisher for audio session state changes
    nonisolated private let sessionStateSubject = PassthroughSubject<AudioSessionState, Never>()

    /// Publisher for interruption events
    nonisolated private let interruptionSubject = PassthroughSubject<AudioInterruption, Never>()

    /// Publisher for route changes
    nonisolated private let routeChangeSubject = PassthroughSubject<AudioRouteChange, Never>()

    /// Publisher for session activation state
    nonisolated private let activationSubject = CurrentValueSubject<Bool, Never>(false)

    // MARK: - Notification Observers

    /// Stores notification observation tokens
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    public init() {
        Task {
            await setupNotificationObservers()
        }
    }

    deinit {
        Task {
            await cleanup()
        }
    }

    // MARK: - Public Interface

    /// Configure and activate the audio session
    /// - Parameters:
    ///   - category: Audio session category
    ///   - mode: Audio session mode
    ///   - options: Category options
    /// - Throws: AudioError if configuration fails
    #if os(iOS) || os(tvOS) || os(watchOS)
    public func configureSession(
        category: AVAudioSession.Category = .playback,
        mode: AVAudioSession.Mode = .default,
        options: AVAudioSession.CategoryOptions = []
    ) throws {
    #else
    public func configureSession() throws {
    #endif
        #if os(iOS) || os(tvOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()

        do {
            // Set category and mode
            try session.setCategory(category, mode: mode, options: options)

            // Store configuration
            configuredCategory = category
            configuredMode = mode
            configuredOptions = options

            // Publish state change
            sessionStateSubject.send(.configured(category: category, mode: mode, options: options))

        } catch {
            let audioError = AudioError.audioSessionError
            sessionStateSubject.send(.error(audioError))
            throw audioError
        }
        #else
        // macOS doesn't require audio session configuration - send a placeholder state
        sessionStateSubject.send(.active)
        #endif
    }

    /// Activate the audio session
    /// - Parameter options: Activation options
    /// - Throws: AudioError if activation fails
    #if os(iOS) || os(tvOS) || os(watchOS)
    public func activate(options: AVAudioSession.SetActiveOptions = .notifyOthersOnDeactivation) throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(true, options: options)
            isActivated = true
            activationSubject.send(true)
            sessionStateSubject.send(.activated)
        } catch {
            let audioError = AudioError.audioSessionError
            sessionStateSubject.send(.error(audioError))
            throw audioError
        }
    }
    #else
    public func activate() throws {
        // macOS doesn't use AVAudioSession
        isActivated = true
        activationSubject.send(true)
        sessionStateSubject.send(.activated)
    }
    #endif

    /// Deactivate the audio session
    /// - Parameter options: Deactivation options
    /// - Throws: AudioError if deactivation fails
    #if os(iOS) || os(tvOS) || os(watchOS)
    public func deactivate(options: AVAudioSession.SetActiveOptions = .notifyOthersOnDeactivation) throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(false, options: options)
            isActivated = false
            activationSubject.send(false)
            sessionStateSubject.send(.deactivated)
        } catch {
            let audioError = AudioError.audioSessionError
            sessionStateSubject.send(.error(audioError))
            throw audioError
        }
    }
    #else
    public func deactivate() throws {
        // macOS doesn't use AVAudioSession
        isActivated = false
        activationSubject.send(false)
        sessionStateSubject.send(.deactivated)
    }
    #endif

    /// Set the current active session
    /// - Parameter session: The audio session to manage
    public func setCurrentSession(_ session: AudioSession?) {
        currentSession = session

        if let session = session {
            sessionStateSubject.send(.sessionChanged(session))
        } else {
            sessionStateSubject.send(.sessionCleared)
        }
    }

    /// Get the current active session
    /// - Returns: Current audio session, if any
    public func getCurrentSession() -> AudioSession? {
        return currentSession
    }

    /// Check if session is currently activated
    /// - Returns: True if session is active
    public func isSessionActive() -> Bool {
        return isActivated
    }

    /// Get current session configuration
    /// - Returns: Tuple of category, mode, and options
    #if os(iOS) || os(tvOS) || os(watchOS)
    public func getSessionConfiguration() -> (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) {
        return (configuredCategory, configuredMode, configuredOptions)
    }
    #else
    public func getSessionConfiguration() -> (category: String, mode: String, options: [String]) {
        return (category: "default", mode: "default", options: [])
    }
    #endif

    /// Handle application state changes for background/foreground transitions
    /// - Parameter state: New application state
    public func handleApplicationStateChange(_ state: ApplicationState) {
        let previousState = applicationState
        applicationState = state

        switch state {
        case .background:
            sessionStateSubject.send(.backgrounded)
            #if os(iOS) || os(tvOS) || os(watchOS)
            // Don't deactivate if we need background audio
            if configuredCategory != .playback {
                try? deactivate()
            }
            #endif

        case .foreground:
            sessionStateSubject.send(.foregrounded)
            // Reactivate session when returning to foreground
            if previousState == .background && !isActivated {
                try? activate()
            }

        case .inactive:
            sessionStateSubject.send(.inactive)
        }
    }

    // MARK: - Reactive Publishers (Non-isolated)

    /// Publisher for session state changes
    nonisolated public var sessionStatePublisher: AnyPublisher<AudioSessionState, Never> {
        sessionStateSubject.eraseToAnyPublisher()
    }

    /// Publisher for interruption events
    nonisolated public var interruptionPublisher: AnyPublisher<AudioInterruption, Never> {
        interruptionSubject.eraseToAnyPublisher()
    }

    /// Publisher for route changes
    nonisolated public var routeChangePublisher: AnyPublisher<AudioRouteChange, Never> {
        routeChangeSubject.eraseToAnyPublisher()
    }

    /// Publisher for activation state
    nonisolated public var activationPublisher: AnyPublisher<Bool, Never> {
        activationSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Implementation

    /// Setup notification observers for audio session events
    private func setupNotificationObservers() {
        let notificationCenter = NotificationCenter.default

        #if os(iOS) || os(tvOS)
        // Audio interruption notifications
        let interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task {
                await self?.handleInterruption(notification)
            }
        }
        notificationObservers.append(interruptionObserver)

        // Audio route change notifications
        let routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            Task {
                await self?.handleRouteChange(notification)
            }
        }
        notificationObservers.append(routeChangeObserver)
        #endif

        #if os(iOS)
        // Background/foreground notifications (iOS only)
        let backgroundObserver = notificationCenter.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task {
                await self?.handleApplicationStateChange(.background)
            }
        }
        notificationObservers.append(backgroundObserver)

        let foregroundObserver = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task {
                await self?.handleApplicationStateChange(.foreground)
            }
        }
        notificationObservers.append(foregroundObserver)

        let inactiveObserver = notificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task {
                await self?.handleApplicationStateChange(.inactive)
            }
        }
        notificationObservers.append(inactiveObserver)
        #endif
    }

    /// Handle audio interruption notifications
    /// - Parameter notification: Interruption notification
    private func handleInterruption(_ notification: Notification) {
        #if os(iOS) || os(tvOS)
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began - pause playback
            interruptionSubject.send(.began)
            sessionStateSubject.send(.interrupted)

        case .ended:
            // Interruption ended - potentially resume playback
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            let shouldResume = options.contains(.shouldResume)
            interruptionSubject.send(.ended(shouldResume: shouldResume))

            if shouldResume {
                sessionStateSubject.send(.resumingAfterInterruption)
            } else {
                sessionStateSubject.send(.interruptionEnded)
            }

        @unknown default:
            // Handle unknown interruption types
            break
        }
        #endif
    }

    /// Handle audio route change notifications
    /// - Parameter notification: Route change notification
    private func handleRouteChange(_ notification: Notification) {
        #if os(iOS) || os(tvOS)
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription
        let currentRoute = AVAudioSession.sharedInstance().currentRoute

        let routeChange = AudioRouteChange(
            reason: reason,
            previousRoute: previousRoute,
            currentRoute: currentRoute
        )

        routeChangeSubject.send(routeChange)
        sessionStateSubject.send(.routeChanged(routeChange))

        // Handle specific route change scenarios
        switch reason {
        case .oldDeviceUnavailable:
            // Device was unplugged - might need to pause
            if let previousOutput = previousRoute?.outputs.first,
               previousOutput.portType == .headphones {
                interruptionSubject.send(.deviceDisconnected(.headphones))
            }

        case .newDeviceAvailable:
            // New device connected
            if let currentOutput = currentRoute.outputs.first {
                interruptionSubject.send(.deviceConnected(currentOutput.portType))
            }

        default:
            break
        }
        #endif
    }

    /// Clean up resources
    private func cleanup() {
        // Remove notification observers
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        // Complete publishers
        sessionStateSubject.send(completion: .finished)
        interruptionSubject.send(completion: .finished)
        routeChangeSubject.send(completion: .finished)
        activationSubject.send(completion: .finished)
    }
}

// MARK: - Supporting Types

/// Application state for background/foreground handling
public enum ApplicationState: Sendable {
    case foreground
    case background
    case inactive
}

/// Audio session state changes
public enum AudioSessionState: Sendable {
    #if os(iOS) || os(tvOS) || os(watchOS)
    case configured(category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)
    #endif
    case activated
    case deactivated
    case sessionChanged(AudioSession)
    case sessionCleared
    case interrupted
    case interruptionEnded
    case resumingAfterInterruption
    #if os(iOS) || os(tvOS) || os(watchOS)
    case routeChanged(AudioRouteChange)
    #endif
    case backgrounded
    case foregrounded
    case inactive
    case error(AudioError)
}

/// Audio interruption events
public enum AudioInterruption: Sendable {
    case began
    case ended(shouldResume: Bool)
    #if os(iOS) || os(tvOS) || os(watchOS)
    case deviceDisconnected(AVAudioSession.Port)
    case deviceConnected(AVAudioSession.Port)
    #endif
}

/// Audio route change information
public struct AudioRouteChange: Sendable {
    #if os(iOS) || os(tvOS) || os(watchOS)
    public let reason: AVAudioSession.RouteChangeReason
    public let previousRoute: AVAudioSessionRouteDescription?
    public let currentRoute: AVAudioSessionRouteDescription

    public init(reason: AVAudioSession.RouteChangeReason, previousRoute: AVAudioSessionRouteDescription?, currentRoute: AVAudioSessionRouteDescription) {
        self.reason = reason
        self.previousRoute = previousRoute
        self.currentRoute = currentRoute
    }
    #else
    public let reason: String
    public let previousRoute: String?
    public let currentRoute: String

    public init(reason: String, previousRoute: String?, currentRoute: String) {
        self.reason = reason
        self.previousRoute = previousRoute
        self.currentRoute = currentRoute
    }
    #endif
}

// MARK: - Integration with AudioUpdates

extension AudioSessionActor {
    /// Create reactive bindings with the existing AudioUpdates system
    /// - Parameter updates: AudioUpdates instance to bind to
    /// - Returns: Set of AnyCancellable for subscription management
    nonisolated public func bindToAudioUpdates(_ updates: AudioUpdates) -> Set<AnyCancellable> {
        var cancellables = Set<AnyCancellable>()

        // Bind interruptions to affect playing status
        interruptionPublisher
            .sink { interruption in
                switch interruption {
                case .began, .deviceDisconnected:
                    updates.updatePlayingStatus(.paused)
                case .ended(shouldResume: let shouldResume):
                    if shouldResume {
                        updates.updatePlayingStatus(.playing)
                    }
                case .deviceConnected:
                    // Device connected - no automatic action
                    break
                }
            }
            .store(in: &cancellables)

        return cancellables
    }
}

// MARK: - Convenience Extensions

#if os(iOS) || os(tvOS) || os(watchOS)
extension AVAudioSession.Category: @retroactive Sendable {}
extension AVAudioSession.Mode: @retroactive Sendable {}
extension AVAudioSession.CategoryOptions: @retroactive Sendable {}
extension AVAudioSession.RouteChangeReason: @retroactive Sendable {}
extension AVAudioSession.Port: @retroactive Sendable {}
#endif