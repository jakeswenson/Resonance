// MemoryLeakTests.swift - Memory leak detection for reactive streams
// Ensures Combine publishers and audio streams don't cause memory leaks

import XCTest
import Combine
import AVFoundation
@testable import Resonance

/// Performance test for memory leak detection in reactive streams
///
/// Requirements:
/// - No memory leaks in Combine publisher chains
/// - Proper cleanup of audio stream resources
/// - Memory usage should stabilize after operations
/// - AnyCancellables should be properly stored and released
@MainActor
final class MemoryLeakTests: XCTestCase {

    private var cancellables: Set<AnyCancellable>!
    private var initialMemoryUsage: UInt64 = 0

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()

        // Record initial memory usage
        initialMemoryUsage = getCurrentMemoryUsage()

        // Allow memory to stabilize
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    }

    override func tearDown() async throws {
        // Cancel all subscriptions
        cancellables?.removeAll()
        cancellables = nil

        // Force garbage collection
        autoreleasepool {}

        // Give time for cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        try await super.tearDown()
    }

    // MARK: - Memory Leak Tests

    /// Test T050: Memory leak detection for reactive streams
    ///
    /// This test validates that Combine publishers and reactive streams
    /// don't cause memory leaks during normal operation cycles.
    func testNoMemoryLeaksInReactiveStreams() async throws {
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let cycleCount = 50
        let memoryGrowthThreshold: UInt64 = 10 * 1024 * 1024 // 10MB

        var memoryMeasurements: [UInt64] = []

        for cycle in 0..<cycleCount {
            let player = BasicAudioPlayer()
            var localCancellables = Set<AnyCancellable>()

            // Set up multiple reactive subscriptions
            player.playbackStatePublisher
                .sink { state in
                    // Simulate UI updates
                    _ = state
                }
                .store(in: &localCancellables)

            // Load and play audio
            try await player.loadAudio(from: testURL, metadata: nil)
            try await player.play()

            // Brief playback period
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Stop playback
            try await player.pause()

            // Cleanup subscriptions
            localCancellables.removeAll()

            // Measure memory every 10 cycles
            if cycle % 10 == 0 {
                // Force garbage collection
                autoreleasepool {}
                try await Task.sleep(nanoseconds: 50_000_000) // 50ms

                let currentMemory = getCurrentMemoryUsage()
                memoryMeasurements.append(currentMemory)

                print("Cycle \(cycle): Memory usage: \(formatMemorySize(currentMemory))")
            }
        }

        // Analyze memory growth
        let finalMemory = getCurrentMemoryUsage()
        let memoryGrowth = finalMemory > initialMemoryUsage ? finalMemory - initialMemoryUsage : 0

        XCTAssertLessThanOrEqual(memoryGrowth, memoryGrowthThreshold,
                               "Memory grew by \(formatMemorySize(memoryGrowth)), exceeding \(formatMemorySize(memoryGrowthThreshold)) threshold")

        // Check for continuous memory growth
        let growthTrend = analyzeMemoryGrowthTrend(memoryMeasurements)
        XCTAssertLessThanOrEqual(growthTrend, 0.1,
                               "Memory shows continuous growth trend: \(String(format: "%.2f", growthTrend * 100))%")

        print("✅ Memory Leak Test Results:")
        print("   Initial memory: \(formatMemorySize(initialMemoryUsage))")
        print("   Final memory: \(formatMemorySize(finalMemory))")
        print("   Growth: \(formatMemorySize(memoryGrowth))")
        print("   Growth trend: \(String(format: "%.2f", growthTrend * 100))%")
    }

    /// Test memory leaks with concurrent publisher subscriptions
    func testNoMemoryLeaksWithConcurrentSubscriptions() async throws {
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let subscriptionCount = 100
        let memoryGrowthThreshold: UInt64 = 5 * 1024 * 1024 // 5MB

        let player = BasicAudioPlayer()
        var subscriptionCancellables: [AnyCancellable] = []

        let startMemory = getCurrentMemoryUsage()

        // Create many concurrent subscriptions
        for i in 0..<subscriptionCount {
            let cancellable = player.playbackStatePublisher
                .map { state in
                    // Simulate processing
                    return "Subscription \(i): \(state)"
                }
                .sink { _ in
                    // Consume the result
                }

            subscriptionCancellables.append(cancellable)
        }

        // Start playback to trigger all subscriptions
        try await player.loadAudio(from: testURL, metadata: nil)
        try await player.play()

        // Let subscriptions run
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        let memoryWithSubscriptions = getCurrentMemoryUsage()

        // Cancel all subscriptions
        subscriptionCancellables.removeAll()

        // Force cleanup
        autoreleasepool {}
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        let memoryAfterCleanup = getCurrentMemoryUsage()

        // Validate memory cleanup
        let memoryDifference = memoryAfterCleanup > startMemory ? memoryAfterCleanup - startMemory : 0

        XCTAssertLessThanOrEqual(memoryDifference, memoryGrowthThreshold,
                               "Memory not properly cleaned up after subscription removal. Difference: \(formatMemorySize(memoryDifference))")

        print("✅ Concurrent Subscriptions Test:")
        print("   Start memory: \(formatMemorySize(startMemory))")
        print("   With subscriptions: \(formatMemorySize(memoryWithSubscriptions))")
        print("   After cleanup: \(formatMemorySize(memoryAfterCleanup))")
        print("   Net difference: \(formatMemorySize(memoryDifference))")
    }

    /// Test memory leaks with advanced audio player features
    func testNoMemoryLeaksWithAdvancedFeatures() async throws {
        guard let advancedPlayer = AdvancedAudioPlayer() as? AdvancedAudioPlayer else {
            throw XCTestError(.failureWhileWaiting)
        }

        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let iterationCount = 20
        let memoryGrowthThreshold: UInt64 = 8 * 1024 * 1024 // 8MB

        let startMemory = getCurrentMemoryUsage()
        var memoryMeasurements: [UInt64] = []

        for iteration in 0..<iterationCount {
            var localCancellables = Set<AnyCancellable>()

            // Set up multiple publisher subscriptions
            advancedPlayer.playbackStatePublisher
                .combineLatest(advancedPlayer.downloadProgressPublisher)
                .map { state, progress in
                    return "State: \(state), Progress: \(progress)"
                }
                .sink { _ in }
                .store(in: &localCancellables)

            // Add and remove effects
            let reverb = try await advancedPlayer.addEffect(.reverb(wetDryMix: 0.5))
            let delay = try await advancedPlayer.addEffect(.delay(time: 0.3, feedback: 0.4))

            // Queue operations
            try await advancedPlayer.addToQueue(testURL, metadata: nil)
            try await advancedPlayer.removeFromQueue(at: 0)

            // Load and play audio
            try await advancedPlayer.loadAudio(from: testURL, metadata: nil)
            try await advancedPlayer.play()

            // Brief playback
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms

            try await advancedPlayer.pause()

            // Remove effects
            try await advancedPlayer.removeEffect(reverb)
            try await advancedPlayer.removeEffect(delay)

            // Cleanup subscriptions
            localCancellables.removeAll()

            // Measure memory every few iterations
            if iteration % 5 == 0 {
                autoreleasepool {}
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms

                let currentMemory = getCurrentMemoryUsage()
                memoryMeasurements.append(currentMemory)

                print("Advanced features iteration \(iteration): \(formatMemorySize(currentMemory))")
            }
        }

        let finalMemory = getCurrentMemoryUsage()
        let memoryGrowth = finalMemory > startMemory ? finalMemory - startMemory : 0

        XCTAssertLessThanOrEqual(memoryGrowth, memoryGrowthThreshold,
                               "Advanced features caused memory growth of \(formatMemorySize(memoryGrowth))")

        // Check for continuous growth
        let growthTrend = analyzeMemoryGrowthTrend(memoryMeasurements)
        XCTAssertLessThanOrEqual(growthTrend, 0.15,
                               "Memory shows concerning growth trend: \(String(format: "%.2f", growthTrend * 100))%")

        print("✅ Advanced Features Memory Test:")
        print("   Memory growth: \(formatMemorySize(memoryGrowth))")
        print("   Growth trend: \(String(format: "%.2f", growthTrend * 100))%")
    }

    /// Test memory stability during long-running operations
    func testMemoryStabilityDuringLongRunningOperations() async throws {
        let player = BasicAudioPlayer()
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let testDuration: TimeInterval = 60.0 // 1 minute
        let samplingInterval: TimeInterval = 5.0 // Sample every 5 seconds
        let maxMemoryVariation: Double = 0.20 // 20% variation allowed

        var memoryMeasurements: [UInt64] = []
        let startTime = CFAbsoluteTimeGetCurrent()

        // Set up subscription that runs for the entire test
        player.playbackStatePublisher
            .sink { state in
                // Simulate continuous processing
                _ = String(describing: state)
            }
            .store(in: &cancellables)

        // Start playback
        try await player.loadAudio(from: testURL, metadata: nil)
        try await player.play()

        // Monitor memory over time
        let monitoringTask = Task {
            while CFAbsoluteTimeGetCurrent() - startTime < testDuration {
                autoreleasepool {}
                let currentMemory = getCurrentMemoryUsage()
                memoryMeasurements.append(currentMemory)

                print("Long-running test: \(formatMemorySize(currentMemory)) at \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - startTime))s")

                try? await Task.sleep(nanoseconds: UInt64(samplingInterval * 1_000_000_000))
            }
        }

        await monitoringTask.value

        // Analyze memory stability
        guard !memoryMeasurements.isEmpty else {
            XCTFail("No memory measurements collected")
            return
        }

        let minMemory = memoryMeasurements.min()!
        let maxMemory = memoryMeasurements.max()!
        let averageMemory = memoryMeasurements.reduce(0, +) / UInt64(memoryMeasurements.count)
        let variation = Double(maxMemory - minMemory) / Double(averageMemory)

        XCTAssertLessThanOrEqual(variation, maxMemoryVariation,
                               "Memory variation (\(String(format: "%.2f", variation * 100))%) exceeds \(String(format: "%.0f", maxMemoryVariation * 100))% threshold")

        print("✅ Long-running Memory Stability:")
        print("   Min memory: \(formatMemorySize(minMemory))")
        print("   Max memory: \(formatMemorySize(maxMemory))")
        print("   Average: \(formatMemorySize(averageMemory))")
        print("   Variation: \(String(format: "%.2f", variation * 100))%")
    }

    // MARK: - Memory Measurement Utilities

    /// Get current memory usage for the process
    /// - Returns: Memory usage in bytes
    private func getCurrentMemoryUsage() -> UInt64 {
        var info = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            print("⚠️ Failed to get memory usage info")
            return 0
        }

        return UInt64(info.resident_size)
    }

    /// Format memory size for human-readable output
    /// - Parameter bytes: Memory size in bytes
    /// - Returns: Formatted string (e.g., "4.2 MB")
    private func formatMemorySize(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .decimal
        return formatter.string(fromByteCount: Int64(bytes))
    }

    /// Analyze memory growth trend across measurements
    /// - Parameter measurements: Array of memory measurements
    /// - Returns: Growth trend as ratio (0 = no growth, 1 = 100% growth)
    private func analyzeMemoryGrowthTrend(_ measurements: [UInt64]) -> Double {
        guard measurements.count >= 2 else { return 0.0 }

        let firstMeasurement = measurements.first!
        let lastMeasurement = measurements.last!

        if firstMeasurement == 0 { return 0.0 }

        let growth = lastMeasurement > firstMeasurement ? lastMeasurement - firstMeasurement : 0
        return Double(growth) / Double(firstMeasurement)
    }

    /// Check if memory usage is stable (no continuous growth)
    /// - Parameter measurements: Array of memory measurements
    /// - Returns: True if memory usage is considered stable
    private func isMemoryUsageStable(_ measurements: [UInt64]) -> Bool {
        guard measurements.count >= 3 else { return true }

        let windowSize = min(5, measurements.count / 3)
        let firstWindow = Array(measurements.prefix(windowSize))
        let lastWindow = Array(measurements.suffix(windowSize))

        let firstAverage = firstWindow.reduce(0, +) / UInt64(firstWindow.count)
        let lastAverage = lastWindow.reduce(0, +) / UInt64(lastWindow.count)

        let growthRatio = Double(lastAverage) / Double(firstAverage)
        return growthRatio < 1.1 // Less than 10% growth is considered stable
    }
}

