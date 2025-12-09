// AudioEngineAccessibleTests.swift - Contract tests for AudioEngineAccessible protocol
// These tests verify direct AVAudioEngine access capabilities

import XCTest
import Combine
import AVFoundation
@testable import Resonance

final class AudioEngineAccessibleTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioEngineAccessible!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioEngineAccessible()
    }

    override func tearDown() {
        cancellables = nil
        mockPlayer = nil
        super.tearDown()
    }

    // MARK: - Engine Access Contract Tests

    func testAudioEngineAccess() {
        // Arrange & Act
        let engine = mockPlayer.audioEngine

        // Assert
        XCTAssertNotNil(engine)
    }

    func testPlayerNodeAccess() {
        // Arrange & Act
        let playerNode = mockPlayer.playerNode

        // Assert
        XCTAssertNotNil(playerNode)
    }

    func testInstallTap() {
        // Arrange
        let expectation = XCTestExpectation(description: "Install tap completes")
        var tapBlockCalled = false

        // Act & Assert
        mockPlayer.installTap(bufferSize: 1024, format: nil) { buffer, time in
            tapBlockCalled = true
        }
        .sink(
            receiveCompletion: { completion in
                if case .finished = completion {
                    expectation.fulfill()
                }
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockPlayer.installTapWasCalled)
    }

    func testRemoveTap() {
        // Arrange
        let expectation = XCTestExpectation(description: "Remove tap completes")

        // Act & Assert
        mockPlayer.removeTap()
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockPlayer.removeTapWasCalled)
    }

    func testInsertAudioNode() {
        // Arrange
        let customNode = AVAudioUnitDelay()
        let expectation = XCTestExpectation(description: "Insert node completes")

        // Act & Assert
        mockPlayer.insertAudioNode(customNode, at: .beforeOutput)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockPlayer.insertedNodes.contains(customNode))
    }

    func testProcessingFormatPublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Format updates received")
        expectation.expectedFulfillmentCount = 2

        // Act & Assert
        mockPlayer.processingFormat
            .sink { format in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate format update
        mockPlayer.simulateFormatUpdate(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))

        wait(for: [expectation], timeout: 1.0)
    }

    func testSetEngineRunning() {
        // Arrange
        let expectation = XCTestExpectation(description: "Engine running state set")

        // Act & Assert
        mockPlayer.setEngineRunning(true)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockPlayer.lastEngineRunningState, true)
    }
}

// MARK: - Mock Implementation for Testing

private class MockAudioEngineAccessible: AudioEngineAccessible {
    var installTapWasCalled = false
    var removeTapWasCalled = false
    var insertedNodes: [AVAudioNode] = []
    var lastEngineRunningState: Bool?

    // Simplified engine and node
    private let _audioEngine = AVAudioEngine()
    private let _playerNode = AVAudioPlayerNode()

    var audioEngine: AVAudioEngine? { _audioEngine }
    var playerNode: AVAudioPlayerNode? { _playerNode }

    // Simplified AudioEffectable properties
    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    // Publishers
    private let processingFormatSubject = CurrentValueSubject<AVAudioFormat?, Never>(nil)
    private let engineConfigSubject = CurrentValueSubject<EngineConfiguration, Never>(
        EngineConfiguration(
            sampleRate: 44100,
            channelCount: 2,
            format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!,
            isRunning: false,
            bufferSize: 1024,
            hardwareSampleRate: 44100,
            hardwareBufferDuration: 0.023
        )
    )

    // Other required publishers (simplified)
    var playbackState: AnyPublisher<PlaybackState, Never> {
        Just(.idle).eraseToAnyPublisher()
    }
    var currentTime: AnyPublisher<TimeInterval, Never> {
        Just(0.0).eraseToAnyPublisher()
    }
    var duration: AnyPublisher<TimeInterval, Never> {
        Just(0.0).eraseToAnyPublisher()
    }
    var metadata: AnyPublisher<AudioMetadata?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    var bufferStatus: AnyPublisher<BufferStatus?, Never> {
        Just(nil).eraseToAnyPublisher()
    }
    var currentEffects: AnyPublisher<[AudioEffect], Never> {
        Just([]).eraseToAnyPublisher()
    }

    var processingFormat: AnyPublisher<AVAudioFormat?, Never> {
        processingFormatSubject.eraseToAnyPublisher()
    }

    var engineConfiguration: AnyPublisher<EngineConfiguration, Never> {
        engineConfigSubject.eraseToAnyPublisher()
    }

    // AudioEngineAccessible methods
    func installTap(bufferSize: AVAudioFrameCount, format: AVAudioFormat?, tapBlock: @escaping AVAudioNodeTapBlock) -> AnyPublisher<Void, AudioError> {
        installTapWasCalled = true
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func removeTap() -> AnyPublisher<Void, AudioError> {
        removeTapWasCalled = true
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func insertAudioNode(_ node: AVAudioNode, at position: NodePosition) -> AnyPublisher<Void, AudioError> {
        insertedNodes.append(node)
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func removeAudioNode(_ node: AVAudioNode) -> AnyPublisher<Void, AudioError> {
        insertedNodes.removeAll { $0 === node }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func setEngineRunning(_ shouldStart: Bool) -> AnyPublisher<Void, AudioError> {
        lastEngineRunningState = shouldStart
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // Simplified implementations of other required methods
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func play() -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func pause() -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // Test helper
    func simulateFormatUpdate(_ format: AVAudioFormat?) {
        processingFormatSubject.send(format)
    }
}