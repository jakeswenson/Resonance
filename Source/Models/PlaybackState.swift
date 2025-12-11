// PlaybackState.swift - Playback state and error definitions
// Swift 6 Sendable compliant enums for state management

import Foundation

// MARK: - Type Aliases

/// Type alias for audio progress (percentage 0.0-1.0)
public typealias AudioProgress = Double

/// Enumeration of possible audio session states
/// This enum is Sendable for use across concurrency boundaries
public enum PlaybackState: Sendable, Equatable, Hashable {
    /// No audio loaded
    case idle

    /// Audio being prepared/buffered for playback
    case loading

    /// Audio ready for playback but not yet started
    case ready

    /// Currently playing audio
    case playing

    /// Paused by user action
    case paused

    /// Temporarily pausing for network buffering
    case buffering

    /// Playback finished successfully
    case completed

    /// Playback failed with specific error
    case error(AudioError)

    /// Whether the state represents an active playback session
    public var isActive: Bool {
        switch self {
        case .playing, .paused, .buffering:
            return true
        case .idle, .loading, .ready, .completed, .error:
            return false
        }
    }

    /// Whether the state allows playback controls
    public var allowsPlaybackControls: Bool {
        switch self {
        case .ready, .playing, .paused:
            return true
        case .idle, .loading, .buffering, .completed, .error:
            return false
        }
    }

    /// Whether the state indicates loading or buffering
    public var isLoading: Bool {
        switch self {
        case .loading, .buffering:
            return true
        case .idle, .ready, .playing, .paused, .completed, .error:
            return false
        }
    }

    /// Whether the state indicates an error condition
    public var isError: Bool {
        if case .error = self {
            return true
        }
        return false
    }

    /// Get the error if state is error, nil otherwise
    public var error: AudioError? {
        if case .error(let audioError) = self {
            return audioError
        }
        return nil
    }
}

// MARK: - AudioError

/// Enumeration of possible audio-related errors
/// This enum is Sendable for use across concurrency boundaries
public enum AudioError: Error, Sendable, Equatable, Hashable {
    /// Invalid or malformed URL
    case invalidURL

    /// Network connectivity or request failure
    case networkFailure

    /// Unsupported audio format or codec
    case audioFormatUnsupported

    /// Audio session configuration or hardware error
    case audioSessionError

    /// Seek position is out of valid bounds
    case seekOutOfBounds

    /// Internal processing error with description
    case internalError(String)

    /// File not found or inaccessible
    case fileNotFound

    /// Insufficient storage space
    case insufficientStorage

    /// Operation cancelled by user or system
    case cancelled

    /// Permission denied (e.g., microphone access)
    case permissionDenied

    /// Hardware or system resource unavailable
    case resourceUnavailable

    /// Operation timed out
    case timeout

    /// Codec or decoder error
    case decodingError

    /// Invalid input parameter or value
    case invalidInput(String)

    /// Audio player was deallocated during operation
    case playerDeallocated

    /// User-friendly error description
    public var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid audio URL"
        case .networkFailure:
            return "Network connection failed"
        case .audioFormatUnsupported:
            return "Audio format not supported"
        case .audioSessionError:
            return "Audio system error"
        case .seekOutOfBounds:
            return "Seek position out of range"
        case .internalError(let message):
            return "Internal error: \(message)"
        case .fileNotFound:
            return "Audio file not found"
        case .insufficientStorage:
            return "Not enough storage space"
        case .cancelled:
            return "Operation cancelled"
        case .permissionDenied:
            return "Permission denied"
        case .resourceUnavailable:
            return "Audio resource unavailable"
        case .timeout:
            return "Operation timed out"
        case .decodingError:
            return "Audio decoding failed"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .playerDeallocated:
            return "Audio player was deallocated"
        }
    }

    /// Error category for grouping and handling
    public var category: ErrorCategory {
        switch self {
        case .invalidURL, .fileNotFound:
            return .invalidInput
        case .networkFailure, .timeout:
            return .network
        case .audioFormatUnsupported, .decodingError:
            return .format
        case .audioSessionError, .resourceUnavailable:
            return .system
        case .seekOutOfBounds:
            return .invalidOperation
        case .internalError, .invalidInput:
            return .internal
        case .insufficientStorage:
            return .storage
        case .cancelled:
            return .userAction
        case .permissionDenied:
            return .permission
        case .playerDeallocated:
            return .internal
        }
    }

    /// Whether this error is recoverable through retry
    public var isRecoverable: Bool {
        switch self {
        case .networkFailure, .timeout, .resourceUnavailable, .audioSessionError:
            return true
        case .invalidURL, .audioFormatUnsupported, .seekOutOfBounds, .fileNotFound,
             .insufficientStorage, .cancelled, .permissionDenied, .decodingError, .internalError, .invalidInput, .playerDeallocated:
            return false
        }
    }

    /// Whether this error should be reported to analytics/crash reporting
    public var shouldReport: Bool {
        switch self {
        case .internalError, .audioSessionError, .decodingError:
            return true
        case .invalidURL, .networkFailure, .audioFormatUnsupported, .seekOutOfBounds,
             .fileNotFound, .insufficientStorage, .cancelled, .permissionDenied,
             .resourceUnavailable, .timeout, .invalidInput, .playerDeallocated:
            return false
        }
    }
}