// MARK: - Memory Test Utilities

extension MemoryLeakTests {

    /// Stress test memory with rapid allocation/deallocation cycles
    private func performMemoryStressTest(cycles: Int, operation: () async throws -> Void) async throws -> [UInt64] {
        var measurements: [UInt64] = []

        for cycle in 0..<cycles {
            autoreleasepool {
                // Perform operation in autorelease pool
                Task {
                    do {
                        try await operation()
                    } catch {
                        print("⚠️ Error in memory stress test cycle \(cycle): \(error)")
                    }
                }
            }

            if cycle % 10 == 0 {
                // Force garbage collection and measure
                autoreleasepool {}
                let memory = getCurrentMemoryUsage()
                measurements.append(memory)

                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }

        return measurements
    }

    /// Validate that memory cleanup occurs after operations
    private func validateMemoryCleanup(beforeOperation: UInt64,
                                     afterOperation: UInt64,
                                     afterCleanup: UInt64,
                                     threshold: UInt64,
                                     testName: String) {
        let netGrowth = afterCleanup > beforeOperation ? afterCleanup - beforeOperation : 0

        XCTAssertLessThanOrEqual(netGrowth, threshold,
                               "\(testName): Memory not properly cleaned up. Net growth: \(formatMemorySize(netGrowth))")

        print("🧹 \(testName) Cleanup Validation:")
        print("   Before: \(formatMemorySize(beforeOperation))")
        print("   After operation: \(formatMemorySize(afterOperation))")
        print("   After cleanup: \(formatMemorySize(afterCleanup))")
        print("   Net growth: \(formatMemorySize(netGrowth))")
    }
}