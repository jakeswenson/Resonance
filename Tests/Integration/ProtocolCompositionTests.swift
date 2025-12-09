// ProtocolCompositionTests.swift - T048: Protocol composition and progressive adoption
// Tests progressive adoption patterns for migrating applications

import XCTest
import Combine
import Foundation
@testable import Resonance

final class ProtocolCompositionTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        try await super.setUp()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - T048.1: Basic to Enhanced Progressive Adoption

    func testBasicToEnhancedAdoption() async throws {
        // Test upgrading from AudioPlayable to AudioConfigurable
        let basicPlayer = MockBasicPlayer()

        // Start with basic functionality
        try await testBasicPlayback(player: basicPlayer)

        // Upgrade to enhanced player
        let enhancedPlayer = MockEnhancedPlayer()

        // Copy basic state from old player
        try await migrateBasicState(from: basicPlayer, to: enhancedPlayer)

        // Test enhanced features work
        try await testEnhancedFeatures(player: enhancedPlayer)

        // Verify basic functionality still works
        try await testBasicPlayback(player: enhancedPlayer)
    }

    // MARK: - T048.2: Enhanced to Effects Progressive Adoption

    func testEnhancedToEffectsAdoption() async throws {
        // Test upgrading from AudioConfigurable to AudioEffectable
        let enhancedPlayer = MockEnhancedPlayer()

        // Establish enhanced playback
        let testURL = URL(string: "https://example.com/music.mp3")!
        try await enhancedPlayer.loadAudio(from: testURL, metadata: nil)

        enhancedPlayer.volume = 0.8
        enhancedPlayer.playbackRate = 1.25

        // Upgrade to effects player
        let effectsPlayer = MockEffectsPlayer()

        // Migrate enhanced state
        try await migrateEnhancedState(from: enhancedPlayer, to: effectsPlayer)

        // Verify enhanced features are preserved
        XCTAssertEqual(effectsPlayer.volume, 0.8, "Volume should be preserved")
        XCTAssertEqual(effectsPlayer.playbackRate, 1.25, "Playback rate should be preserved")

        // Test that effects can be added without breaking existing functionality
        let reverbEffect = AudioEffect(type: .reverb, displayName: "Test Reverb")
        try await effectsPlayer.addEffect(reverbEffect)

        // Enhanced features should still work with effects applied
        effectsPlayer.volume = 0.6
        XCTAssertEqual(effectsPlayer.volume, 0.6, "Volume control should work with effects")

        let skipExpectation = expectation(description: "Skip with effects")
        effectsPlayer.skipForward(duration: 10.0)
            .sink(receiveCompletion: { _ in skipExpectation.fulfill() }, receiveValue: { })
            .store(in: &cancellables)

        await fulfillment(of: [skipExpectation], timeout: 1.0)
    }

    // MARK: - T048.3: Multiple Protocol Composition

    func testMultipleProtocolComposition() async throws {
        // Test a player that implements multiple protocols simultaneously
        let compositePlayer = MockCompositePlayer()

        let testURL = URL(string: "https://example.com/podcast.mp3")!
        let metadata = AudioMetadata(title: "Test Episode", artist: "Test Podcast")

        // Test all protocol capabilities work together

        // 1. Basic playback
        try await compositePlayer.loadAudio(from: testURL, metadata: metadata)
        try await compositePlayer.play()

        // 2. Enhanced configuration
        compositePlayer.volume = 0.7
        compositePlayer.playbackRate = 1.5

        // 3. Effects
        let eqEffect = AudioEffect(type: .equalizer, displayName: "Podcast EQ")
        try await compositePlayer.addEffect(eqEffect)

        // 4. Download capabilities
        let downloadURL = URL(string: "https://example.com/download.mp3")!
        let downloadExpectation = expectation(description: "Download audio")

        compositePlayer.downloadAudio(from: downloadURL, metadata: nil)
            .sink(
                receiveCompletion: { _ in downloadExpectation.fulfill() },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [downloadExpectation], timeout: 2.0)

        // 5. Queue management
        let queueURL = URL(string: "https://example.com/queue.mp3")!
        try await compositePlayer.enqueue(url: queueURL, metadata: nil)

        // Verify all capabilities work together without conflicts
        XCTAssertEqual(compositePlayer.volume, 0.7)
        XCTAssertEqual(compositePlayer.playbackRate, 1.5)

        let currentEffects = compositePlayer.getCurrentEffects()
        XCTAssertEqual(currentEffects.count, 1)

        let queue = compositePlayer.getCurrentQueue()
        XCTAssertEqual(queue.count, 1)
    }

    // MARK: - T048.4: Selective Protocol Adoption

    func testSelectiveProtocolAdoption() async throws {
        // Test adopting only specific protocols based on app needs

        // Scenario 1: Podcast app (needs basic + enhanced + queue, but not effects)
        let podcastPlayer = MockPodcastPlayer()

        let episode1 = URL(string: "https://example.com/ep1.mp3")!
        let episode2 = URL(string: "https://example.com/ep2.mp3")!

        // Basic playback
        try await podcastPlayer.loadAudio(from: episode1, metadata: nil)
        try await podcastPlayer.play()

        // Enhanced features for podcast listening
        podcastPlayer.playbackRate = 1.5  // Speed listening
        try await podcastPlayer.skipForward(duration: 15.0)  // Chapter skip

        // Queue management for episode playlist
        try await podcastPlayer.enqueue(url: episode2, metadata: nil)
        podcastPlayer.autoAdvanceEnabled = true

        // Verify podcast-specific workflow
        XCTAssertEqual(podcastPlayer.playbackRate, 1.5)
        XCTAssertTrue(podcastPlayer.autoAdvanceEnabled)

        // Scenario 2: Music app (needs basic + effects, but not download/queue)
        let musicPlayer = MockMusicPlayer()

        let song = URL(string: "https://example.com/song.mp3")!
        try await musicPlayer.loadAudio(from: song, metadata: nil)
        try await musicPlayer.play()

        // Effects for music enhancement
        let bassBoostEQ = AudioEffect(
            type: .equalizer,
            parameters: ["bass": 5.0],
            displayName: "Bass Boost"
        )
        try await musicPlayer.addEffect(bassBoostEQ)

        let reverb = AudioEffect(type: .reverb, displayName: "Concert Hall")
        try await musicPlayer.addEffect(reverb)

        // Verify music-specific workflow
        let effects = musicPlayer.getCurrentEffects()
        XCTAssertEqual(effects.count, 2)
    }

    // MARK: - T048.5: Protocol Compatibility and Interoperability

    func testProtocolInteroperability() async throws {
        // Test that different protocol implementations can work together

        let basicPlayer = MockBasicPlayer()
        let enhancedPlayer = MockEnhancedPlayer()
        let effectsPlayer = MockEffectsPlayer()

        // Create a shared audio session
        let testURL = URL(string: "https://example.com/interop.mp3")!

        // Each player should be able to handle the same audio independently
        try await basicPlayer.loadAudio(from: testURL, metadata: nil)
        try await enhancedPlayer.loadAudio(from: testURL, metadata: nil)
        try await effectsPlayer.loadAudio(from: testURL, metadata: nil)

        // Test state synchronization across different protocol levels
        var playbackStates: [String: PlaybackState] = [:]

        basicPlayer.playbackState
            .sink { state in playbackStates["basic"] = state }
            .store(in: &cancellables)

        enhancedPlayer.playbackState
            .sink { state in playbackStates["enhanced"] = state }
            .store(in: &cancellables)

        effectsPlayer.playbackState
            .sink { state in playbackStates["effects"] = state }
            .store(in: &cancellables)

        // Start playback on all players
        try await basicPlayer.play()
        try await enhancedPlayer.play()
        try await effectsPlayer.play()

        // All should be in playing state
        XCTAssertEqual(playbackStates["basic"], .playing)
        XCTAssertEqual(playbackStates["enhanced"], .playing)
        XCTAssertEqual(playbackStates["effects"], .playing)
    }

    // MARK: - T048.6: Migration Strategy Validation

    func testMigrationStrategies() async throws {
        // Test different migration approaches from legacy to modern protocols

        // Strategy 1: Gradual feature adoption
        await testGradualMigration()

        // Strategy 2: Wrapper-based migration
        await testWrapperBasedMigration()

        // Strategy 3: Feature flag migration
        await testFeatureFlagMigration()
    }

    private func testGradualMigration() async {
        // Simulate gradual adoption: basic -> enhanced -> effects -> queue

        var currentPlayer: any AudioPlayable = MockBasicPlayer()

        // Start with basic
        let testURL = URL(string: "https://example.com/gradual.mp3")!
        try? await currentPlayer.loadAudio(from: testURL, metadata: nil)

        // Upgrade to enhanced
        if let enhancedPlayer = currentPlayer as? AudioConfigurable {
            // Already enhanced, continue
        } else {
            currentPlayer = MockEnhancedPlayer()
            try? await currentPlayer.loadAudio(from: testURL, metadata: nil)
        }

        // Upgrade to effects
        if let effectsPlayer = currentPlayer as? AudioEffectable {
            // Already has effects
        } else {
            currentPlayer = MockEffectsPlayer()
            try? await currentPlayer.loadAudio(from: testURL, metadata: nil)
        }

        // Final player should have all capabilities
        XCTAssertTrue(currentPlayer is AudioEffectable, "Final player should support effects")
    }

    private func testWrapperBasedMigration() async {
        // Test using wrapper pattern to add capabilities
        let basicPlayer = MockBasicPlayer()
        let wrapper = EnhancedPlayerWrapper(basicPlayer: basicPlayer)

        let testURL = URL(string: "https://example.com/wrapper.mp3")!

        // Wrapper should provide enhanced features while delegating basic functionality
        try? await wrapper.loadAudio(from: testURL, metadata: nil)
        try? await wrapper.play()

        // Enhanced features through wrapper
        wrapper.volume = 0.5
        XCTAssertEqual(wrapper.volume, 0.5)

        try? await wrapper.skipForward(duration: 5.0)

        // Verify basic functionality still works through delegation
        let playbackStateExpectation = expectation(description: "Wrapper playback state")

        wrapper.playbackState
            .sink { state in
                if state == .playing {
                    playbackStateExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await fulfillment(of: [playbackStateExpectation], timeout: 1.0)
    }

    private func testFeatureFlagMigration() async {
        // Test migration using feature flags
        let flaggedPlayer = FeatureFlaggedPlayer()

        // Enable features progressively
        flaggedPlayer.enableEnhancedFeatures = true
        flaggedPlayer.enableEffects = false
        flaggedPlayer.enableQueue = true

        let testURL = URL(string: "https://example.com/flagged.mp3")!
        try? await flaggedPlayer.loadAudio(from: testURL, metadata: nil)

        // Should have basic + enhanced + queue, but not effects
        XCTAssertTrue(flaggedPlayer.hasBasicFeatures)
        XCTAssertTrue(flaggedPlayer.hasEnhancedFeatures)
        XCTAssertFalse(flaggedPlayer.hasEffectFeatures)
        XCTAssertTrue(flaggedPlayer.hasQueueFeatures)

        // Test that disabled features return appropriate responses
        do {
            let effect = AudioEffect(type: .reverb, displayName: "Test")
            try await flaggedPlayer.addEffect(effect)
            XCTFail("Should not allow effects when disabled")
        } catch {
            // Expected to fail when effects are disabled
        }
    }

    // MARK: - T048.7: Real-World Progressive Adoption Scenario

    func testRealWorldProgressiveAdoption() async throws {
        // Simulate a real app migrating from simple audio playback to full-featured player

        // Phase 1: MVP with basic playback
        let mvpPlayer = MockBasicPlayer()
        let podcast = URL(string: "https://example.com/mvp-podcast.mp3")!

        try await mvpPlayer.loadAudio(from: podcast, metadata: nil)
        try await mvpPlayer.play()

        // Phase 2: Add speed control for podcasts
        let v2Player = MockEnhancedPlayer()
        try await migrateBasicState(from: mvpPlayer, to: v2Player)

        v2Player.playbackRate = 1.25  // 1.25x speed
        try await v2Player.skipForward(duration: 30.0)  // Skip ads

        // Phase 3: Add download for offline listening
        let v3Player = MockDownloadPlayer()
        try await migrateEnhancedState(from: v2Player, to: v3Player)

        let downloadExpectation = expectation(description: "Download for offline")
        let offlineURL = URL(string: "https://example.com/offline-episode.mp3")!

        v3Player.downloadAudio(from: offlineURL, metadata: nil)
            .sink(
                receiveCompletion: { _ in downloadExpectation.fulfill() },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)

        await fulfillment(of: [downloadExpectation], timeout: 2.0)

        // Phase 4: Add playlist management
        let v4Player = MockPodcastPlayer()
        try await migrateDownloadState(from: v3Player, to: v4Player)

        let nextEpisode = URL(string: "https://example.com/next-episode.mp3")!
        try await v4Player.enqueue(url: nextEpisode, metadata: nil)
        v4Player.autoAdvanceEnabled = true

        // Verify complete feature set works together
        XCTAssertEqual(v4Player.playbackRate, 1.25, "Speed control preserved")
        XCTAssertTrue(v4Player.autoAdvanceEnabled, "Queue management available")

        // Verify local downloads are available
        let localURL = v4Player.localURL(for: offlineURL)
        XCTAssertNotNil(localURL, "Downloaded content should be available")

        // Final verification: all features work in harmony
        let queue = v4Player.getCurrentQueue()
        XCTAssertEqual(queue.count, 1, "Queue should have next episode")
    }

    // MARK: - Helper Methods and Mock Implementations

    private func testBasicPlayback(player: AudioPlayable) async throws {
        let testURL = URL(string: "https://example.com/basic-test.mp3")!
        try await player.loadAudio(from: testURL, metadata: nil)

        let playExpectation = expectation(description: "Basic play")
        player.play()
            .sink(receiveCompletion: { _ in playExpectation.fulfill() }, receiveValue: { })
            .store(in: &cancellables)

        await fulfillment(of: [playExpectation], timeout: 1.0)
    }

    private func testEnhancedFeatures(player: AudioConfigurable) async throws {
        player.volume = 0.5
        XCTAssertEqual(player.volume, 0.5)

        player.playbackRate = 2.0
        XCTAssertEqual(player.playbackRate, 2.0)

        let skipExpectation = expectation(description: "Enhanced skip")
        player.skipForward(duration: 15.0)
            .sink(receiveCompletion: { _ in skipExpectation.fulfill() }, receiveValue: { })
            .store(in: &cancellables)

        await fulfillment(of: [skipExpectation], timeout: 1.0)
    }

    private func migrateBasicState(from oldPlayer: AudioPlayable, to newPlayer: AudioPlayable) async throws {
        // In real implementation, this would preserve current time, loaded audio, etc.
        let testURL = URL(string: "https://example.com/migrate.mp3")!
        try await newPlayer.loadAudio(from: testURL, metadata: nil)
    }

    private func migrateEnhancedState(from oldPlayer: AudioConfigurable, to newPlayer: AudioConfigurable) async throws {
        // Migrate basic state
        try await migrateBasicState(from: oldPlayer, to: newPlayer)

        // Preserve enhanced settings
        newPlayer.volume = oldPlayer.volume
        newPlayer.playbackRate = oldPlayer.playbackRate
    }

    private func migrateDownloadState(from oldPlayer: AudioDownloadable, to newPlayer: AudioDownloadable) async throws {
        // In real implementation, would transfer download history, settings, etc.
        newPlayer.allowsCellularDownloads = oldPlayer.allowsCellularDownloads
    }
}

// MARK: - Mock Implementations for Progressive Adoption Testing

private class MockBasicPlayer: AudioPlayable {
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)

    var playbackState: AnyPublisher<PlaybackState, Never> {
        playbackStateSubject.eraseToAnyPublisher()
    }
    var currentTime: AnyPublisher<TimeInterval, Never> {
        currentTimeSubject.eraseToAnyPublisher()
    }
    var duration: AnyPublisher<TimeInterval, Never> {
        durationSubject.eraseToAnyPublisher()
    }

    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.playbackStateSubject.send(.ready)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.playbackStateSubject.send(.playing)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.playbackStateSubject.send(.paused)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.currentTimeSubject.send(position)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }
}

