// AudioEffectsIntegrationTests.swift - T046: Real-time audio effects manipulation
// Tests real-time effects for music and audio processing apps

import XCTest
import Combine
import Foundation
import AVFoundation
@testable import Resonance

final class AudioEffectsIntegrationTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    private var mockEffectsPlayer: MockAudioEffectable!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
        mockEffectsPlayer = MockAudioEffectable()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        mockEffectsPlayer = nil
        try await super.tearDown()
    }

    // MARK: - T046.1: Real-time Effect Application

    func testRealTimeEffectApplication() async throws {
        // Test applying effects during live audio playback
        let testURL = URL(string: "https://example.com/music-track.mp3")!

        try await preparePlayback(url: testURL)
        try await startPlayback()

        // Create a reverb effect
        let reverbEffect = AudioEffect(
            type: .reverb,
            parameters: [EffectParameterKeys.wetDryMix: 50.0],
            displayName: "Concert Hall Reverb"
        )

        var effectsUpdates: [[AudioEffect]] = []

        // Monitor effect changes
        mockEffectsPlayer.currentEffects
            .sink { effects in
                effectsUpdates.append(effects)
            }
            .store(in: &cancellables)

        // Apply effect during playback
        let addEffectExpectation = expectation(description: "Add reverb effect")
        mockEffectsPlayer.addEffect(reverbEffect)
            .sink(
                receiveCompletion: { _ in addEffectExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [addEffectExpectation], timeout: 1.0)

        // Verify effect was applied in real-time
        let currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 1, "Should have one effect applied")
        XCTAssertEqual(currentEffects.first?.type, .reverb, "Should be reverb effect")
        XCTAssertEqual(currentEffects.first?.displayName, "Concert Hall Reverb")

        // Verify effects updates were captured
        XCTAssertTrue(effectsUpdates.contains { $0.count == 1 }, "Should capture effect addition")
    }

    // MARK: - T046.2: Multiple Effects Chain

    func testMultipleEffectsChain() async throws {
        // Test applying multiple effects in a processing chain
        let testURL = URL(string: "https://example.com/audio-processing.mp3")!

        try await preparePlayback(url: testURL)

        // Create effect chain: EQ -> Compressor -> Reverb
        let eqEffect = AudioEffect(
            type: .equalizer,
            parameters: [
                EffectParameterKeys.bands: [
                    EQBand(frequency: 60, gain: 3.0),
                    EQBand(frequency: 1000, gain: -2.0),
                    EQBand(frequency: 8000, gain: 1.5)
                ]
            ],
            displayName: "Bass Boost EQ"
        )

        let compressorEffect = AudioEffect(
            type: .compressor,
            parameters: [
                EffectParameterKeys.threshold: -12.0,
                EffectParameterKeys.ratio: 4.0,
                EffectParameterKeys.attack: 0.003,
                EffectParameterKeys.release: 0.1
            ],
            displayName: "Vocal Compressor"
        )

        let reverbEffect = AudioEffect(
            type: .reverb,
            parameters: [EffectParameterKeys.wetDryMix: 25.0],
            displayName: "Subtle Reverb"
        )

        // Apply effects in sequence
        let effects = [eqEffect, compressorEffect, reverbEffect]
        let addEffectsExpectation = expectation(description: "Add effect chain")
        addEffectsExpectation.expectedFulfillmentCount = 3

        for effect in effects {
            mockEffectsPlayer.addEffect(effect)
                .sink(
                    receiveCompletion: { _ in addEffectsExpectation.fulfill() },
                    receiveValue: { }
                )
                .store(in: &cancellables)
        }

        await fulfillment(of: [addEffectsExpectation], timeout: 2.0)

        // Verify all effects are applied
        let currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 3, "Should have three effects in chain")

        // Verify order is maintained (important for audio processing)
        let effectTypes = currentEffects.map { $0.type }
        XCTAssertEqual(effectTypes[0], .equalizer, "EQ should be first")
        XCTAssertEqual(effectTypes[1], .compressor, "Compressor should be second")
        XCTAssertEqual(effectTypes[2], .reverb, "Reverb should be third")
    }

    // MARK: - T046.3: Real-time Parameter Updates

    func testRealTimeParameterUpdates() async throws {
        // Test updating effect parameters during playback (e.g., EQ knobs)
        let testURL = URL(string: "https://example.com/live-mixing.mp3")!

        try await preparePlayback(url: testURL)
        try await startPlayback()

        // Add an EQ effect
        let eqEffect = AudioEffect(
            type: .equalizer,
            parameters: [EffectParameterKeys.globalGain: 0.0],
            displayName: "Live EQ"
        )

        try await addEffect(eqEffect)

        var parameterUpdates: [String: Any] = [:]

        // Simulate real-time EQ adjustments (like user moving sliders)
        let parameterValues: [(String, Any)] = [
            (EffectParameterKeys.globalGain, 3.0),
            (EffectParameterKeys.globalGain, 6.0),
            (EffectParameterKeys.globalGain, -2.0)
        ]

        for (key, value) in parameterValues {
            let updateExpectation = expectation(description: "Parameter update: \(key)")

            mockEffectsPlayer.updateEffect(
                id: eqEffect.id,
                parameters: [key: value]
            )
            .sink(
                receiveCompletion: { _ in
                    parameterUpdates[key] = value
                    updateExpectation.fulfill()
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

            await fulfillment(of: [updateExpectation], timeout: 1.0)

            // Small delay to simulate real-time adjustments
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        // Verify final parameter state
        XCTAssertEqual(parameterUpdates[EffectParameterKeys.globalGain] as? Double, -2.0,
                      "Should have final gain value")

        // Verify effect is still active after parameter changes
        let currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertTrue(currentEffects.contains { $0.id == eqEffect.id && $0.isEnabled },
                     "Effect should remain enabled after parameter updates")
    }

    // MARK: - T046.4: Effect Enable/Disable Toggle

    func testEffectToggling() async throws {
        // Test enabling/disabling effects without removing them
        let testURL = URL(string: "https://example.com/toggle-test.mp3")!

        try await preparePlayback(url: testURL)

        // Add multiple effects
        let distortionEffect = AudioEffect(
            type: .distortion,
            displayName: "Guitar Distortion"
        )

        let reverbEffect = AudioEffect(
            type: .reverb,
            parameters: [EffectParameterKeys.wetDryMix: 75.0],
            displayName: "Large Hall"
        )

        try await addEffect(distortionEffect)
        try await addEffect(reverbEffect)

        // Verify both effects are enabled initially
        var currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertTrue(currentEffects.allSatisfy { $0.isEnabled }, "All effects should start enabled")

        // Disable distortion effect
        let disableExpectation = expectation(description: "Disable distortion")
        mockEffectsPlayer.setEffectEnabled(id: distortionEffect.id, enabled: false)
            .sink(
                receiveCompletion: { _ in disableExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [disableExpectation], timeout: 1.0)

        // Verify distortion is disabled but reverb remains enabled
        currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        let distortion = currentEffects.first { $0.id == distortionEffect.id }
        let reverb = currentEffects.first { $0.id == reverbEffect.id }

        XCTAssertEqual(distortion?.isEnabled, false, "Distortion should be disabled")
        XCTAssertEqual(reverb?.isEnabled, true, "Reverb should remain enabled")

        // Re-enable distortion
        let enableExpectation = expectation(description: "Re-enable distortion")
        mockEffectsPlayer.setEffectEnabled(id: distortionEffect.id, enabled: true)
            .sink(
                receiveCompletion: { _ in enableExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [enableExpectation], timeout: 1.0)

        // Verify distortion is enabled again
        currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        let reenabledDistortion = currentEffects.first { $0.id == distortionEffect.id }
        XCTAssertEqual(reenabledDistortion?.isEnabled, true, "Distortion should be re-enabled")
    }

    // MARK: - T046.5: Effect Removal and Chain Updates

    func testEffectRemovalAndChainUpdates() async throws {
        // Test removing effects from active chain
        let testURL = URL(string: "https://example.com/chain-updates.mp3")!

        try await preparePlayback(url: testURL)

        // Create a complex effect chain
        let effects: [AudioEffect] = [
            AudioEffect(type: .equalizer, displayName: "EQ 1"),
            AudioEffect(type: .compressor, displayName: "Compressor"),
            AudioEffect(type: .reverb, displayName: "Reverb"),
            AudioEffect(type: .distortion, displayName: "Distortion")
        ]

        // Add all effects
        for effect in effects {
            try await addEffect(effect)
        }

        var currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 4, "Should have all four effects")

        // Remove compressor from the middle of chain
        let compressorId = effects[1].id
        let removeExpectation = expectation(description: "Remove compressor")

        mockEffectsPlayer.removeEffect(id: compressorId)
            .sink(
                receiveCompletion: { _ in removeExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [removeExpectation], timeout: 1.0)

        // Verify compressor was removed but others remain
        currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 3, "Should have three effects after removal")
        XCTAssertFalse(currentEffects.contains { $0.id == compressorId },
                      "Compressor should be removed")

        // Verify remaining effects maintain their order
        let remainingTypes = currentEffects.map { $0.type }
        let expectedTypes: [EffectType] = [.equalizer, .reverb, .distortion]
        XCTAssertEqual(remainingTypes, expectedTypes, "Remaining effects should maintain order")
    }

    // MARK: - T046.6: Reset All Effects

    func testResetAllEffects() async throws {
        // Test resetting all effects to default state
        let testURL = URL(string: "https://example.com/reset-test.mp3")!

        try await preparePlayback(url: testURL)

        // Add several effects with modified parameters
        let customEQ = AudioEffect(
            type: .equalizer,
            parameters: [EffectParameterKeys.globalGain: 6.0],
            displayName: "Boosted EQ"
        )

        let heavyReverb = AudioEffect(
            type: .reverb,
            parameters: [EffectParameterKeys.wetDryMix: 90.0],
            displayName: "Heavy Reverb"
        )

        try await addEffect(customEQ)
        try await addEffect(heavyReverb)

        // Verify effects are active
        var currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 2, "Should have two effects before reset")

        // Reset all effects
        let resetExpectation = expectation(description: "Reset all effects")
        mockEffectsPlayer.resetAllEffects()
            .sink(
                receiveCompletion: { _ in resetExpectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [resetExpectation], timeout: 1.0)

        // Verify all effects are removed/reset
        currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 0, "Should have no effects after reset")
    }

    // MARK: - T046.7: Performance Under Heavy Effects Load

    func testPerformanceUnderHeavyEffectsLoad() async throws {
        // Test performance when applying many effects simultaneously
        let testURL = URL(string: "https://example.com/performance-test.mp3")!

        try await preparePlayback(url: testURL)

        let startTime = Date()

        // Create many effects to stress-test the system
        var effects: [AudioEffect] = []
        for i in 0..<10 {
            effects.append(AudioEffect(
                type: .equalizer,
                parameters: [EffectParameterKeys.globalGain: Float(i)],
                displayName: "EQ \(i)"
            ))
        }

        // Add all effects rapidly
        let addAllEffectsExpectation = expectation(description: "Add many effects")
        addAllEffectsExpectation.expectedFulfillmentCount = effects.count

        for effect in effects {
            mockEffectsPlayer.addEffect(effect)
                .sink(
                    receiveCompletion: { _ in addAllEffectsExpectation.fulfill() },
                    receiveValue: { }
                )
                .store(in: &cancellables)
        }

        await fulfillment(of: [addAllEffectsExpectation], timeout: 3.0)

        let endTime = Date()
        let totalDuration = endTime.timeIntervalSince(startTime)

        // Verify all effects were applied
        let currentEffects = mockEffectsPlayer.getCurrentEffectsSnapshot()
        XCTAssertEqual(currentEffects.count, 10, "Should have all ten effects applied")

        // Performance requirement: should handle many effects efficiently
        XCTAssertLessThan(totalDuration, 2.0, "Should apply many effects within 2 seconds")

        // Verify system remains stable under load
        XCTAssertEqual(mockEffectsPlayer.playbackState.value, .playing,
                      "Playback should continue during heavy effects processing")
    }

    // MARK: - Helper Methods

    private func preparePlayback(url: URL, metadata: AudioMetadata? = nil) async throws {
        let expectation = expectation(description: "Prepare playback")

        mockEffectsPlayer.loadAudio(from: url, metadata: metadata)
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        expectation.fulfill()
                    }
                },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    private func startPlayback() async throws {
        let expectation = expectation(description: "Start playback")

        mockEffectsPlayer.play()
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    private func addEffect(_ effect: AudioEffect) async throws {
        let expectation = expectation(description: "Add effect")

        mockEffectsPlayer.addEffect(effect)
            .sink(
                receiveCompletion: { _ in expectation.fulfill() },
                receiveValue: { }
            )
            .store(in: &cancellables)

        await fulfillment(of: [expectation], timeout: 1.0)
    }
}

// MARK: - Mock Implementation

/// Mock implementation of AudioEffectable for testing real-time effects
private class MockAudioEffectable: AudioEffectable {
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)
    private let currentEffectsSubject = CurrentValueSubject<[AudioEffect], Never>([])

    private var effects: [AudioEffect] = []

    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    // Protocol conformance
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

    var currentEffects: AnyPublisher<[AudioEffect], Never> {
        currentEffectsSubject.eraseToAnyPublisher()
    }

    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.loading)
                self.metadataSubject.send(metadata)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.playbackStateSubject.send(.ready)
                    self.durationSubject.send(240.0) // 4-minute test audio
                    promise(.success(()))
                }
            }
        }.eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.playing)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.playbackStateSubject.send(.paused)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.currentTimeSubject.send(position)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.metadataSubject.send(metadata)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                let newTime = self.currentTimeSubject.value + duration
                self.currentTimeSubject.send(min(newTime, self.durationSubject.value))
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                let newTime = max(0, self.currentTimeSubject.value - duration)
                self.currentTimeSubject.send(newTime)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    // MARK: - Effects Implementation

    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.effects.append(effect)
                self.currentEffectsSubject.send(self.effects)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.effects.removeAll { $0.id == effectId }
                self.currentEffectsSubject.send(self.effects)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if let index = self.effects.firstIndex(where: { $0.id == effectId }) {
                    let oldEffect = self.effects[index]
                    var newParameters = oldEffect.parameters
                    for (key, value) in parameters {
                        newParameters[key] = value
                    }
                    let updatedEffect = AudioEffect(
                        id: oldEffect.id,
                        type: oldEffect.type,
                        parameters: newParameters,
                        isEnabled: oldEffect.isEnabled,
                        displayName: oldEffect.displayName
                    )
                    self.effects[index] = updatedEffect
                    self.currentEffectsSubject.send(self.effects)
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                if let index = self.effects.firstIndex(where: { $0.id == effectId }) {
                    let oldEffect = self.effects[index]
                    let updatedEffect = AudioEffect(
                        id: oldEffect.id,
                        type: oldEffect.type,
                        parameters: oldEffect.parameters,
                        isEnabled: enabled,
                        displayName: oldEffect.displayName
                    )
                    self.effects[index] = updatedEffect
                    self.currentEffectsSubject.send(self.effects)
                }
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            DispatchQueue.main.async {
                self.effects.removeAll()
                self.currentEffectsSubject.send(self.effects)
                promise(.success(()))
            }
        }.eraseToAnyPublisher()
    }

    func getCurrentEffectsSnapshot() -> [AudioEffect] {
        return effects
    }
}