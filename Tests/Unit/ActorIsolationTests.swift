// ActorIsolationTests.swift - Actor isolation and thread safety tests
// Validates proper actor boundaries and data race prevention

import XCTest
import Combine
import AVFoundation
@testable import Resonance

/// Unit tests for actor isolation and thread safety
///
/// Requirements:
/// - Actors must properly isolate mutable state
/// - No data races should occur under concurrent access
/// - Actor boundaries should be respected
/// - Sendable types should be used correctly
@MainActor
final class ActorIsolationTests: XCTestCase {

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

    // MARK: - Actor Isolation Tests

    /// Test T052: Unit tests for actor isolation and thread safety
    ///
    /// This test validates that actors properly isolate mutable state
    /// and prevent data races during concurrent operations.
    func testActorIsolationPreventsDataRaces() async throws {
        let concurrentOperations = 100
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!

        // Create a test actor to validate isolation
        let testActor = TestAudioActor()

        // Perform concurrent operations that would cause data races without proper isolation
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrentOperations {
                group.addTask {
                    await testActor.performAudioOperation(id: i, url: testURL)
                }
            }

            // Wait for all operations to complete
            for await _ in group {
                // Operation completed
            }
        }

        // Validate that all operations completed without data races
        let operationCount = await testActor.getOperationCount()
        let errors = await testActor.getErrors()

        XCTAssertEqual(operationCount, concurrentOperations,
                      "Expected \(concurrentOperations) operations, but got \(operationCount)")
        XCTAssertTrue(errors.isEmpty,
                     "Actor isolation failed with \(errors.count) errors: \(errors)")

        print("✅ Actor Isolation Test Results:")
        print("   Concurrent operations: \(concurrentOperations)")
        print("   Successful operations: \(operationCount)")
        print("   Errors: \(errors.count)")
    }

    /// Test thread safety of reactive publishers
    func testReactivePublisherThreadSafety() async throws {
        let player = BasicAudioPlayer()
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let subscriberCount = 50
        let publishCount = 100

        var receivedValues: [String] = []
        let receivedValuesLock = NSLock()

        // Create multiple subscribers from different threads
        await withTaskGroup(of: Void.self) { group in
            // Add subscriber tasks
            for i in 0..<subscriberCount {
                group.addTask {
                    let subscription = player.playbackStatePublisher
                        .map { state in "Subscriber \(i): \(state)" }
                        .sink { value in
                            receivedValuesLock.lock()
                            receivedValues.append(value)
                            receivedValuesLock.unlock()
                        }

                    // Keep subscription alive for test duration
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    subscription.cancel()
                }
            }

            // Add publisher tasks
            for _ in 0..<publishCount {
                group.addTask {
                    do {
                        try await player.loadAudio(from: testURL, metadata: nil)
                        try await player.play()
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                        try await player.pause()
                    } catch {
                        print("⚠️ Publisher operation error: \(error)")
                    }
                }
            }

            // Wait for all tasks
            for await _ in group {
                // Task completed
            }
        }

        // Validate thread safety - should have received values without crashes
        receivedValuesLock.lock()
        let totalReceivedValues = receivedValues.count
        receivedValuesLock.unlock()

        XCTAssertGreaterThan(totalReceivedValues, 0,
                           "No values received from publishers - possible thread safety issue")

        print("✅ Reactive Publisher Thread Safety:")
        print("   Subscribers: \(subscriberCount)")
        print("   Publishers: \(publishCount)")
        print("   Values received: \(totalReceivedValues)")
    }

    /// Test Sendable conformance validation
    func testSendableConformanceValidation() async throws {
        // Test that our key types are properly Sendable
        let metadata = AudioMetadata(
            title: "Test Audio",
            artist: "Test Artist",
            album: "Test Album",
            duration: 120.0
        )

        let playbackState = PlaybackState.playing
        let audioError = AudioError.networkFailure

        // These should compile without warnings if Sendable conformance is correct
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    // Pass Sendable types across actor boundaries
                    await self.processSendableTypes(
                        metadata: metadata,
                        state: playbackState,
                        error: audioError,
                        index: i
                    )
                }
            }

            for await _ in group {
                // Task completed
            }
        }

        print("✅ Sendable Conformance Validation: All types properly sendable")
    }

    /// Test actor boundary crossing performance
    func testActorBoundaryCrossingPerformance() async throws {
        let operationCount = 1000
        let maxTimePerCrossing: TimeInterval = 0.001 // 1ms per crossing
        let testActor = TestAudioActor()

        let startTime = CFAbsoluteTimeGetCurrent()

        for i in 0..<operationCount {
            await testActor.lightweightOperation(id: i)
        }

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let averageTimePerOperation = totalTime / Double(operationCount)

        XCTAssertLessThanOrEqual(averageTimePerOperation, maxTimePerCrossing,
                               "Actor boundary crossing too slow: \(String(format: "%.4f", averageTimePerOperation))s per operation")

        print("✅ Actor Boundary Crossing Performance:")
        print("   Operations: \(operationCount)")
        print("   Total time: \(String(format: "%.3f", totalTime))s")
        print("   Average per operation: \(String(format: "%.4f", averageTimePerOperation))s")
    }

    /// Test isolated state mutation safety
    func testIsolatedStateMutationSafety() async throws {
        let testActor = TestAudioActor()
        let concurrentMutations = 1000

        // Perform concurrent state mutations
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<concurrentMutations {
                group.addTask {
                    await testActor.incrementCounter(by: 1)
                    await testActor.addToHistory(value: i)
                }
            }

            for await _ in group {
                // Mutation completed
            }
        }

        // Validate final state consistency
        let finalCounter = await testActor.getCounter()
        let historyCount = await testActor.getHistoryCount()

        XCTAssertEqual(finalCounter, concurrentMutations,
                      "Counter inconsistency: expected \(concurrentMutations), got \(finalCounter)")
        XCTAssertEqual(historyCount, concurrentMutations,
                      "History inconsistency: expected \(concurrentMutations) entries, got \(historyCount)")

        print("✅ Isolated State Mutation Safety:")
        print("   Concurrent mutations: \(concurrentMutations)")
        print("   Final counter: \(finalCounter)")
        print("   History entries: \(historyCount)")
    }

    /// Test Main Actor isolation for UI updates
    func testMainActorIsolationForUIUpdates() async throws {
        let player = BasicAudioPlayer()
        let testURL = URL(string: "https://www.soundjay.com/misc/sounds/bell-ringing-05.wav")!
        let updateCount = 50

        var uiUpdates: [MainActorUIUpdate] = []

        // Subscribe to state changes and perform UI updates
        player.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { state in
                // Verify we're on the main thread
                XCTAssertTrue(Thread.isMainThread, "UI update not on main thread")

                let update = MainActorUIUpdate(
                    timestamp: Date(),
                    state: state,
                    threadInfo: Thread.current.description
                )
                uiUpdates.append(update)
            }
            .store(in: &cancellables)

        // Trigger state changes from background threads
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<updateCount {
                group.addTask {
                    do {
                        try await player.loadAudio(from: testURL, metadata: nil)
                        try await player.play()
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                        try await player.pause()
                    } catch {
                        print("⚠️ Background playback error: \(error)")
                    }
                }
            }

            for await _ in group {
                // Background task completed
            }
        }

        // Give UI updates time to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Validate UI updates occurred on main thread
        XCTAssertGreaterThan(uiUpdates.count, 0, "No UI updates received")

        let mainThreadUpdates = uiUpdates.filter { $0.threadInfo.contains("main") }
        XCTAssertEqual(mainThreadUpdates.count, uiUpdates.count,
                      "Some UI updates not on main thread: \(uiUpdates.count - mainThreadUpdates.count)/\(uiUpdates.count)")

        print("✅ Main Actor UI Update Isolation:")
        print("   Total updates: \(uiUpdates.count)")
        print("   Main thread updates: \(mainThreadUpdates.count)")
    }

    // MARK: - Helper Methods

    /// Process Sendable types across actor boundaries
    private func processSendableTypes(metadata: AudioMetadata,
                                    state: PlaybackState,
                                    error: AudioError,
                                    index: Int) async {
        // Simulate processing Sendable types
        let processedData = ProcessedAudioData(
            metadata: metadata,
            state: state,
            error: error,
            processIndex: index,
            processTime: Date()
        )

        // Verify data integrity
        XCTAssertEqual(processedData.metadata.title, metadata.title)
        XCTAssertEqual(processedData.state, state)
        XCTAssertEqual(processedData.error, error)
        XCTAssertEqual(processedData.processIndex, index)
    }
}