private class MockEnhancedPlayer: MockBasicPlayer, AudioConfigurable {
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)

    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    var metadata: AnyPublisher<AudioMetadata?, Never> {
        metadataSubject.eraseToAnyPublisher()
    }
    var bufferStatus: AnyPublisher<BufferStatus?, Never> {
        bufferStatusSubject.eraseToAnyPublisher()
    }

    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.metadataSubject.send(metadata)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return seek(to: currentTime.prefix(1).first().map { $0 + duration } ?? duration)
    }

    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return seek(to: max(0, (currentTime.prefix(1).first().map { $0 - duration } ?? 0)))
    }
}

private class MockEffectsPlayer: MockEnhancedPlayer, AudioEffectable {
    private let currentEffectsSubject = CurrentValueSubject<[AudioEffect], Never>([])
    private var effects: [AudioEffect] = []

    var currentEffects: AnyPublisher<[AudioEffect], Never> {
        currentEffectsSubject.eraseToAnyPublisher()
    }

    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.effects.append(effect)
            self.currentEffectsSubject.send(self.effects)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.effects.removeAll { $0.id == effectId }
            self.currentEffectsSubject.send(self.effects)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        return Future { promise in promise(.success(())) }.eraseToAnyPublisher()
    }

    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        return Future { promise in promise(.success(())) }.eraseToAnyPublisher()
    }

    func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.effects.removeAll()
            self.currentEffectsSubject.send(self.effects)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func getCurrentEffects() -> [AudioEffect] { effects }
}

