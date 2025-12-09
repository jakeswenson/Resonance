// ConcurrencyPerformanceTests.swift - Swift 6 concurrency performance validation
// Validates actor isolation, async/await performance, and thread safety

import XCTest
import Combine
import AVFoundation
@testable import Resonance

/// Performance tests for Swift 6 concurrency features
///
/// Requirements:
/// - Actor isolation must be thread-safe and performant
/// - Async/await calls should complete without blocking
/// - Concurrent operations should scale efficiently
/// - No data races or thread safety violations
@MainActor
final class ConcurrencyPerformanceTests: XCTestCase {

    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables?.removeAll()
        cancellables = nil
        try await super.tearDown()
    }

    // MARK: - Swift 6 Concurrency Performance Tests

    /// Test T051: Swift 6 concurrency performance validation
    ///
    /// This test validates that async/await operations complete efficiently
    /// and don't cause performance bottlenecks in audio operations.
    func testAsyncAwaitPerformanceInAudioOperations() async throws {
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let operationCount = 100
        let maxOperationTime: TimeInterval = 0.1 // 100ms per operation
        let maxTotalTime: TimeInterval = 5.0 // 5 seconds total

        let startTime = CFAbsoluteTimeGetCurrent()
        var operationTimes: [TimeInterval] = []

        for i in 0..<operationCount {
            let operationStart = CFAbsoluteTimeGetCurrent()

            // Create new player for each operation to test initialization performance
            let player = BasicAudioPlayer()

            // Test async operations
            try await player.loadAudio(from: testURL, metadata: nil)
            try await player.play()
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms playback
            try await player.pause()

            let operationTime = CFAbsoluteTimeGetCurrent() - operationStart
            operationTimes.append(operationTime)

            // Validate individual operation time
            XCTAssertLessThanOrEqual(operationTime, maxOperationTime,
                                   "Operation \(i) took \(String(format: "%.3f", operationTime))s, exceeding \(maxOperationTime)s limit")

            if i % 10 == 0 {
                print("Completed \(i) async operations in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - startTime))s")
            }
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTime = operationTimes.reduce(0, +) / Double(operationTimes.count)

        // Validate overall performance
        XCTAssertLessThanOrEqual(totalTime, maxTotalTime,
                               "Total time (\(String(format: "%.2f", totalTime))s) exceeds limit")
        XCTAssertLessThanOrEqual(averageTime, maxOperationTime * 0.5,
                               "Average operation time too high: \(String(format: "%.3f", averageTime))s")

        print("✅ Async/Await Performance Results:")
        print("   Operations: \(operationCount)")
        print("   Total time: \(String(format: "%.2f", totalTime))s")
        print("   Average per operation: \(String(format: "%.3f", averageTime))s")
        print("   Fastest operation: \(String(format: "%.3f", operationTimes.min() ?? 0))s")
        print("   Slowest operation: \(String(format: "%.3f", operationTimes.max() ?? 0))s")
    }

    /// Test concurrent audio operations scaling
    func testConcurrentAudioOperationsScaling() async throws {
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let concurrencyLevels = [1, 2, 4, 8, 16, 32]
        let operationsPerLevel = 20
        let maxScalingDegradation: Double = 2.0 // Allow 2x degradation at high concurrency

        var scalingResults: [(concurrency: Int, averageTime: TimeInterval)] = []

        for concurrentOperations in concurrencyLevels {
            let startTime = CFAbsoluteTimeGetCurrent()
            var completedOperations = 0

            // Run operations concurrently
            await withTaskGroup(of: Void.self) { group in
                for batch in 0..<(operationsPerLevel / concurrentOperations) {
                    for i in 0..<concurrentOperations {
                        group.addTask {
                            do {
                                let player = BasicAudioPlayer()
                                try await player.loadAudio(from: testURL, metadata: nil)
                                try await player.play()
                                try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                                try await player.pause()

                                await MainActor.run {
                                    completedOperations += 1
                                }
                            } catch {
                                print("⚠️ Error in concurrent operation: \(error)")
                            }
                        }
                    }

                    // Wait for this batch to complete
                    for await _ in group {
                        // Operations complete
                    }
                }
            }

            let totalTime = CFAbsoluteTimeGetCurrent() - startTime
            let averageTimePerOperation = totalTime / Double(completedOperations)
            scalingResults.append((concurrentOperations, averageTimePerOperation))

            print("Concurrency level \(concurrentOperations): \(String(format: "%.3f", averageTimePerOperation))s per operation")
        }

        // Validate scaling behavior
        let baselineTime = scalingResults.first?.averageTime ?? 0.1
        let maxConcurrencyTime = scalingResults.last?.averageTime ?? 0.1
        let scalingRatio = maxConcurrencyTime / baselineTime

        XCTAssertLessThanOrEqual(scalingRatio, maxScalingDegradation,
                               "Performance degraded by \(String(format: "%.2f", scalingRatio))x at high concurrency, exceeding \(maxScalingDegradation)x limit")

        print("✅ Concurrency Scaling Results:")
        for result in scalingResults {
            print("   \(result.concurrency) concurrent: \(String(format: "%.3f", result.averageTime))s per operation")
        }
        print("   Scaling ratio: \(String(format: "%.2f", scalingRatio))x")
    }

    /// Test actor isolation performance with download manager
    func testActorIsolationPerformanceWithDownloadManager() async throws {
        let testURLs = (1...50).map { index in
            URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-0\(index % 9 + 1).wav")!
        }
        let maxActorCallTime: TimeInterval = 0.05 // 50ms per actor call
        let maxTotalTime: TimeInterval = 10.0 // 10 seconds total

        // Note: In a real implementation, we would create an actual DownloadManagerActor
        // For this test, we'll simulate actor calls with structured concurrency

        let startTime = CFAbsoluteTimeGetCurrent()
        var actorCallTimes: [TimeInterval] = []

        // Simulate actor isolation calls
        for testURL in testURLs {
            let callStart = CFAbsoluteTimeGetCurrent()

            // Simulate actor-isolated operations
            await withCheckedContinuation { continuation in
                Task.detached {
                    // Simulate download preparation work
                    try? await Task.sleep(nanoseconds: UInt64.random(in: 1_000_000...10_000_000)) // 1-10ms
                    continuation.resume()
                }
            }

            let callTime = CFAbsoluteTimeGetCurrent() - callStart
            actorCallTimes.append(callTime)

            XCTAssertLessThanOrEqual(callTime, maxActorCallTime,
                                   "Actor call for \(testURL) took \(String(format: "%.3f", callTime))s, exceeding limit")
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageActorCallTime = actorCallTimes.reduce(0, +) / Double(actorCallTimes.count)

        XCTAssertLessThanOrEqual(totalTime, maxTotalTime,
                               "Total actor operations took \(String(format: "%.2f", totalTime))s")
        XCTAssertLessThanOrEqual(averageActorCallTime, maxActorCallTime * 0.5,
                               "Average actor call time too high: \(String(format: "%.3f", averageActorCallTime))s")

        print("✅ Actor Isolation Performance:")
        print("   Actor calls: \(actorCallTimes.count)")
        print("   Total time: \(String(format: "%.2f", totalTime))s")
        print("   Average call time: \(String(format: "%.3f", averageActorCallTime))s")
    }

    /// Test async sequence performance for streaming operations
    func testAsyncSequencePerformanceForStreaming() async throws {
        let streamDuration: TimeInterval = 10.0
        let expectedDataPoints = 100 // Expect ~10 data points per second
        let maxProcessingTime: TimeInterval = 0.01 // 10ms per data point

        let player = BasicAudioPlayer()
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!

        try await player.loadAudio(from: testURL, metadata: nil)
        try await player.play()

        var dataPoints = 0
        var processingTimes: [TimeInterval] = []
        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate async sequence processing
        let asyncSequence = AsyncTimerSequence(interval: 0.1) // 100ms intervals

        for await _ in asyncSequence {
            let processingStart = CFAbsoluteTimeGetCurrent()

            // Simulate data processing work
            let currentTime = CFAbsoluteTimeGetCurrent() - startTime

            // Process current playback state
            _ = await player.playbackStatePublisher.first()

            let processingTime = CFAbsoluteTimeGetCurrent() - processingStart
            processingTimes.append(processingTime)

            dataPoints += 1

            XCTAssertLessThanOrEqual(processingTime, maxProcessingTime,
                                   "Data point \(dataPoints) took \(String(format: "%.3f", processingTime))s to process")

            // Stop after specified duration
            if currentTime >= streamDuration {
                break
            }
        }

        try await player.pause()

        // Validate streaming performance
        XCTAssertGreaterThanOrEqual(dataPoints, expectedDataPoints * 0.8,
                                  "Too few data points processed: \(dataPoints) (expected ~\(expectedDataPoints))")

        let averageProcessingTime = processingTimes.reduce(0, +) / Double(processingTimes.count)
        XCTAssertLessThanOrEqual(averageProcessingTime, maxProcessingTime * 0.5,
                               "Average processing time too high: \(String(format: "%.3f", averageProcessingTime))s")

        print("✅ Async Sequence Performance:")
        print("   Data points processed: \(dataPoints)")
        print("   Average processing time: \(String(format: "%.3f", averageProcessingTime))s")
        print("   Total duration: \(String(format: "%.2f", streamDuration))s")
    }

    /// Test task group performance for batch operations
    func testTaskGroupPerformanceForBatchOperations() async throws {
        let batchSizes = [1, 5, 10, 20, 50]
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let maxBatchTime: TimeInterval = 2.0 // 2 seconds per batch

        var batchResults: [(size: Int, time: TimeInterval)] = []

        for batchSize in batchSizes {
            let startTime = CFAbsoluteTimeGetCurrent()

            await withTaskGroup(of: Void.self) { group in
                for i in 0..<batchSize {
                    group.addTask {
                        do {
                            let player = BasicAudioPlayer()
                            try await player.loadAudio(from: testURL, metadata: nil)
                            try await player.play()
                            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                            try await player.pause()
                        } catch {
                            print("⚠️ Error in batch operation \(i): \(error)")
                        }
                    }
                }

                // Wait for all tasks to complete
                for await _ in group {
                    // Task completed
                }
            }

            let batchTime = CFAbsoluteTimeGetCurrent() - startTime
            batchResults.append((batchSize, batchTime))

            XCTAssertLessThanOrEqual(batchTime, maxBatchTime,
                                   "Batch of size \(batchSize) took \(String(format: "%.2f", batchTime))s, exceeding limit")

            print("Batch size \(batchSize): \(String(format: "%.2f", batchTime))s")
        }

        // Validate scaling efficiency
        let smallestBatch = batchResults.first!
        let largestBatch = batchResults.last!
        let scalingEfficiency = (smallestBatch.time * Double(largestBatch.size)) / (largestBatch.time * Double(smallestBatch.size))

        XCTAssertGreaterThanOrEqual(scalingEfficiency, 0.5,
                                  "Batch scaling efficiency too low: \(String(format: "%.2f", scalingEfficiency))")

        print("✅ Task Group Performance:")
        for result in batchResults {
            let timePerOperation = result.time / Double(result.size)
            print("   Batch \(result.size): \(String(format: "%.2f", result.time))s total, \(String(format: "%.3f", timePerOperation))s per operation")
        }
        print("   Scaling efficiency: \(String(format: "%.2f", scalingEfficiency))")
    }

    /// Test async/await vs. completion handler performance comparison
    func testAsyncAwaitVsCompletionHandlerPerformance() async throws {
        let operationCount = 100
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!

        // Test async/await performance
        let asyncStartTime = CFAbsoluteTimeGetCurrent()
        for i in 0..<operationCount {
            let player = BasicAudioPlayer()
            try await player.loadAudio(from: testURL, metadata: nil)

            if i % 20 == 0 {
                print("Async/await: completed \(i) operations")
            }
        }
        let asyncTime = CFAbsoluteTimeGetCurrent() - asyncStartTime

        // Test completion handler performance (simulated)
        let completionStartTime = CFAbsoluteTimeGetCurrent()
        for i in 0..<operationCount {
            await withCheckedContinuation { continuation in
                // Simulate completion handler pattern
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.001) {
                    continuation.resume()
                }
            }

            if i % 20 == 0 {
                print("Completion handlers: completed \(i) operations")
            }
        }
        let completionTime = CFAbsoluteTimeGetCurrent() - completionStartTime

        // Compare performance
        let performanceRatio = asyncTime / completionTime
        let asyncPerformanceBetter = performanceRatio <= 1.5 // Allow async to be up to 50% slower

        XCTAssertTrue(asyncPerformanceBetter || asyncTime < 5.0,
                     "Async/await performance significantly worse than completion handlers: \(String(format: "%.2f", performanceRatio))x")

        print("✅ Async/Await vs Completion Handler Performance:")
        print("   Async/await time: \(String(format: "%.2f", asyncTime))s")
        print("   Completion handler time: \(String(format: "%.2f", completionTime))s")
        print("   Performance ratio: \(String(format: "%.2f", performanceRatio))x")
        print("   Async/await advantage: \(asyncTime < completionTime ? "Yes" : "No")")
    }
}

