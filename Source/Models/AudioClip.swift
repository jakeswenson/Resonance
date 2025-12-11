//
//  AudioClip.swift
//  Resonance
//
//  Extracted audio clip for sharing or transcription.
//

import Foundation

/// An extracted audio clip with metadata.
///
/// Represents a segment of audio extracted from an episode.
/// The file is stored in a temporary directory and can be:
/// - Shared via UIActivityViewController
/// - Transcribed using Speech framework
/// - Saved permanently by the app
///
/// ```swift
/// let clip = try await player.extractClip(from: episode, start: 120, end: 180)
/// // Share it
/// let activityVC = UIActivityViewController(activityItems: [clip.fileURL], ...)
/// // Or transcribe it
/// let request = SFSpeechURLRecognitionRequest(url: clip.fileURL)
/// ```
public struct AudioClip: Sendable {

    /// Source episode this clip was extracted from.
    public let episode: Episode

    /// Start time in the original episode (seconds).
    public let startTime: TimeInterval

    /// End time in the original episode (seconds).
    public let endTime: TimeInterval

    /// Local file URL of the extracted audio.
    public let fileURL: URL

    /// Duration of the clip in seconds.
    public var duration: TimeInterval {
        endTime - startTime
    }

    /// Human-readable time range (e.g., "2:30 - 3:00").
    public var timeRangeDescription: String {
        "\(formatTime(startTime)) - \(formatTime(endTime))"
    }

    /// Suggested filename for saving/sharing.
    public var suggestedFilename: String {
        let safeTitle = episode.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .prefix(50)
        let ext = fileURL.pathExtension
        return "\(safeTitle) - \(formatTime(startTime)).\(ext)"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - ClipFormat

/// Output format for extracted audio clips.
public enum ClipFormat: Sendable {
    /// AAC in M4A container - small file size, iOS-native.
    /// Best for sharing.
    case m4a

    /// Uncompressed WAV audio.
    /// Best for transcription (Speech framework works better with uncompressed).
    case wav

    var fileExtension: String {
        switch self {
        case .m4a: return "m4a"
        case .wav: return "wav"
        }
    }
}
