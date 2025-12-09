# Data Model: Protocol-Based Audio Architecture

## Core Entity Definitions

### AudioSession
**Purpose**: Represents an active audio playback session with reactive state management
**Fields**:
- `id: UUID` - Unique session identifier
- `url: URL` - Source audio URL (remote or local)
- `metadata: AudioMetadata?` - Optional title, artwork, duration information
- `state: PlaybackState` - Current playback status
- `progress: TimeInterval` - Current playback position
- `duration: TimeInterval` - Total audio duration (may update for streaming)

**Relationships**: One-to-many with AudioEffects, One-to-one with DownloadTask (if applicable)

**State Transitions**:
- `.idle` → `.loading` → `.ready` → `.playing`
- `.playing` ⇄ `.paused`
- Any state → `.error` → `.idle`
- `.playing`/`.paused` → `.completed` → `.idle`

### AudioMetadata
**Purpose**: Immutable audio content information
**Fields**:
- `title: String?`
- `artist: String?`
- `artwork: Data?` - Image data for lock screen display
- `chapters: [ChapterInfo]` - For podcast chapter navigation
- `releaseDate: Date?`

**Validation Rules**: All fields optional, but title recommended for meaningful display

### PlaybackState
**Purpose**: Enumeration of possible audio session states
**Values**:
- `.idle` - No audio loaded
- `.loading` - Audio being prepared/buffered
- `.ready` - Audio ready for playback
- `.playing` - Currently playing
- `.paused` - Paused by user
- `.buffering` - Temporarily pausing for network buffering
- `.completed` - Playback finished
- `.error(AudioError)` - Playback failed with specific error

### DownloadTask
**Purpose**: Represents background download operation with progress tracking
**Fields**:
- `id: UUID` - Unique download identifier
- `remoteUrl: URL` - Source URL for download
- `localUrl: URL?` - Destination path when complete
- `progress: Double` - Download progress (0.0 to 1.0)
- `state: DownloadState` - Current download status
- `totalBytes: Int64?` - Expected download size
- `downloadedBytes: Int64` - Current downloaded amount

**State Transitions**:
- `.pending` → `.downloading` → `.completed`
- `.downloading` → `.paused` → `.downloading`
- Any state → `.failed` → `.pending` (retry)

### AudioEffect
**Purpose**: Represents configurable audio processing effects
**Fields**:
- `id: UUID` - Unique effect identifier
- `type: EffectType` - Kind of audio effect
- `parameters: [String: Any]` - Effect-specific configuration
- `isEnabled: Bool` - Whether effect is currently active

**Effect Types**:
- `.timePitch(rate: Float, pitch: Float)` - Speed/pitch manipulation
- `.reverb(wetDryMix: Float)` - Reverb effect
- `.equalizer(bands: [EQBand])` - Frequency equalization
- `.custom(node: AVAudioUnit)` - User-provided audio unit

## Protocol Hierarchy Design

### Tier 1: Basic Playback (AudioPlayable)
**Minimal API for simple use cases**
```swift
protocol AudioPlayable {
    func play() async throws
    func pause()
    var isPlaying: Bool { get }
    var updates: AudioUpdates { get }
}
```

### Tier 2: Enhanced Features (AudioConfigurable)
**Adds configuration and control**
```swift
protocol AudioConfigurable: AudioPlayable {
    func setPlaybackRate(_ rate: Float) async throws
    func seek(to time: TimeInterval) async throws
    func setVolume(_ volume: Float) async throws
    var configuration: AudioConfiguration { get set }
}
```

### Tier 3: Advanced Control (AudioEffectable)
**Adds audio effects and processing**
```swift
protocol AudioEffectable: AudioConfigurable {
    var effects: [AudioEffect] { get set }
    func addEffect(_ effect: AudioEffect) async throws
    func removeEffect(withId id: UUID) async throws
    func reorderEffects(_ effectIds: [UUID]) async throws
}
```

### Tier 4: Queue Management (AudioQueueManageable)
**Adds playlist and queue features**
```swift
protocol AudioQueueManageable: AudioEffectable {
    var queue: AudioQueue { get }
    func enqueue(_ url: URL) async throws
    func playNext() async throws
    func playPrevious() async throws
}
```

### Tier 5: Download Management (AudioDownloadable)
**Adds offline capabilities**
```swift
protocol AudioDownloadable: AudioQueueManageable {
    func downloadAudio(from url: URL) async throws -> URL
    func cancelDownload(for url: URL) async throws
    var downloadTasks: [DownloadTask] { get }
}
```

## Reactive Data Flow

### Publishers (Output)
- `playbackState: CurrentValueSubject<PlaybackState, Never>`
- `playbackProgress: CurrentValueSubject<TimeInterval, Never>`
- `audioDuration: CurrentValueSubject<TimeInterval, Never>`
- `downloadProgress: CurrentValueSubject<[UUID: Double], Never>`
- `audioMetadata: CurrentValueSubject<AudioMetadata?, Never>`

### Commands (Input)
- `PlayCommand(sessionId: UUID)`
- `PauseCommand(sessionId: UUID)`
- `SeekCommand(sessionId: UUID, position: TimeInterval)`
- `LoadAudioCommand(url: URL, metadata: AudioMetadata?)`
- `ApplyEffectCommand(effect: AudioEffect)`

## Thread Safety Considerations

All data models are value types (structs) for immutability. State mutations occur only through designated actors:
- `AudioSessionActor` - Manages playback state
- `DownloadManagerActor` - Handles download operations
- `EffectProcessorActor` - Manages real-time effects

This ensures Swift 6 strict concurrency compliance while maintaining performance.