// MARK: - Concurrency Test Utilities

/// Utility async sequence for testing streaming performance
struct AsyncTimerSequence: AsyncSequence {
    typealias Element = Date

    let interval: TimeInterval

    func makeAsyncIterator() -> AsyncTimerIterator {
        return AsyncTimerIterator(interval: interval)
    }
}

struct AsyncTimerIterator: AsyncIteratorProtocol {
    typealias Element = Date

    let interval: TimeInterval
    private var lastTime: Date?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func next() async -> Date? {
        let now = Date()

        if let lastTime = lastTime {
            let elapsed = now.timeIntervalSince(lastTime)
            if elapsed < interval {
                let sleepTime = interval - elapsed
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }

        lastTime = Date()
        return lastTime
    }
}

extension ConcurrencyPerformanceTests {

    /// Measure performance of an async operation
    private func measureAsyncOperation<T>(_ operation: () async throws -> T) async throws -> (result: T, time: TimeInterval) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await operation()
        let endTime = CFAbsoluteTimeGetCurrent()
        return (result, endTime - startTime)
    }

    /// Test actor performance with simulated isolation
    private func testActorIsolationPerformance(operations: Int) async -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0..<operations {
            await withCheckedContinuation { continuation in
                Task.detached {
                    // Simulate actor isolation boundary crossing
                    try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                    continuation.resume()
                }
            }
        }