private class MockCompositePlayer: MockEffectsPlayer, AudioDownloadable, AudioQueueManageable {
    private var downloads: [URL: DownloadInfo] = [:]
    private var queue: [QueuedAudio] = []

    var allowsCellularDownloads: Bool = true
    var autoAdvanceEnabled: Bool = false
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> {
        Just([:]).eraseToAnyPublisher()
    }

    var queuePublisher: AnyPublisher<[QueuedAudio], Never> {
        Just(queue).eraseToAnyPublisher()
    }
    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> {
        Just(queue.first).eraseToAnyPublisher()
    }

    // Download methods
    func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError> {
        return Future { promise in
            let progress = DownloadProgress(
                remoteURL: url,
                localURL: URL(fileURLWithPath: "/tmp/\(url.lastPathComponent)"),
                progress: 1.0,
                state: .completed,
                downloadedBytes: 1000000
            )
            promise(.success(progress))
        }.eraseToAnyPublisher()
    }

    func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func localURL(for remoteURL: URL) -> URL? {
        return downloads[remoteURL]?.localURL
    }

    func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func getAllDownloads() -> [DownloadInfo] {
        return Array(downloads.values)
    }

    // Queue methods
    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            let queuedAudio = QueuedAudio(url: url, metadata: metadata, queuePosition: self.queue.count)
            self.queue.append(queuedAudio)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return enqueue(url: url, metadata: metadata)
    }

    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func playNext() -> AnyPublisher<Void, AudioError> {
        return play()
    }

    func playPrevious() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func clearQueue() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.queue.removeAll()
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func getCurrentQueue() -> [QueuedAudio] { queue }
}

