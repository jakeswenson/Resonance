//
//  SilenceAnalyzer.swift
//  Resonance
//
//  Analyzes audio to detect silence for smart speed adjustment.
//  Works with both streamed (buffered) and local audio.
//

import AVFoundation
import Foundation

/// Analyzes audio to build a speed map for silence trimming.
///
/// Reads ahead of the current playback position to detect silent segments,
/// then provides a map of playback rates. Silent portions play faster.
public actor SilenceAnalyzer {

    // MARK: - Types

    /// Configuration for silence detection.
    public struct Config: Sendable {
        /// Amplitude threshold in dB below which audio is considered silence.
        /// Default: -35 dB (fairly aggressive, catches quiet speech pauses)
        public var silenceThresholdDb: Float = -35

        /// Minimum duration in seconds for a segment to be considered silence.
        /// Shorter silences aren't worth speeding up (too jarring).
        /// Default: 0.3 seconds
        public var minSilenceDuration: TimeInterval = 0.3

        /// Playback rate multiplier during silence.
        /// Default: 2.0x (silence plays at double speed)
        public var silenceSpeedMultiplier: Float = 2.0

        /// Maximum combined speed (user speed * silence multiplier).
        /// Prevents excessive speed when user is already at 2x.
        /// Default: 3.5x
        public var maxCombinedSpeed: Float = 3.5

        public init() {}
    }

    /// A segment of audio with an associated playback rate.
    public struct SpeedSegment: Sendable {
        public let start: TimeInterval
        public let end: TimeInterval
        public let rate: Float  // 1.0 = normal, >1.0 = speed up (silence)

        public var duration: TimeInterval { end - start }
    }

    /// Statistics about silence detection.
    public struct Stats: Sendable {
        public let totalDurationAnalyzed: TimeInterval
        public let silenceDuration: TimeInterval
        public let segmentCount: Int

        public var timeSaved: TimeInterval {
            // Time saved = silence duration * (1 - 1/rate)
            // At 2x speed, you save half the silence time
            silenceDuration * 0.5
        }

        public var percentageSilence: Double {
            guard totalDurationAnalyzed > 0 else { return 0 }
            return silenceDuration / totalDurationAnalyzed
        }
    }

    // MARK: - State

    public var config: Config

    /// Cached speed segments for the current asset.
    private var cachedSegments: [SpeedSegment] = []
    private var analyzedRange: ClosedRange<TimeInterval>?
    private var currentAssetURL: URL?

    // MARK: - Init

    public init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Public API

    /// Analyzes audio from a URL and returns speed segments.
    ///
    /// For streaming URLs, only analyzes what's been buffered.
    /// Call this periodically to extend the analysis as more audio buffers.
    ///
    /// - Parameters:
    ///   - url: Audio URL (local or remote)
    ///   - startTime: Start of analysis range (usually current playback position)
    ///   - duration: How far ahead to analyze
    ///   - bufferedEnd: For streaming, the end of buffered content (optimization hint)
    /// - Returns: Array of speed segments, or empty if analysis fails
    public func analyze(
        url: URL,
        from startTime: TimeInterval,
        duration: TimeInterval,
        bufferedEnd: TimeInterval? = nil
    ) async -> [SpeedSegment] {
        // Check if we can use cached results
        if url == currentAssetURL,
           let range = analyzedRange,
           range.contains(startTime),
           range.upperBound >= startTime + duration {
            // Return cached segments for requested range
            return cachedSegments.filter { $0.end > startTime && $0.start < startTime + duration }
        }

        // New URL or need to extend analysis
        if url != currentAssetURL {
            cachedSegments = []
            analyzedRange = nil
            currentAssetURL = url
        }

        let asset = AVURLAsset(url: url)

        // Determine analysis end time
        var endTime = startTime + duration
        if let buffered = bufferedEnd {
            endTime = min(endTime, buffered)
        }

        // Can't analyze negative duration
        guard endTime > startTime else { return cachedSegments }

        // Perform analysis
        let newSegments = await analyzeRange(asset: asset, start: startTime, end: endTime)

        // Merge with existing cache
        mergeSegments(newSegments, from: startTime, to: endTime)

        return cachedSegments.filter { $0.end > startTime && $0.start < startTime + duration }
    }

    /// Returns the playback rate for a specific time.
    ///
    /// - Parameters:
    ///   - time: Playback position
    ///   - baseRate: User's selected playback rate (e.g., 1.5x)
    /// - Returns: Effective rate (capped at maxCombinedSpeed)
    public func rate(at time: TimeInterval, baseRate: Float) -> Float {
        if let segment = cachedSegments.first(where: { time >= $0.start && time < $0.end }) {
            let combined = baseRate * segment.rate
            return min(combined, config.maxCombinedSpeed)
        }
        return baseRate
    }

    /// Clears cached analysis (call when loading a new episode).
    public func reset() {
        cachedSegments = []
        analyzedRange = nil
        currentAssetURL = nil
    }

    /// Returns statistics about detected silence.
    public func stats() -> Stats {
        let silenceSegments = cachedSegments.filter { $0.rate > 1.0 }
        let silenceDuration = silenceSegments.reduce(0) { $0 + $1.duration }
        let totalDuration = analyzedRange.map { $0.upperBound - $0.lowerBound } ?? 0

        return Stats(
            totalDurationAnalyzed: totalDuration,
            silenceDuration: silenceDuration,
            segmentCount: silenceSegments.count
        )
    }

    // MARK: - Private Analysis

    private func analyzeRange(asset: AVAsset, start: TimeInterval, end: TimeInterval) async -> [SpeedSegment] {
        // Get audio track
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }

        // Create asset reader
        guard let reader = try? AVAssetReader(asset: asset) else {
            return []
        }

        // Configure output for PCM samples
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false
        ]

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else { return [] }
        reader.add(output)

        // Set time range
        let startCMTime = CMTime(seconds: start, preferredTimescale: 44100)
        let durationCMTime = CMTime(seconds: end - start, preferredTimescale: 44100)
        reader.timeRange = CMTimeRange(start: startCMTime, duration: durationCMTime)

        guard reader.startReading() else { return [] }

        // Analyze samples
        var amplitudes: [(time: TimeInterval, db: Float)] = []
        let chunkDuration: TimeInterval = 0.05  // Analyze in 50ms chunks

        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer() else { break }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let db = calculateAmplitude(sampleBuffer: sampleBuffer)

            amplitudes.append((time: presentationTime, db: db))

            // Release the buffer
            CMSampleBufferInvalidate(sampleBuffer)
        }

        // Convert amplitudes to speed segments
        return buildSpeedSegments(from: amplitudes, chunkDuration: chunkDuration)
    }

    private func calculateAmplitude(sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return -100  // Very quiet
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer else { return -100 }

        // Interpret as Float32 samples
        let floatPointer = UnsafeRawPointer(data).assumingMemoryBound(to: Float32.self)
        let sampleCount = length / MemoryLayout<Float32>.size

        guard sampleCount > 0 else { return -100 }

        // Calculate RMS
        var sumOfSquares: Float = 0
        for i in 0..<sampleCount {
            let sample = floatPointer[i]
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(sampleCount))

        // Convert to dB (with floor to avoid -infinity)
        let db = 20 * log10(max(rms, 0.0001))
        return db
    }

    private func buildSpeedSegments(
        from amplitudes: [(time: TimeInterval, db: Float)],
        chunkDuration: TimeInterval
    ) -> [SpeedSegment] {
        guard !amplitudes.isEmpty else { return [] }

        var segments: [SpeedSegment] = []
        var silenceStart: TimeInterval?

        for (time, db) in amplitudes {
            let isSilent = db < config.silenceThresholdDb

            if isSilent {
                if silenceStart == nil {
                    silenceStart = time
                }
            } else {
                if let start = silenceStart {
                    let silenceDuration = time - start
                    if silenceDuration >= config.minSilenceDuration {
                        // Add silence segment
                        segments.append(SpeedSegment(
                            start: start,
                            end: time,
                            rate: config.silenceSpeedMultiplier
                        ))
                    }
                    silenceStart = nil
                }
            }
        }

        // Handle trailing silence
        if let start = silenceStart, let last = amplitudes.last {
            let silenceDuration = last.time + chunkDuration - start
            if silenceDuration >= config.minSilenceDuration {
                segments.append(SpeedSegment(
                    start: start,
                    end: last.time + chunkDuration,
                    rate: config.silenceSpeedMultiplier
                ))
            }
        }

        return segments
    }

    private func mergeSegments(_ newSegments: [SpeedSegment], from start: TimeInterval, to end: TimeInterval) {
        // Remove any existing segments that overlap with the new range
        cachedSegments.removeAll { segment in
            segment.start >= start && segment.end <= end
        }

        // Add new segments
        cachedSegments.append(contentsOf: newSegments)

        // Sort by start time
        cachedSegments.sort { $0.start < $1.start }

        // Update analyzed range
        if let existing = analyzedRange {
            analyzedRange = min(existing.lowerBound, start)...max(existing.upperBound, end)
        } else {
            analyzedRange = start...end
        }
    }
}
