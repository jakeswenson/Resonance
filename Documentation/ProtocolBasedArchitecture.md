# Protocol-Based Architecture Guide

## Overview

Resonance's modern architecture is built on focused protocols that can be composed together to create audio players with exactly the capabilities your application needs. This guide demonstrates how to use the protocol-based approach effectively.

## Core Architecture Principles

### 1. Protocol Composition
Rather than inheriting from a monolithic class, Resonance uses protocol composition:

```swift
import Resonance

// Basic playback only
let basicPlayer: AudioPlayable = BasicAudioPlayer()

// Full-featured player
let advancedPlayer: AudioPlayable & AudioConfigurable & AudioEffectable = AdvancedAudioPlayer()

// Custom composition
let downloadPlayer: AudioPlayable & AudioDownloadable = createCustomPlayer()
```

### 2. Reactive State Management
All protocols expose state through Combine publishers:

```swift
import Combine

let player = createResonancePlayer()
var cancellables = Set<AnyCancellable>()

// React to playback state changes
player.playbackStatePublisher
    .sink { state in
        switch state {
        case .playing:
            updateUI(for: .playing)
        case .paused:
            updateUI(for: .paused)
        case .stopped:
            updateUI(for: .stopped)
        case .buffering:
            showLoadingIndicator()
        }
    }
    .store(in: &cancellables)
```

### 3. Async/Await First
All operations use modern Swift concurrency:

```swift
// Clean async/await syntax
do {
    try await player.loadAudio(from: audioURL, metadata: metadata)
    try await player.play()
} catch {
    handleError(error)
}
```

## Protocol Reference

### AudioPlayable - Core Playback

The foundation protocol for all audio players:

```swift
// Basic usage
let player = BasicAudioPlayer()

// Load and play audio
try await player.loadAudio(from: audioURL, metadata: metadata)
try await player.play()

// Control playback
try await player.pause()
try await player.seek(to: 30.0) // Seek to 30 seconds

// Observe state changes
player.playbackStatePublisher
    .sink { state in
        print("Playback state: \(state)")
    }
    .store(in: &cancellables)
```

#### Reactive State Observation

```swift
// Monitor playback progress
player.playbackStatePublisher
    .compactMap { state in
        if case .playing = state { return true }
        return false
    }
    .sink { isPlaying in
        playButton.setTitle(isPlaying ? "Pause" : "Play", for: .normal)
    }
    .store(in: &cancellables)
```

### AudioConfigurable - Quality Control

Configure audio quality and buffering behavior:

```swift
guard let configurablePlayer = player as? AudioConfigurable else {
    fatalError("Player doesn't support configuration")
}

// Set audio quality
try await configurablePlayer.configure(
    quality: .high,        // .low, .standard, .high, .lossless
    bufferSize: .large     // .small, .medium, .large, .custom(Int)
)

// Volume control (if supported)
await configurablePlayer.setVolume(0.8)
await configurablePlayer.setMute(false)

// Playback rate control
await configurablePlayer.setPlaybackRate(1.25) // 1.25x speed
```

### AudioDownloadable - Offline Capabilities

Manage audio downloads for offline playback:

```swift
guard let downloadPlayer = player as? AudioDownloadable else {
    fatalError("Player doesn't support downloads")
}

// Download audio for offline use
do {
    let localURL = try await downloadPlayer.downloadAudio(from: remoteURL)
    print("Downloaded to: \(localURL)")
} catch {
    print("Download failed: \(error)")
}

// Monitor download progress
downloadPlayer.downloadProgressPublisher
    .sink { progress in
        progressBar.progress = Float(progress)
    }
    .store(in: &cancellables)

// Check if audio is available offline
if await downloadPlayer.isAvailableOffline(remoteURL) {
    // Use cached version
    try await downloadPlayer.loadCachedAudio(from: remoteURL)
}
```

### AudioEffectable - Real-Time Effects

Add and manage audio effects:

```swift
guard let effectPlayer = player as? AudioEffectable else {
    fatalError("Player doesn't support effects")
}

// Add reverb effect
let reverb = try await effectPlayer.addEffect(.reverb(wetDryMix: 0.5))

// Add delay effect
let delay = try await effectPlayer.addEffect(.delay(time: 0.3, feedback: 0.4))

// Add EQ
let eq = try await effectPlayer.addEffect(.equalizer(bands: [0, -2, -4, 2, 4]))

// Modify effects in real-time
if let reverbUnit = reverb as? AVAudioUnitReverb {
    reverbUnit.wetDryMix = 0.8 // Changes immediately
}

// Remove effects
try await effectPlayer.removeEffect(reverb)
```

### AudioQueueManageable - Playlist Management

Manage playback queues and playlists:

