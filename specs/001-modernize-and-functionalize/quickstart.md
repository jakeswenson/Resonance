# Quickstart: Protocol-Based Audio Library

## 3-Line Basic Integration (AudioPlayable)

```swift
import Resonance

// Simple podcast streaming in 3 lines
let player = BasicAudioPlayer()
player.loadAudio(from: podcastURL, metadata: nil)
player.play()
```

## Progressive Protocol Adoption Examples

### Level 1: Basic Playback (AudioPlayable)
```swift
import Combine

class SimplePodcastPlayer {
    private let audioPlayer: AudioPlayable
    private var cancellables = Set<AnyCancellable>()

    init(audioPlayer: AudioPlayable) {
        self.audioPlayer = audioPlayer
        setupObservers()
    }

    func playPodcast(url: URL) {
        audioPlayer.loadAudio(from: url, metadata: nil)
            .flatMap { self.audioPlayer.play() }
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        print("Playback failed: \(error)")
                    }
                },
                receiveValue: { _ in
                    print("Playback started")
                }
            )
            .store(in: &cancellables)
    }

    private func setupObservers() {
        audioPlayer.playbackState
            .sink { state in
                print("Playback state: \(state)")
            }
            .store(in: &cancellables)
    }
}
```

### Level 2: Enhanced Features (AudioConfigurable)
```swift
class EnhancedPodcastPlayer {
    private let audioPlayer: AudioConfigurable
    private var cancellables = Set<AnyCancellable>()

    init(audioPlayer: AudioConfigurable) {
        self.audioPlayer = audioPlayer
        setupAdvancedObservers()
    }

    func playPodcastWithSpeed(url: URL, speed: Float = 1.5) {
        let metadata = AudioMetadata(
            title: "My Podcast Episode",
            artist: "Podcast Host"
        )

        audioPlayer.loadAudio(from: url, metadata: metadata)
            .flatMap { _ in
                self.audioPlayer.playbackRate = speed
                return self.audioPlayer.play()
            }
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in
                    print("Playing at \(speed)x speed")
                }
            )
            .store(in: &cancellables)
    }

    func setupSkipButtons() {
        // Skip forward 30 seconds
        audioPlayer.skipForward(duration: 30)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in print("Skipped forward") }
            )
            .store(in: &cancellables)
    }

    private func setupAdvancedObservers() {
        // Monitor buffering for streaming indicators
        audioPlayer.bufferStatus
            .compactMap { $0 }
            .sink { bufferStatus in
                print("Buffer progress: \(bufferStatus.bufferingProgress)")
            }
            .store(in: &cancellables)
    }
}
```

### Level 3: Offline Support (AudioDownloadable)
```swift
class OfflinePodcastPlayer {
    private let audioPlayer: AudioDownloadable & AudioConfigurable
    private var cancellables = Set<AnyCancellable>()

    init(audioPlayer: AudioDownloadable & AudioConfigurable) {
        self.audioPlayer = audioPlayer
        monitorDownloads()
    }

    func downloadAndPlay(url: URL) {
        // Check if already downloaded
        if let localURL = audioPlayer.localURL(for: url) {
            playLocalFile(localURL)
            return
        }

        // Download first, then play
        audioPlayer.downloadAudio(from: url, metadata: nil)
            .compactMap { progress in
                progress.state == .completed ? progress.localURL : nil
            }
            .flatMap { localURL in
                self.audioPlayer.loadAudio(from: localURL, metadata: nil)
            }
            .flatMap { _ in
                self.audioPlayer.play()
            }
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in print("Downloaded and playing") }
            )
            .store(in: &cancellables)
    }

    private func playLocalFile(_ url: URL) {
        audioPlayer.loadAudio(from: url, metadata: nil)
            .flatMap { self.audioPlayer.play() }
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in print("Playing offline") }
            )
            .store(in: &cancellables)
    }

    private func monitorDownloads() {
        audioPlayer.downloadProgress
            .sink { progressDict in
                for (url, progress) in progressDict {
                    print("Download \(url): \(progress.progress * 100)%")
                }
            }
            .store(in: &cancellables)
    }
}
```

