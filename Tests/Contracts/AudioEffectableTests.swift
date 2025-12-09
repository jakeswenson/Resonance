// AudioEffectableTests.swift - Contract tests for AudioEffectable protocol
// These tests verify real-time audio effects functionality

import XCTest
import Combine
@testable import Resonance

final class AudioEffectableTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockPlayer: MockAudioEffectable!

    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
        mockPlayer = MockAudioEffectable()
    }

    override func tearDown() {
        cancellables = nil
        mockPlayer = nil
        super.tearDown()
    }

    // MARK: - Effect Management Contract Tests

    func testAddEffect() {
        // Arrange
        let effect = AudioEffect(
            type: .reverb,
            parameters: [EffectParameterKeys.wetDryMix: 50.0],
            displayName: "Test Reverb"
        )
        let expectation = XCTestExpectation(description: "Add effect completes")

        // Act & Assert
        mockPlayer.addEffect(effect)
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
        XCTAssertTrue(mockPlayer.addedEffects.contains { $0.id == effect.id })
    }

    func testRemoveEffect() {
        // Arrange
        let effect = AudioEffect(type: .compressor)
        let expectation = XCTestExpectation(description: "Remove effect completes")

        // Add effect first
        mockPlayer.simulateEffectAdded(effect)

        // Act & Assert
        mockPlayer.removeEffect(id: effect.id)
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
        XCTAssertTrue(mockPlayer.removedEffectIds.contains(effect.id))
    }

    func testUpdateEffect() {
        // Arrange
        let effect = AudioEffect(type: .equalizer)
        let newParameters = [EffectParameterKeys.globalGain: 3.0]
        let expectation = XCTestExpectation(description: "Update effect completes")

        // Act & Assert
        mockPlayer.updateEffect(id: effect.id, parameters: newParameters)
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
        XCTAssertEqual(mockPlayer.lastUpdatedEffectId, effect.id)
        XCTAssertEqual(mockPlayer.lastUpdatedParameters?[EffectParameterKeys.globalGain] as? Double, 3.0)
    }

    func testSetEffectEnabled() {
        // Arrange
        let effect = AudioEffect(type: .distortion)
        let expectation = XCTestExpectation(description: "Set effect enabled completes")

        // Act & Assert
        mockPlayer.setEffectEnabled(id: effect.id, enabled: false)
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
        XCTAssertEqual(mockPlayer.lastEnabledEffectId, effect.id)
        XCTAssertEqual(mockPlayer.lastEnabledState, false)
    }

    // MARK: - Current Effects Publisher Contract Tests

    func testCurrentEffectsPublisher() {
        // Arrange
        let expectation = XCTestExpectation(description: "Current effects updates")
        expectation.expectedFulfillmentCount = 3
        var effectsUpdates: [[AudioEffect]] = []

        // Act & Assert
        mockPlayer.currentEffects
            .sink { effects in
                effectsUpdates.append(effects)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // Simulate effects changes
        let effect1 = AudioEffect(type: .reverb)
        let effect2 = AudioEffect(type: .equalizer)

        mockPlayer.simulateEffectsUpdate([effect1])
        mockPlayer.simulateEffectsUpdate([effect1, effect2])

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(effectsUpdates.count, 3)
        XCTAssertEqual(effectsUpdates[0].count, 0) // Initial empty state
        XCTAssertEqual(effectsUpdates[1].count, 1) // One effect added
        XCTAssertEqual(effectsUpdates[2].count, 2) // Two effects
    }

    // MARK: - Reset Effects Contract Tests

    func testResetAllEffects() {
        // Arrange
        let expectation = XCTestExpectation(description: "Reset all effects completes")

        // Act & Assert
        mockPlayer.resetAllEffects()
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
        XCTAssertTrue(mockPlayer.resetAllEffectsWasCalled)
    }

    // MARK: - Effect Types Contract Tests

    func testTimePitchEffect() {
        // Arrange
        let effect = AudioEffect(
            type: .timePitch,
            parameters: [
                EffectParameterKeys.rate: 1.5,
                EffectParameterKeys.pitch: 0.0
            ]
        )

        // Act & Assert
        XCTAssertEqual(effect.type, .timePitch)
        XCTAssertEqual(effect.type.defaultDisplayName, "Time/Pitch")
        XCTAssertEqual(effect.parameters[EffectParameterKeys.rate] as? Float, 1.5)
    }

    func testEqualizerEffect() {
        // Arrange
        let eqBands = [
            EQBand(frequency: 60, gain: 2.0),
            EQBand(frequency: 1000, gain: -1.5),
            EQBand(frequency: 8000, gain: 0.5)
        ]
        let effect = AudioEffect(
            type: .equalizer,
            parameters: [EffectParameterKeys.bands: eqBands]
        )

        // Act & Assert
        XCTAssertEqual(effect.type, .equalizer)
        let storedBands = effect.parameters[EffectParameterKeys.bands] as? [EQBand]
        XCTAssertEqual(storedBands?.count, 3)
        XCTAssertEqual(storedBands?[0].frequency, 60)
        XCTAssertEqual(storedBands?[1].gain, -1.5)
    }

    // MARK: - Error Handling Contract Tests

    func testEffectNotFound() {
        // Arrange
        let nonExistentId = UUID()
        let expectation = XCTestExpectation(description: "Effect not found error")

        // Act & Assert
        mockPlayer.forceError = AudioError.internalError("Effect not found")
        mockPlayer.removeEffect(id: nonExistentId)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        if case .internalError(let message) = error as? AudioError {
                            XCTAssertEqual(message, "Effect not found")
                            expectation.fulfill()
                        }
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation for Testing

private class MockAudioEffectable: AudioEffectable {
    // Track method calls
    var addedEffects: [AudioEffect] = []
    var removedEffectIds: [UUID] = []
    var lastUpdatedEffectId: UUID?
    var lastUpdatedParameters: [String: Any]?
    var lastEnabledEffectId: UUID?
    var lastEnabledState: Bool?
    var resetAllEffectsWasCalled = false
    var forceError: AudioError?

    // AudioConfigurable properties (simplified for testing)
    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    // Publishers
    private let currentEffectsSubject = CurrentValueSubject<[AudioEffect], Never>([])
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0.0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0.0)
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)

    var currentEffects: AnyPublisher<[AudioEffect], Never> {
        currentEffectsSubject.eraseToAnyPublisher()
    }

    var playbackState: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }

    var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }

    var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }

    var metadata: AnyPublisher<AudioMetadata?, Never> {
        metadataSubject.eraseToAnyPublisher()
    }

    var bufferStatus: AnyPublisher<BufferStatus?, Never> {
        bufferStatusSubject.eraseToAnyPublisher()
    }

    // AudioPlayable methods (simplified)
    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // AudioConfigurable methods (simplified)
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // AudioEffectable methods
    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        addedEffects.append(effect)

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        removedEffectIds.append(effectId)

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        lastUpdatedEffectId = effectId
        lastUpdatedParameters = parameters

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        lastEnabledEffectId = effectId
        lastEnabledState = enabled

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        resetAllEffectsWasCalled = true

        if let error = forceError {
            return Fail(error: error).eraseToAnyPublisher()
        }

        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    // Test helper methods
    func simulateEffectAdded(_ effect: AudioEffect) {
        addedEffects.append(effect)
    }

    func simulateEffectsUpdate(_ effects: [AudioEffect]) {
        currentEffectsSubject.send(effects)
    }
}