private class MockPodcastPlayer: MockEnhancedPlayer, AudioQueueManageable {
    private var queue: [QueuedAudio] = []

    var autoAdvanceEnabled: Bool = false
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    var queuePublisher: AnyPublisher<[QueuedAudio], Never> {
        Just(queue).eraseToAnyPublisher()
    }
    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> {
        Just(queue.first).eraseToAnyPublisher()
    }

    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            let queuedAudio = QueuedAudio(url: url, metadata: metadata, queuePosition: self.queue.count)
            self.queue.append(queuedAudio)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return enqueue(url: url, metadata: metadata)
    }

    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func playNext() -> AnyPublisher<Void, AudioError> { return play() }
    func playPrevious() -> AnyPublisher<Void, AudioError> { return play() }

    func clearQueue() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.queue.removeAll()
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func getCurrentQueue() -> [QueuedAudio] { queue }
}

private class MockMusicPlayer: MockBasicPlayer, AudioEffectable {
    private let currentEffectsSubject = CurrentValueSubject<[AudioEffect], Never>([])
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)
    private var effects: [AudioEffect] = []

    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    var metadata: AnyPublisher<AudioMetadata?, Never> {
        metadataSubject.eraseToAnyPublisher()
    }
    var bufferStatus: AnyPublisher<BufferStatus?, Never> {
        bufferStatusSubject.eraseToAnyPublisher()
    }
    var currentEffects: AnyPublisher<[AudioEffect], Never> {
        currentEffectsSubject.eraseToAnyPublisher()
    }

    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.effects.append(effect)
            self.currentEffectsSubject.send(self.effects)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func getCurrentEffects() -> [AudioEffect] { effects }
}

