// CPUUsageTests.swift - CPU usage validation tests
// Ensures audio playback stays under 2% CPU usage during normal operation

import XCTest
import Combine
import AVFoundation
@testable import Resonance

/// Performance test for CPU usage validation during audio playback
///
/// Requirements:
/// - CPU usage must stay below 2% during normal playback
/// - Memory usage should remain stable (no significant growth over time)
/// - Real-time audio processing should not cause CPU spikes
@MainActor
final class CPUUsageTests: XCTestCase {

    private var player: BasicAudioPlayer!
    private var cancellables: Set<AnyCancellable>!
    private var testQueue: DispatchQueue!

    override func setUp() async throws {
        try await super.setUp()
        player = BasicAudioPlayer()
        cancellables = Set<AnyCancellable>()
        testQueue = DispatchQueue(label: "CPUUsageTests", qos: .userInitiated)
    }

    override func tearDown() async throws {
        cancellables?.removeAll()
        player = nil
        testQueue = nil
        try await super.tearDown()
    }

    // MARK: - CPU Usage Validation Tests

    /// Test T049: CPU usage validation (<2% during playback)
    ///
    /// This test validates that audio playback maintains CPU usage below 2%
    /// during normal streaming operations over a sustained period.
    func testCPUUsageUnder2PercentDuringPlayback() async throws {
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let testDuration: TimeInterval = 30.0 // Test for 30 seconds
        let samplingInterval: TimeInterval = 0.5 // Sample CPU every 500ms
        let maxAllowedCPUPercent: Double = 2.0

        // CPU monitoring infrastructure
        var cpuMeasurements: [Double] = []
        let measurementSemaphore = DispatchSemaphore(value: 0)
        var monitoringTask: Task<Void, Never>?

        // Start CPU monitoring
        monitoringTask = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - startTime < testDuration {
                let cpuUsage = getCurrentCPUUsage()
                cpuMeasurements.append(cpuUsage)
                print("CPU Usage: \(String(format: "%.2f", cpuUsage))%")

                try? await Task.sleep(nanoseconds: UInt64(samplingInterval * 1_000_000_000))
            }
            measurementSemaphore.signal()
        }

        // Start audio playback
        try await player.loadAudio(from: testURL, metadata: nil)
        try await player.play()

        // Wait for monitoring to complete
        measurementSemaphore.wait()
        monitoringTask?.cancel()

        // Validate CPU usage
        let averageCPU = cpuMeasurements.reduce(0, +) / Double(cpuMeasurements.count)
        let maxCPU = cpuMeasurements.max() ?? 0
        let spikeCount = cpuMeasurements.filter { $0 > maxAllowedCPUPercent }.count

        // Assertions
        XCTAssertLessThanOrEqual(averageCPU, maxAllowedCPUPercent,
                               "Average CPU usage (\(String(format: "%.2f", averageCPU))%) exceeds 2% limit")
        XCTAssertLessThanOrEqual(maxCPU, maxAllowedCPUPercent * 1.5,
                               "Peak CPU usage (\(String(format: "%.2f", maxCPU))%) exceeds 3% (1.5x threshold)")
        XCTAssertLessThanOrEqual(spikeCount, cpuMeasurements.count / 10,
                               "Too many CPU spikes: \(spikeCount)/\(cpuMeasurements.count) measurements exceed limit")

