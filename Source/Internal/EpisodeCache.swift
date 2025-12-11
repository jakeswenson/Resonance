//
//  EpisodeCache.swift
//  Resonance
//
//  Smart caching for streamed episodes - stream once, replay offline.
//

import Foundation

/// Actor managing episode audio caching.
///
/// Provides transparent caching:
/// - Remote URLs are cached as they stream
/// - Subsequent plays use cached file
/// - Automatic LRU eviction when cache exceeds limit
///
/// Separate from explicit downloads - cache is automatic and temporary.
public actor EpisodeCache {

    // MARK: - Configuration

    /// Maximum cache size in bytes (default 500MB)
    public var maxCacheSize: Int64 = 500 * 1024 * 1024

    // MARK: - State

    private let cacheDirectory: URL
    private var cacheIndex: [String: CacheEntry] = [:]  // episodeId -> entry

    private struct CacheEntry: Codable {
        let episodeId: String
        let fileURL: URL
        let originalURL: URL
        let size: Int64
        let lastAccessed: Date
    }

    // MARK: - Init

    public init() {
        // Use Caches directory (system can purge if needed)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = caches.appendingPathComponent("Resonance/EpisodeCache", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load index
        Task {
            await loadIndex()
        }
    }

    // MARK: - Public API

    /// Returns the URL to use for playback.
    ///
    /// If episode is cached, returns local file URL.
    /// Otherwise returns original URL (player will stream).
    public func playbackURL(for episode: Episode) -> URL {
        if let entry = cacheIndex[episode.id],
           FileManager.default.fileExists(atPath: entry.fileURL.path) {
            // Update last accessed
            var updated = entry
            updated = CacheEntry(
                episodeId: entry.episodeId,
                fileURL: entry.fileURL,
                originalURL: entry.originalURL,
                size: entry.size,
                lastAccessed: Date()
            )
            cacheIndex[episode.id] = updated
            saveIndex()
            return entry.fileURL
        }
        return episode.url
    }

    /// Checks if an episode is cached.
    public func isCached(_ episode: Episode) -> Bool {
        guard let entry = cacheIndex[episode.id] else { return false }
        return FileManager.default.fileExists(atPath: entry.fileURL.path)
    }

    /// Caches audio data for an episode.
    ///
    /// Called after streaming completes to save for offline replay.
    public func cache(episode: Episode, data: Data) throws {
        // Determine file extension from URL
        let ext = episode.url.pathExtension.isEmpty ? "mp3" : episode.url.pathExtension
        let filename = "\(episode.id.safeFilename).\(ext)"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        // Write data
        try data.write(to: fileURL)

        // Add to index
        let entry = CacheEntry(
            episodeId: episode.id,
            fileURL: fileURL,
            originalURL: episode.url,
            size: Int64(data.count),
            lastAccessed: Date()
        )
        cacheIndex[episode.id] = entry
        saveIndex()

        // Evict if over limit
        evictIfNeeded()
    }

    /// Caches a file for an episode (moves/copies existing file).
    public func cache(episode: Episode, fileURL sourceURL: URL) throws {
        let ext = sourceURL.pathExtension.isEmpty ? "mp3" : sourceURL.pathExtension
        let filename = "\(episode.id.safeFilename).\(ext)"
        let destURL = cacheDirectory.appendingPathComponent(filename)

        // Copy file
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destURL)

        // Get file size
        let attrs = try FileManager.default.attributesOfItem(atPath: destURL.path)
        let size = attrs[.size] as? Int64 ?? 0

        // Add to index
        let entry = CacheEntry(
            episodeId: episode.id,
            fileURL: destURL,
            originalURL: episode.url,
            size: size,
            lastAccessed: Date()
        )
        cacheIndex[episode.id] = entry
        saveIndex()

        evictIfNeeded()
    }

    /// Removes an episode from cache.
    public func remove(episode: Episode) {
        guard let entry = cacheIndex.removeValue(forKey: episode.id) else { return }
        try? FileManager.default.removeItem(at: entry.fileURL)
        saveIndex()
    }

    /// Clears entire cache.
    public func clearAll() {
        for entry in cacheIndex.values {
            try? FileManager.default.removeItem(at: entry.fileURL)
        }
        cacheIndex.removeAll()
        saveIndex()
    }

    /// Total size of cached files in bytes.
    public var totalSize: Int64 {
        cacheIndex.values.reduce(0) { $0 + $1.size }
    }

    /// Number of cached episodes.
    public var count: Int {
        cacheIndex.count
    }

    // MARK: - Private

    private var indexURL: URL {
        cacheDirectory.appendingPathComponent("index.json")
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([CacheEntry].self, from: data) else {
            return
        }

        // Rebuild index, verifying files exist
        for entry in entries {
            if FileManager.default.fileExists(atPath: entry.fileURL.path) {
                cacheIndex[entry.episodeId] = entry
            }
        }
    }

    private func saveIndex() {
        let entries = Array(cacheIndex.values)
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL)
    }

    private func evictIfNeeded() {
        guard totalSize > maxCacheSize else { return }

        // Sort by last accessed (oldest first)
        let sorted = cacheIndex.values.sorted { $0.lastAccessed < $1.lastAccessed }

        var currentSize = totalSize
        for entry in sorted {
            guard currentSize > maxCacheSize else { break }

            try? FileManager.default.removeItem(at: entry.fileURL)
            cacheIndex.removeValue(forKey: entry.episodeId)
            currentSize -= entry.size
        }

        saveIndex()
    }
}

// MARK: - String Extension

private extension String {
    /// Converts string to a safe filename.
    var safeFilename: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return self.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .prefix(100)
            .description
    }
}