### Level 4: Audio Effects (AudioEffectable)
```swift
class ProPodcastPlayer {
    private let audioPlayer: AudioEffectable
    private var cancellables = Set<AnyCancellable>()

    init(audioPlayer: AudioEffectable) {
        self.audioPlayer = audioPlayer
    }

    func playWithDynamicEQ(url: URL) {
        // Create custom EQ for voice enhancement
        let voiceEQ = AudioEffect(
            type: .equalizer,
            parameters: [
                EffectParameterKeys.bands: [
                    EQBand(frequency: 200, gain: -3.0),   // Reduce muddy lows
                    EQBand(frequency: 1000, gain: 2.0),   // Enhance vocal presence
                    EQBand(frequency: 3000, gain: 1.5),   // Add clarity
                    EQBand(frequency: 8000, gain: -1.0)   // Reduce harsh sibilants
                ]
            ],
            displayName: "Voice Enhancement"
        )

        audioPlayer.loadAudio(from: url, metadata: nil)
            .flatMap { _ in
                self.audioPlayer.addEffect(voiceEQ)
            }
            .flatMap { _ in
                self.audioPlayer.play()
            }
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in print("Playing with voice enhancement") }
            )
            .store(in: &cancellables)
    }

    func adjustEffectsRealtime() {
        // Real-time effect parameter changes
        audioPlayer.currentEffects
            .compactMap { effects in
                effects.first { $0.type == .equalizer }
            }
            .sink { eqEffect in
                // Dynamically adjust EQ based on content analysis
                self.audioPlayer.updateEffect(
                    id: eqEffect.id,
                    parameters: [
                        EffectParameterKeys.globalGain: 2.0
                    ]
                )
            }
            .store(in: &cancellables)
    }
}
```

### Level 5: Playlist Management (AudioQueueManageable)
```swift
class PlaylistPodcastPlayer {
    private let audioPlayer: AudioQueueManageable
    private var cancellables = Set<AnyCancellable>()

    init(audioPlayer: AudioQueueManageable) {
        self.audioPlayer = audioPlayer
        self.audioPlayer.autoAdvanceEnabled = true
        setupQueueObserver()
    }

    func createPodcastPlaylist(episodes: [(URL, AudioMetadata)]) {
        // Clear existing queue
        audioPlayer.clearQueue()
            .flatMap { _ in
                // Add all episodes to queue
                Publishers.Sequence(sequence: episodes)
                    .flatMap { episode in
                        self.audioPlayer.enqueue(url: episode.0, metadata: episode.1)
                    }
                    .collect()
            }
            .flatMap { _ in
                // Start playing first episode
                self.audioPlayer.playNext()
            }
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { _ in print("Playlist created and playing") }
            )
            .store(in: &cancellables)
    }

    private func setupQueueObserver() {
        audioPlayer.queue
            .sink { queue in
                print("Queue has \(queue.count) episodes")
                queue.forEach { item in
                    print("- \(item.metadata?.title ?? "Unknown Episode")")
                }
            }
            .store(in: &cancellables)
    }
}
```

## Migration from Legacy SAPlayer

### Before (Monolithic)
```swift
// Old monolithic approach - single massive object
SAPlayer.shared.startRemoteAudio(withRemoteUrl: url)
SAPlayer.shared.play()
SAPlayer.shared.rate = 1.5
SAPlayer.shared.skipForward()

// Direct engine access with no safety
SAPlayer.shared.engine?.attachNode(customNode)
```

### After (Protocol-Based)
```swift
// New protocol-based approach - progressive complexity
let player: AudioConfigurable = ResonanceAudioPlayer()

player.loadAudio(from: url, metadata: metadata)
    .flatMap { _ in
        player.playbackRate = 1.5
        return player.play()
    }
    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })

player.skipForward(duration: 30)

// Advanced features only when needed
if let advancedPlayer = player as? AudioEngineAccessible {
    advancedPlayer.insertAudioNode(customNode, at: .beforeOutput)
}
```

## Testing Validation Steps

1. **Basic Integration Test**: Verify 3-line integration compiles and runs
2. **Protocol Adoption Test**: Confirm each protocol level works independently
3. **Migration Test**: Validate common SAPlayer patterns have protocol equivalents
4. **Performance Test**: Ensure protocol overhead doesn't impact audio performance
5. **Combine Integration Test**: Verify reactive streams work correctly with SwiftUI/UIKit