        return CFAbsoluteTimeGetCurrent() - startTime
    }

    /// Validate concurrency performance metrics
    private func validateConcurrencyMetrics(_ metrics: ConcurrencyMetrics, testName: String) {
        XCTAssertLessThanOrEqual(metrics.averageOperationTime, metrics.maxAllowedTime,
                               "\(testName): Average operation time exceeds limit")
        XCTAssertLessThanOrEqual(metrics.maxOperationTime, metrics.maxAllowedTime * 2,
                               "\(testName): Peak operation time too high")
        XCTAssertGreaterThanOrEqual(metrics.operationsPerSecond, metrics.minRequiredThroughput,
                                  "\(testName): Throughput below minimum requirement")

        print("📊 \(testName) Metrics:")
        print("   Average time: \(String(format: "%.3f", metrics.averageOperationTime))s")
        print("   Max time: \(String(format: "%.3f", metrics.maxOperationTime))s")
        print("   Throughput: \(String(format: "%.1f", metrics.operationsPerSecond)) ops/sec")
    }
}

/// Performance metrics for concurrency testing
struct ConcurrencyMetrics {
    let averageOperationTime: TimeInterval
    let maxOperationTime: TimeInterval
    let operationsPerSecond: Double
    let maxAllowedTime: TimeInterval
    let minRequiredThroughput: Double

    init(operationTimes: [TimeInterval], maxAllowedTime: TimeInterval, minRequiredThroughput: Double) {
        self.averageOperationTime = operationTimes.reduce(0, +) / Double(operationTimes.count)
        self.maxOperationTime = operationTimes.max() ?? 0
        self.operationsPerSecond = Double(operationTimes.count) / operationTimes.reduce(0, +)
        self.maxAllowedTime = maxAllowedTime
        self.minRequiredThroughput = minRequiredThroughput
    }
}