private class MockDownloadPlayer: MockEnhancedPlayer, AudioDownloadable {
    var allowsCellularDownloads: Bool = true
    var downloadProgress: AnyPublisher<[URL: DownloadProgress], Never> {
        Just([:]).eraseToAnyPublisher()
    }

    func downloadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<DownloadProgress, AudioError> {
        return Future { promise in
            let progress = DownloadProgress(
                remoteURL: url,
                localURL: URL(fileURLWithPath: "/tmp/\(url.lastPathComponent)"),
                progress: 1.0,
                state: .completed,
                downloadedBytes: 1000000
            )
            promise(.success(progress))
        }.eraseToAnyPublisher()
    }

    func cancelDownload(for url: URL) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func localURL(for remoteURL: URL) -> URL? {
        return URL(fileURLWithPath: "/tmp/\(remoteURL.lastPathComponent)")
    }

    func deleteDownload(at localURL: URL) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func getAllDownloads() -> [DownloadInfo] { [] }
}

private class EnhancedPlayerWrapper: AudioConfigurable {
    private let basicPlayer: AudioPlayable
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)

    var volume: Float = 1.0
    var playbackRate: Float = 1.0

    init(basicPlayer: AudioPlayable) {
        self.basicPlayer = basicPlayer
    }

    var playbackState: AnyPublisher<PlaybackState, Never> { basicPlayer.playbackState }
    var currentTime: AnyPublisher<TimeInterval, Never> { basicPlayer.currentTime }
    var duration: AnyPublisher<TimeInterval, Never> { basicPlayer.duration }
    var metadata: AnyPublisher<AudioMetadata?, Never> { metadataSubject.eraseToAnyPublisher() }
    var bufferStatus: AnyPublisher<BufferStatus?, Never> { bufferStatusSubject.eraseToAnyPublisher() }

    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return basicPlayer.loadAudio(from: url, metadata: metadata)
    }
    func play() -> AnyPublisher<Void, AudioError> { basicPlayer.play() }
    func pause() -> AnyPublisher<Void, AudioError> { basicPlayer.pause() }
    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return basicPlayer.seek(to: position)
    }

    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.metadataSubject.send(metadata)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
}