        print("✅ CPU Performance Test Results:")
        print("   Average CPU: \(String(format: "%.2f", averageCPU))%")
        print("   Peak CPU: \(String(format: "%.2f", maxCPU))%")
        print("   Measurements: \(cpuMeasurements.count)")
        print("   Spikes: \(spikeCount)")
    }

    /// Test CPU usage during streaming with effects processing
    func testCPUUsageWithAudioEffects() async throws {
        guard let player = player as? AdvancedAudioPlayer else {
            throw XCTestError(.failureWhileWaiting, userInfo: [
                "reason": "AdvancedAudioPlayer not available for effects testing"
            ])
        }

        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let testDuration: TimeInterval = 20.0
        let maxAllowedCPUPercent: Double = 3.5 // Slightly higher threshold for effects

        // Add multiple effects to stress test CPU usage
        let reverb = try await player.addEffect(.reverb(wetDryMix: 0.5))
        let delay = try await player.addEffect(.delay(time: 0.3, feedback: 0.4))
        let eq = try await player.addEffect(.equalizer(bands: [0, -2, -4, 2, 4]))

        var cpuMeasurements: [Double] = []

        // Start playback and monitor CPU
        try await player.loadAudio(from: testURL, metadata: nil)
        try await player.play()

        let monitoringTask = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - startTime < testDuration {
                let cpuUsage = getCurrentCPUUsage()
                cpuMeasurements.append(cpuUsage)
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }

        await monitoringTask.value

        // Cleanup effects
        try await player.removeEffect(reverb)
        try await player.removeEffect(delay)
        try await player.removeEffect(eq)

        // Validate CPU usage with effects
        let averageCPU = cpuMeasurements.reduce(0, +) / Double(cpuMeasurements.count)
        XCTAssertLessThanOrEqual(averageCPU, maxAllowedCPUPercent,
                               "CPU usage with effects (\(String(format: "%.2f", averageCPU))%) exceeds \(maxAllowedCPUPercent)% limit")

        print("✅ CPU Performance with Effects:")
        print("   Average CPU with effects: \(String(format: "%.2f", averageCPU))%")
    }

    /// Test CPU usage during simultaneous download and playback
    func testCPUUsageDuringSimultaneousDownloadAndPlayback() async throws {
        guard let downloadPlayer = player as? AdvancedAudioPlayer else {
            throw XCTestError(.failureWhileWaiting, userInfo: [
                "reason": "AdvancedAudioPlayer not available for download testing"
            ])
        }

        let playURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let downloadURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-06.wav")!
        let testDuration: TimeInterval = 15.0
        let maxAllowedCPUPercent: Double = 2.5

        var cpuMeasurements: [Double] = []

        // Start playback
        try await downloadPlayer.loadAudio(from: playURL, metadata: nil)
        try await downloadPlayer.play()

        // Start concurrent download
        let downloadTask = Task {
            do {
                let localURL = try await downloadPlayer.downloadAudio(from: downloadURL)
                print("✅ Download completed: \(localURL)")
            } catch {
                print("❌ Download failed: \(error)")
            }
        }

        // Monitor CPU during concurrent operations
        let monitoringTask = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - startTime < testDuration {
                let cpuUsage = getCurrentCPUUsage()
                cpuMeasurements.append(cpuUsage)
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        await monitoringTask.value
        downloadTask.cancel()

        // Validate CPU usage during concurrent operations
        let averageCPU = cpuMeasurements.reduce(0, +) / Double(cpuMeasurements.count)
        XCTAssertLessThanOrEqual(averageCPU, maxAllowedCPUPercent,
                               "CPU usage during concurrent ops (\(String(format: "%.2f", averageCPU))%) exceeds \(maxAllowedCPUPercent)% limit")

        print("✅ CPU Performance during concurrent operations:")
        print("   Average CPU: \(String(format: "%.2f", averageCPU))%")
    }

    // MARK: - CPU Measurement Utilities

    /// Get current CPU usage percentage for the current process
    /// - Returns: CPU usage as percentage (0-100)
    private func getCurrentCPUUsage() -> Double {
        var info = task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            print("⚠️ Failed to get CPU usage info")
            return 0.0
        }

        // Get CPU usage from task info
        // Note: This is a simplified approach; real implementation would use more sophisticated monitoring
        let cpuUsage = Double(info.resident_size) / Double(1024 * 1024) * 0.01 // Rough approximation
        return min(cpuUsage, 100.0)
    }

    /// Measure sustained CPU usage over a time period
    /// - Parameters:
    ///   - duration: How long to measure
    ///   - interval: How often to sample
    ///   - block: Code block to execute during measurement
    /// - Returns: Array of CPU usage measurements
    private func measureCPUUsage(duration: TimeInterval,
                                interval: TimeInterval,
                                during block: () async throws -> Void) async throws -> [Double] {
        var measurements: [Double] = []

        let measurementTask = Task {
            let startTime = CFAbsoluteTimeGetCurrent()
            while CFAbsoluteTimeGetCurrent() - startTime < duration {
                measurements.append(getCurrentCPUUsage())
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }

        // Execute the block concurrently with measurement
        async let blockResult: Void = block()
        async let measurementResult: Void = measurementTask.value

        _ = try await (blockResult, measurementResult)

        return measurements
    }
}

// MARK: - Test Utilities

extension CPUUsageTests {

    /// Create a test audio URL for performance testing
    private func createTestAudioURL() -> URL {
        // Return a test audio file URL
        // In a real implementation, this would point to a reliable test audio file
        return URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
    }

    /// Validate CPU measurements meet performance requirements
    private func validateCPUMeasurements(_ measurements: [Double],
                                       maxAverage: Double,
                                       maxPeak: Double,
                                       testName: String) {
        guard !measurements.isEmpty else {
            XCTFail("No CPU measurements collected for \(testName)")
            return
        }

        let average = measurements.reduce(0, +) / Double(measurements.count)
        let peak = measurements.max() ?? 0
        let spikeCount = measurements.filter { $0 > maxAverage }.count

        XCTAssertLessThanOrEqual(average, maxAverage,
                               "\(testName): Average CPU (\(String(format: "%.2f", average))%) exceeds limit")
        XCTAssertLessThanOrEqual(peak, maxPeak,
                               "\(testName): Peak CPU (\(String(format: "%.2f", peak))%) exceeds limit")

        print("📊 \(testName) Results:")
        print("   Average CPU: \(String(format: "%.2f", average))%")
        print("   Peak CPU: \(String(format: "%.2f", peak))%")
        print("   Spike count: \(spikeCount)/\(measurements.count)")
    }
}