// MARK: - Test Actors and Supporting Types

/// Test actor for validating isolation behavior
actor TestAudioActor {
    private var operationCount: Int = 0
    private var errors: [String] = []
    private var counter: Int = 0
    private var history: [Int] = []

    func performAudioOperation(id: Int, url: URL) async {
        // Simulate audio operation with potential race conditions
        let currentCount = operationCount

        // Simulate async work that could cause race conditions
        await Task.yield()

        // Update state - this would be unsafe without actor isolation
        operationCount = currentCount + 1

        // Simulate potential error conditions
        if id % 100 == 99 {
            // Simulate occasional errors for testing
            errors.append("Simulated error for operation \(id)")
        }
    }

    func lightweightOperation(id: Int) async {
        // Minimal operation for performance testing
        counter += 1
    }

    func incrementCounter(by amount: Int) async {
        counter += amount
    }

    func addToHistory(value: Int) async {
        history.append(value)
    }

    func getOperationCount() async -> Int {
        return operationCount
    }

    func getErrors() async -> [String] {
        return errors
    }

    func getCounter() async -> Int {
        return counter
    }

    func getHistoryCount() async -> Int {
        return history.count
    }
}

/// Sendable data structure for testing
struct ProcessedAudioData: Sendable {
    let metadata: AudioMetadata
    let state: PlaybackState
    let error: AudioError
    let processIndex: Int
    let processTime: Date
}

/// UI update record for Main Actor testing
struct MainActorUIUpdate: Sendable {
    let timestamp: Date
    let state: AudioPlaybackState
    let threadInfo: String
}

// MARK: - Thread Safety Testing Utilities

extension ActorIsolationTests {

    /// Test concurrent access to shared resources
    private func testConcurrentAccess<T>(
        resource: T,
        operationCount: Int,
        operation: (T) async -> Void
    ) async where T: Sendable {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<operationCount {
                group.addTask {
                    await operation(resource)
                }
            }

            for await _ in group {
                // Operation completed
            }
        }
    }

    /// Validate that operations maintain data consistency
    private func validateDataConsistency<T: Equatable>(
        expected: T,
        actual: T,
        context: String
    ) {
        XCTAssertEqual(expected, actual,
                      "Data consistency violation in \(context): expected \(expected), got \(actual)")
    }

    /// Measure actor performance under concurrent load
    private func measureActorPerformance(
        operationCount: Int,
        operation: () async -> Void
    ) async -> TimeInterval {
        let startTime = CFAbsoluteTimeGetCurrent()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<operationCount {
                group.addTask {
                    await operation()
                }
            }

            for await _ in group {
                // Operation completed
            }
        }

        return CFAbsoluteTimeGetCurrent() - startTime
    }
}