// MARK: - ErrorCategory

/// Categories for grouping related audio errors
public enum ErrorCategory: String, Sendable, CaseIterable {
    case invalidInput
    case network
    case format
    case system
    case invalidOperation
    case `internal`
    case storage
    case userAction
    case permission

    /// User-friendly category description
    public var description: String {
        switch self {
        case .invalidInput:
            return "Invalid Input"
        case .network:
            return "Network Error"
        case .format:
            return "Format Error"
        case .system:
            return "System Error"
        case .invalidOperation:
            return "Invalid Operation"
        case .internal:
            return "Internal Error"
        case .storage:
            return "Storage Error"
        case .userAction:
            return "User Action"
        case .permission:
            return "Permission Error"
        }
    }
}

// MARK: - CustomStringConvertible

extension PlaybackState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle:
            return "idle"
        case .loading:
            return "loading"
        case .ready:
            return "ready"
        case .playing:
            return "playing"
        case .paused:
            return "paused"
        case .buffering:
            return "buffering"
        case .completed:
            return "completed"
        case .error(let audioError):
            return "error(\(audioError.localizedDescription))"
        }
    }
}

extension AudioError: CustomStringConvertible {
    public var description: String {
        return localizedDescription
    }
}

// MARK: - Equatable Implementation for PlaybackState

extension PlaybackState {
    public static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.ready, .ready),
             (.playing, .playing), (.paused, .paused), (.buffering, .buffering),
             (.completed, .completed):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Hashable Implementation

extension PlaybackState {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .idle:
            hasher.combine("idle")
        case .loading:
            hasher.combine("loading")
        case .ready:
            hasher.combine("ready")
        case .playing:
            hasher.combine("playing")
        case .paused:
            hasher.combine("paused")
        case .buffering:
            hasher.combine("buffering")
        case .completed:
            hasher.combine("completed")
        case .error(let audioError):
            hasher.combine("error")
            hasher.combine(audioError)
        }
    }
}

extension AudioError {
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .invalidURL:
            hasher.combine("invalidURL")
        case .networkFailure:
            hasher.combine("networkFailure")
        case .audioFormatUnsupported:
            hasher.combine("audioFormatUnsupported")
        case .audioSessionError:
            hasher.combine("audioSessionError")
        case .seekOutOfBounds:
            hasher.combine("seekOutOfBounds")
        case .internalError(let message):
            hasher.combine("internalError")
            hasher.combine(message)
        case .fileNotFound:
            hasher.combine("fileNotFound")
        case .insufficientStorage:
            hasher.combine("insufficientStorage")
        case .cancelled:
            hasher.combine("cancelled")
        case .permissionDenied:
            hasher.combine("permissionDenied")
        case .resourceUnavailable:
            hasher.combine("resourceUnavailable")
        case .timeout:
            hasher.combine("timeout")
        case .decodingError:
            hasher.combine("decodingError")
        case .invalidInput(let message):
            hasher.combine("invalidInput")
            hasher.combine(message)
        case .playerDeallocated:
            hasher.combine("playerDeallocated")
        }
    }
}