private class FeatureFlaggedPlayer: AudioEffectable, AudioQueueManageable {
    var enableEnhancedFeatures = false
    var enableEffects = false
    var enableQueue = false

    var hasBasicFeatures = true
    var hasEnhancedFeatures: Bool { enableEnhancedFeatures }
    var hasEffectFeatures: Bool { enableEffects }
    var hasQueueFeatures: Bool { enableQueue }

    // Basic implementation
    private let playbackStateSubject = CurrentValueSubject<PlaybackState, Never>(.idle)
    private let currentTimeSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let durationSubject = CurrentValueSubject<TimeInterval, Never>(0)
    private let metadataSubject = CurrentValueSubject<AudioMetadata?, Never>(nil)
    private let bufferStatusSubject = CurrentValueSubject<BufferStatus?, Never>(nil)
    private let currentEffectsSubject = CurrentValueSubject<[AudioEffect], Never>([])

    var volume: Float = 1.0
    var playbackRate: Float = 1.0
    var autoAdvanceEnabled: Bool = false
    var repeatMode: RepeatMode = .off
    var shuffleEnabled: Bool = false

    var playbackState: AnyPublisher<PlaybackState, Never> { playbackStateSubject.eraseToAnyPublisher() }
    var currentTime: AnyPublisher<TimeInterval, Never> { currentTimeSubject.eraseToAnyPublisher() }
    var duration: AnyPublisher<TimeInterval, Never> { durationSubject.eraseToAnyPublisher() }
    var metadata: AnyPublisher<AudioMetadata?, Never> { metadataSubject.eraseToAnyPublisher() }
    var bufferStatus: AnyPublisher<BufferStatus?, Never> { bufferStatusSubject.eraseToAnyPublisher() }
    var currentEffects: AnyPublisher<[AudioEffect], Never> { currentEffectsSubject.eraseToAnyPublisher() }
    var queue: AnyPublisher<[QueuedAudio], Never> { Just([]).eraseToAnyPublisher() }
    var currentQueueItem: AnyPublisher<QueuedAudio?, Never> { Just(nil).eraseToAnyPublisher() }

    func loadAudio(from url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.playbackStateSubject.send(.ready)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func play() -> AnyPublisher<Void, AudioError> {
        return Future { promise in
            self.playbackStateSubject.send(.playing)
            promise(.success(()))
        }.eraseToAnyPublisher()
    }

    func pause() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func seek(to position: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func updateMetadata(_ metadata: AudioMetadata) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipForward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func skipBackward(duration: TimeInterval) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func addEffect(_ effect: AudioEffect) -> AnyPublisher<Void, AudioError> {
        if enableEffects {
            return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
        } else {
            return Fail(error: AudioError.internalError("Effects disabled")).eraseToAnyPublisher()
        }
    }

    func removeEffect(id effectId: UUID) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func updateEffect(id effectId: UUID, parameters: [String: Any]) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func setEffectEnabled(id effectId: UUID, enabled: Bool) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func resetAllEffects() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }

    func enqueue(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func enqueueNext(url: URL, metadata: AudioMetadata?) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func dequeue(id queueId: UUID) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func playNext() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func playPrevious() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func clearQueue() -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
    func moveQueueItem(from: Int, to: Int) -> AnyPublisher<Void, AudioError> {
        return Just(()).setFailureType(to: AudioError.self).eraseToAnyPublisher()
    }
}