```swift
guard let queuePlayer = player as? AudioQueueManageable else {
    fatalError("Player doesn't support queue management")
}

// Add tracks to queue
try await queuePlayer.addToQueue(trackURL1, metadata: metadata1)
try await queuePlayer.addToQueue(trackURL2, metadata: metadata2)

// Observe queue changes
queuePlayer.currentQueuePublisher
    .sink { queue in
        updateQueueUI(with: queue)
    }
    .store(in: &cancellables)

// Queue management
try await queuePlayer.removeFromQueue(at: 1)
try await queuePlayer.moveInQueue(from: 0, to: 2)
try await queuePlayer.clearQueue()

// Playback control
try await queuePlayer.skipToNext()
try await queuePlayer.skipToPrevious()
```

### AudioEngineAccessible - Advanced Control

Direct access to AVAudioEngine for custom processing:

```swift
guard let enginePlayer = player as? AudioEngineAccessible else {
    fatalError("Player doesn't support engine access")
}

// Access the audio engine
let audioEngine = enginePlayer.audioEngine

// Perform custom operations
try await enginePlayer.accessEngine { engine in
    // Add custom nodes
    let customProcessor = AVAudioUnitEffect()
    engine.attach(customProcessor)

    // Custom routing
    engine.connect(engine.mainMixerNode, to: customProcessor, format: nil)

    return customProcessor
}
```

## Factory Pattern Usage

### Creating Players with Specific Capabilities

```swift
import Resonance

// Using the factory for precise capability control
let capabilities: AudioPlayerFactory.Capabilities = [.playback, .effects, .downloads]
let player = AudioPlayerFactory.createPlayer(with: capabilities)

// Type-safe capability checking
if let effectPlayer = player as? AudioEffectable {
    // Add effects
    let reverb = try await effectPlayer.addEffect(.reverb(wetDryMix: 0.3))
}

// Convenience methods
let basicPlayer = Resonance.createBasicPlayer()      // AudioPlayable only
let advancedPlayer = Resonance.createAdvancedPlayer() // All capabilities
```

### Custom Factory Implementation

```swift
struct CustomAudioPlayerFactory {
    static func createStreamingPlayer() -> any AudioPlayable & AudioConfigurable {
        let player = AdvancedAudioPlayer()

        // Pre-configure for streaming
        Task {
            try await player.configure(quality: .high, bufferSize: .large)
        }

        return player
    }

    static func createOfflinePlayer() -> any AudioPlayable & AudioDownloadable {
        return AdvancedAudioPlayer()
    }

    static func createEffectsPlayer() -> any AudioPlayable & AudioEffectable {
        return AdvancedAudioPlayer()
    }
}
```

## Real-World Examples

### Music Player App

```swift
import SwiftUI
import Combine
import Resonance

@MainActor
class MusicPlayerViewModel: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTrack: Track?
    @Published var playbackProgress: Double = 0
    @Published var downloadProgress: Double = 0

    private let player: any AudioPlayable & AudioDownloadable & AudioEffectable
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Create full-featured player
        self.player = Resonance.createAdvancedPlayer()
        setupBindings()
    }

    private func setupBindings() {
        // Bind playback state
        player.playbackStatePublisher
            .map { $0 == .playing }
            .assign(to: &$isPlaying)

        // Bind download progress if available
        if let downloadable = player as? AudioDownloadable {
            downloadable.downloadProgressPublisher
                .assign(to: &$downloadProgress)
        }
    }

    func play(track: Track) async {
        currentTrack = track

        do {
            // Check if available offline first
            if let downloadable = player as? AudioDownloadable,
               await downloadable.isAvailableOffline(track.url) {
                try await downloadable.loadCachedAudio(from: track.url)
            } else {
                try await player.loadAudio(from: track.url, metadata: track.metadata)
            }

            try await player.play()
        } catch {
            handleError(error)
        }
    }

    func addReverb() async {
        guard let effectPlayer = player as? AudioEffectable else { return }

        do {
            _ = try await effectPlayer.addEffect(.reverb(wetDryMix: 0.4))
        } catch {
            handleError(error)
        }
    }

    func downloadForOffline() async {
        guard let track = currentTrack,
              let downloadable = player as? AudioDownloadable else { return }

        do {
            let localURL = try await downloadable.downloadAudio(from: track.url)
            print("Downloaded: \(localURL)")
        } catch {
            handleError(error)
        }
    }

    private func handleError(_ error: Error) {
        print("Audio error: \(error)")
    }
}
```

### Podcast Player

