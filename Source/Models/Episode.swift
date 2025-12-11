//
//  Episode.swift
//  Resonance
//
//  Core entity for podcast playback - represents a single episode.
//

import Foundation

/// A podcast episode - the core entity for playback.
///
/// Episodes are identified by their `id` and can be played from either
/// local files or remote URLs. The player handles caching and progress
/// tracking automatically based on the episode ID.
///
/// ```swift
/// let episode = Episode(
///     id: "show-123-ep-45",
///     url: URL(string: "https://example.com/episode.mp3")!,
///     title: "How to Build Great Apps"
/// )
/// try await player.play(episode)
/// ```
public struct Episode: Sendable, Identifiable, Hashable, Codable {

    /// Unique identifier for this episode.
    ///
    /// Used for:
    /// - Progress tracking (resume position)
    /// - Cache management
    /// - Download identification
    ///
    /// Typically the GUID from the podcast RSS feed.
    public let id: String

    /// Audio URL (local file or remote).
    ///
    /// The player automatically handles:
    /// - Local files: Direct playback
    /// - Remote URLs: Stream with caching
    /// - Downloaded: Play from local cache
    public let url: URL

    /// Episode title for display.
    public let title: String

    /// Episode duration in seconds (if known).
    ///
    /// May be nil for live streams or until metadata is loaded.
    public var duration: TimeInterval?

    /// Podcast/show name.
    public var podcastName: String?

    /// Episode artwork URL.
    public var artworkURL: URL?

    /// Publication date.
    public var publishedDate: Date?

    /// Episode description/show notes.
    public var episodeDescription: String?

    /// Season number (if applicable).
    public var seasonNumber: Int?

    /// Episode number (if applicable).
    public var episodeNumber: Int?

    /// Creates a new episode.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (e.g., RSS GUID)
    ///   - url: Audio URL (local or remote)
    ///   - title: Episode title
    ///   - duration: Duration in seconds (optional)
    ///   - podcastName: Show name (optional)
    ///   - artworkURL: Artwork URL (optional)
    public init(
        id: String,
        url: URL,
        title: String,
        duration: TimeInterval? = nil,
        podcastName: String? = nil,
        artworkURL: URL? = nil,
        publishedDate: Date? = nil,
        episodeDescription: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.duration = duration
        self.podcastName = podcastName
        self.artworkURL = artworkURL
        self.publishedDate = publishedDate
        self.episodeDescription = episodeDescription
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }

    /// Whether this episode's URL is a local file.
    public var isLocal: Bool {
        url.isFileURL
    }

    /// Whether this episode's URL is remote (requires streaming/download).
    public var isRemote: Bool {
        !url.isFileURL
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: Episode, rhs: Episode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Convenience Initializers

extension Episode {

    /// Creates an episode from a local file URL.
    ///
    /// Uses the filename as both ID and title.
    public init(localFile url: URL) {
        self.init(
            id: url.lastPathComponent,
            url: url,
            title: url.deletingPathExtension().lastPathComponent
        )
    }
}

// MARK: - Debug Description

extension Episode: CustomStringConvertible {
    public var description: String {
        var parts = ["\"\(title)\""]
        if let podcast = podcastName {
            parts.append("from \(podcast)")
        }
        if let dur = duration {
            let minutes = Int(dur) / 60
            parts.append("(\(minutes) min)")
        }
        return "Episode(\(parts.joined(separator: " ")))"
    }
}
