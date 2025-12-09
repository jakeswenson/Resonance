// AudioMetadata.swift - Immutable audio content information
// Swift 6 Sendable compliant value types for metadata management

import Foundation

/// Immutable audio content information for display and organization
/// This struct is Sendable for use across concurrency boundaries
public struct AudioMetadata: Sendable, Equatable, Hashable, Codable {
    /// Title of the audio content
    public let title: String?

    /// Artist or creator name
    public let artist: String?

    /// Album or collection name
    public let album: String?

    /// Artwork image data for lock screen and UI display
    public let artwork: Data?

    /// Chapter information for podcast navigation
    public let chapters: [ChapterInfo]

    /// Release date of the content
    public let releaseDate: Date?

    /// Genre classification
    public let genre: String?

    /// Duration in seconds (may be approximate for streaming)
    public let duration: TimeInterval?

    /// File size in bytes (for downloaded content)
    public let fileSize: Int64?

    /// Content description or summary
    public let contentDescription: String?

    /// Creates new audio metadata
    /// - Parameters:
    ///   - title: Content title
    ///   - artist: Artist or creator name
    ///   - album: Album or collection name
    ///   - artwork: Image data for artwork
    ///   - chapters: Chapter information array
    ///   - releaseDate: Content release date
    ///   - genre: Genre classification
    ///   - duration: Content duration in seconds
    ///   - fileSize: File size in bytes
    ///   - description: Content description
    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artwork: Data? = nil,
        chapters: [ChapterInfo] = [],
        releaseDate: Date? = nil,
        genre: String? = nil,
        duration: TimeInterval? = nil,
        fileSize: Int64? = nil,
        description: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.chapters = chapters
        self.releaseDate = releaseDate
        self.genre = genre
        self.duration = duration
        self.fileSize = fileSize
        self.contentDescription = description
    }

    /// Creates a copy with updated values
    /// - Parameters:
    ///   - title: Updated title
    ///   - artist: Updated artist
    ///   - album: Updated album
    ///   - artwork: Updated artwork
    ///   - chapters: Updated chapters
    ///   - releaseDate: Updated release date
    ///   - genre: Updated genre
    ///   - duration: Updated duration
    ///   - fileSize: Updated file size
    ///   - description: Updated description
    /// - Returns: New metadata instance with updated values
    public func updated(
        title: String?? = nil,
        artist: String?? = nil,
        album: String?? = nil,
        artwork: Data?? = nil,
        chapters: [ChapterInfo]? = nil,
        releaseDate: Date?? = nil,
        genre: String?? = nil,
        duration: TimeInterval?? = nil,
        fileSize: Int64?? = nil,
        description: String?? = nil
    ) -> AudioMetadata {
        AudioMetadata(
            title: title ?? self.title,
            artist: artist ?? self.artist,
            album: album ?? self.album,
            artwork: artwork ?? self.artwork,
            chapters: chapters ?? self.chapters,
            releaseDate: releaseDate ?? self.releaseDate,
            genre: genre ?? self.genre,
            duration: duration ?? self.duration,
            fileSize: fileSize ?? self.fileSize,
            description: description ?? self.description
        )
    }

    /// Display title using title or fallback to artist
    public var displayTitle: String {
        return title ?? artist ?? "Unknown Title"
    }

    /// Display artist using artist or fallback to "Unknown Artist"
    public var displayArtist: String {
        return artist ?? "Unknown Artist"
    }

    /// Whether this metadata has artwork
    public var hasArtwork: Bool {
        return artwork != nil && !(artwork?.isEmpty ?? true)
    }

    /// Whether this metadata has chapters
    public var hasChapters: Bool {
        return !chapters.isEmpty
    }

    /// Formatted duration string (e.g., "1:23:45" or "12:34")
    public var formattedDuration: String? {
        guard let duration = duration, duration > 0 else { return nil }
        return TimeInterval.formatDuration(duration)
    }

    /// Formatted file size string (e.g., "12.5 MB")
    public var formattedFileSize: String? {
        guard let fileSize = fileSize, fileSize > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - ChapterInfo

/// Information about a chapter or segment within audio content
/// This struct is Sendable for use across concurrency boundaries
public struct ChapterInfo: Sendable, Equatable, Hashable, Identifiable, Codable {
    /// Unique identifier for the chapter
    public let id: UUID

    /// Chapter title
    public let title: String

    /// Start time in seconds
    public let startTime: TimeInterval

    /// End time in seconds
    public let endTime: TimeInterval

    /// Optional chapter artwork
    public let artwork: Data?

    /// Optional chapter description
    public let chapterDescription: String?

    /// Optional chapter URL for additional content
    public let url: URL?

    /// Creates new chapter information
    /// - Parameters:
    ///   - id: Unique identifier (auto-generated if not provided)
    ///   - title: Chapter title
    ///   - startTime: Start time in seconds
    ///   - endTime: End time in seconds
    ///   - artwork: Optional chapter artwork
    ///   - chapterDescription: Optional chapter description
    ///   - url: Optional chapter URL
    public init(
        id: UUID = UUID(),
        title: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        artwork: Data? = nil,
        chapterDescription: String? = nil,
        url: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.artwork = artwork
        self.chapterDescription = chapterDescription
        self.url = url
    }

    /// Duration of this chapter in seconds
    public var duration: TimeInterval {
        return max(0, endTime - startTime)
    }

    /// Whether a given time falls within this chapter
    /// - Parameter time: Time to check in seconds
    /// - Returns: True if time is within chapter bounds
    public func contains(time: TimeInterval) -> Bool {
        return time >= startTime && time < endTime
    }

    /// Formatted start time string
    public var formattedStartTime: String {
        return TimeInterval.formatDuration(startTime)
    }

    /// Formatted end time string
    public var formattedEndTime: String {
        return TimeInterval.formatDuration(endTime)
    }

    /// Formatted duration string
    public var formattedDuration: String {
        return TimeInterval.formatDuration(duration)
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Formats duration as a string (e.g., "1:23:45" or "12:34")
    /// - Parameter duration: Duration in seconds
    /// - Returns: Formatted string
    static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - CustomStringConvertible

extension AudioMetadata: CustomStringConvertible {
    public var description: String {
        let titlePart = displayTitle
        let artistPart = artist.map { " by \($0)" } ?? ""
        let chapterPart = hasChapters ? " (\(chapters.count) chapters)" : ""
        return "\(titlePart)\(artistPart)\(chapterPart)"
    }
}

extension ChapterInfo: CustomStringConvertible {
    public var description: String {
        return "\(title) [\(formattedStartTime) - \(formattedEndTime)]"
    }
}