```swift
import Combine
import Resonance

class PodcastPlayer: ObservableObject {
    @Published var currentEpisode: PodcastEpisode?
    @Published var isPlaying = false
    @Published var playbackRate: Float = 1.0
    @Published var sleepTimerActive = false

    private let player: any AudioPlayable & AudioConfigurable & AudioQueueManageable
    private var cancellables = Set<AnyCancellable>()
    private var sleepTimer: Timer?

    init() {
        // Create player with podcast-specific capabilities
        self.player = AudioPlayerFactory.createPlayer(with: [.playback, .configuration, .queue])
        setupPodcastBindings()
    }

    private func setupPodcastBindings() {
        player.playbackStatePublisher
            .map { $0 == .playing }
            .assign(to: &$isPlaying)
    }

    func playEpisode(_ episode: PodcastEpisode) async {
        currentEpisode = episode

        do {
            // Configure for voice content
            if let configurable = player as? AudioConfigurable {
                try await configurable.configure(quality: .standard, bufferSize: .medium)
                await configurable.setPlaybackRate(playbackRate)
            }

            try await player.loadAudio(from: episode.audioURL, metadata: episode.metadata)
            try await player.play()
        } catch {
            handleError(error)
        }
    }

    func setPlaybackRate(_ rate: Float) async {
        playbackRate = rate

        if let configurable = player as? AudioConfigurable {
            await configurable.setPlaybackRate(rate)
        }
    }

    func setSleepTimer(minutes: Int) {
        sleepTimerActive = true
        sleepTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { _ in
            Task {
                try await self.player.pause()
                await MainActor.run {
                    self.sleepTimerActive = false
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        print("Podcast error: \(error)")
    }
}
```

### Game Audio Manager

```swift
import Combine
import Resonance

@MainActor
class GameAudioManager: ObservableObject {
    private let musicPlayer: any AudioPlayable & AudioEffectable
    private let sfxPlayer: any AudioPlayable & AudioQueueManageable

    @Published var musicVolume: Float = 1.0
    @Published var sfxVolume: Float = 1.0
    @Published var environmentalEffectsEnabled = true

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Separate players for music and sound effects
        self.musicPlayer = Resonance.createAdvancedPlayer()
        self.sfxPlayer = Resonance.createAdvancedPlayer()

        setupGameAudio()
    }

    private func setupGameAudio() {
        // Configure music player with ambient effects
        Task {
            if let configurable = musicPlayer as? AudioConfigurable {
                try await configurable.configure(quality: .high, bufferSize: .large)
            }
        }
    }

    func playBackgroundMusic(_ musicURL: URL) async {
        do {
            try await musicPlayer.loadAudio(from: musicURL, metadata: nil)
            try await musicPlayer.play()

            // Add ambient reverb for atmosphere
            if environmentalEffectsEnabled,
               let effectPlayer = musicPlayer as? AudioEffectable {
                _ = try await effectPlayer.addEffect(.reverb(wetDryMix: 0.2))
            }
        } catch {
            print("Music playback error: \(error)")
        }
    }

    func playSoundEffect(_ sfxURL: URL) async {
        do {
            // Queue sound effect for immediate playback
            if let queuePlayer = sfxPlayer as? AudioQueueManageable {
                try await queuePlayer.addToQueue(sfxURL, metadata: nil)
            } else {
                try await sfxPlayer.loadAudio(from: sfxURL, metadata: nil)
                try await sfxPlayer.play()
            }
        } catch {
            print("SFX playback error: \(error)")
        }
    }

    func setMusicVolume(_ volume: Float) async {
        musicVolume = volume

        if let configurable = musicPlayer as? AudioConfigurable {
            await configurable.setVolume(volume)
        }
    }

    func enableEnvironmentalEffects(_ enabled: Bool) async {
        environmentalEffectsEnabled = enabled

        if let effectPlayer = musicPlayer as? AudioEffectable {
            // Implementation would manage environmental effects
        }
    }
}
```

## Performance Considerations

### Memory Management

```swift
// Proper cancellable management
class AudioController {
    private var cancellables = Set<AnyCancellable>()

    func setupPlayer() {
        player.playbackStatePublisher
            .sink { state in /* handle state */ }
            .store(in: &cancellables) // Automatic cleanup
    }

    deinit {
        cancellables.removeAll() // Explicit cleanup
    }
}
```

### Efficient Protocol Usage

```swift
// Check capabilities once and store references
class EfficientAudioManager {
    private let player: any AudioPlayable
    private let configurablePlayer: (any AudioConfigurable)?
    private let effectablePlayer: (any AudioEffectable)?

    init(player: any AudioPlayable) {
        self.player = player
        self.configurablePlayer = player as? AudioConfigurable
        self.effectablePlayer = player as? AudioEffectable
    }

    func configure() async {
        // Efficient - no repeated casting
        if let configurable = configurablePlayer {
            try await configurable.configure(quality: .high, bufferSize: .large)
        }
    }
}
```

## Migration Strategy

See [Migration Examples](../Examples/Migration/) for detailed migration guides from legacy SAPlayer to the new protocol-based architecture.

## Best Practices

1. **Use Type Composition**: Combine only the protocols you need
2. **Reactive State Management**: Leverage Combine publishers for UI updates
3. **Async/Await**: Use modern concurrency for all operations
4. **Error Handling**: Properly handle and propagate audio errors
5. **Memory Management**: Use proper cancellable storage
6. **Testing**: Mock protocols for unit testing

## Conclusion

The protocol-based architecture provides flexibility, type safety, and performance while maintaining clean separation of concerns. Choose the protocols that match your application's needs and compose them as required.