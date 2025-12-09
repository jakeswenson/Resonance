# Research: Protocol-Based Audio Architecture

**Generated**: 2025-09-28
**Input**: Phase 0 research requirements from plan.md

## Protocol-Oriented Functional Patterns for Audio Streaming

### Decision: Hierarchical Protocol Design with Progressive Disclosure
Use a three-tier protocol hierarchy: Basic → Enhanced → Advanced, where each level adds capabilities without breaking simpler conformances.

### Rationale:
- Allows developers to start with minimal API surface (`AudioPlayable`)
- Progressive adoption through protocol composition (`AudioPlayable & AudioConfigurable`)
- Maintains backwards compatibility while enabling feature growth
- Follows Swift's standard library patterns (e.g., `Collection` → `BidirectionalCollection` → `RandomAccessCollection`)

### Alternatives Considered:
- **Single monolithic protocol**: Rejected - forces complexity on simple use cases
- **Separate unrelated protocols**: Rejected - loses cohesion and discoverability
- **Factory pattern with complexity levels**: Rejected - less type-safe than protocols

### Implementation Pattern:
```swift
// Tier 1: Basic playback
protocol AudioPlayable {
    func play() async throws
    func pause()
    var isPlaying: Bool { get }
}

// Tier 2: Enhanced features
protocol AudioConfigurable: AudioPlayable {
    func setPlaybackRate(_ rate: Float) async throws
    func seek(to time: TimeInterval) async throws
}

// Tier 3: Advanced control
protocol AudioEffectable: AudioConfigurable {
    var effects: [AudioEffect] { get set }
    func addEffect(_ effect: AudioEffect) async throws
}
```

## Swift 6 Actor Isolation Patterns for Real-Time Audio

### Decision: Dedicated Audio Session Actor with Main Actor UI Coordination
Use specialized actors for audio engine operations while keeping UI updates on MainActor.

### Rationale:
- Audio processing requires dedicated threads to avoid Main thread blocking
- Swift 6 actor isolation prevents data races in audio state management
- `@MainActor` ensures UI updates happen on main thread without manual dispatch
- Sendable types enable safe data transfer between actor contexts

### Alternatives Considered:
- **Everything on MainActor**: Rejected - blocks UI during audio processing
- **Manual GCD queues**: Rejected - Swift 6 actors provide better safety guarantees
- **No actor isolation**: Rejected - creates data race conditions in audio state

### Implementation Pattern:
```swift
@available(iOS 15.0, *)
actor AudioSessionActor {
    private var audioEngine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    func configureSession() async throws {
        // Audio configuration happens on actor's serial executor
    }

    nonisolated var statePublisher: AnyPublisher<AudioState, Never> {
        // Publishers can be accessed from any context
    }
}

@MainActor
class AudioPresenter {
    private let sessionActor = AudioSessionActor()

    func playAudio() {
        Task {
            try await sessionActor.configureSession()
            // UI updates happen on MainActor automatically
        }
    }
}
```

## Combine Reactive Patterns for Audio State Management

### Decision: Central Updates Hub with Specialized Publishers
Use a single `AudioUpdates` struct containing all reactive streams, following the hub pattern.

### Rationale:
- Centralizes all audio-related reactive streams in one discoverable location
- `CurrentValueSubject` maintains latest state for immediate access
- `PassthroughSubject` for events that don't need state retention
- Enables composition and transformation of multiple audio streams

### Alternatives Considered:
- **Distributed publishers across classes**: Rejected - harder to discover and coordinate
- **Single combined publisher**: Rejected - loses type safety and granular subscriptions
- **Callback-based patterns**: Rejected - less composable than reactive streams

### Implementation Pattern:
```swift
public struct AudioUpdates {
    public let playingStatus = CurrentValueSubject<PlayingStatus, Never>(.stopped)
    public let elapsedTime = CurrentValueSubject<TimeInterval, Never>(0)
    public let duration = CurrentValueSubject<TimeInterval, Never>(0)
    public let downloadProgress = PassthroughSubject<Double, Never>()
    public let errors = PassthroughSubject<AudioError, Never>()
}

// Usage enables powerful composition:
updates.playingStatus
    .combineLatest(updates.elapsedTime)
    .sink { status, time in
        updateUI(status: status, time: time)
    }
    .store(in: &cancellables)
```

## Cross-Platform Audio Development Patterns

### Decision: Conditional Compilation with Unified Abstractions
Use `#if os()` for platform-specific implementations behind unified protocol interfaces.

### Rationale:
- iOS/tvOS share AVAudioSession APIs, macOS has different audio session model
- Swift Package Manager enables clean platform targeting
- Protocol abstractions hide platform differences from consumers
- Maintains single codebase with platform-specific optimizations

### Alternatives Considered:
- **Separate platform frameworks**: Rejected - increases maintenance burden
- **Runtime platform detection**: Rejected - less efficient than compile-time selection
- **Lowest common denominator**: Rejected - loses platform-specific capabilities

### Implementation Pattern:
```swift
protocol AudioSessionManaging {
    func configure() async throws
    func activate() async throws
    var statePublisher: AnyPublisher<SessionState, Never> { get }
}

#if os(iOS) || os(tvOS)
final class iOSAudioSessionManager: AudioSessionManaging {
    func configure() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback)
    }
}
#elseif os(macOS)
final class macOSAudioSessionManager: AudioSessionManaging {
    func configure() async throws {
        // macOS-specific audio configuration
    }
}
#endif
```

## Progressive API Design Patterns

### Decision: Protocol Extension Progressive Disclosure
Use protocol extensions to add functionality layers while maintaining simple base contracts.

### Rationale:
- Base protocols remain minimal and focused
- Extensions add convenience methods without complexity
- Default implementations reduce boilerplate for implementers
- Enables "pay for what you use" API design

### Alternatives Considered:
- **Builder pattern complexity levels**: Rejected - less discoverable than protocols
- **Separate classes per complexity**: Rejected - breaks type relationships
- **Configuration objects**: Rejected - runtime configuration vs compile-time protocols

### Implementation Pattern:
```swift
protocol AudioPlayable {
    func play() async throws
    func pause()
    var isPlaying: Bool { get }
}

extension AudioPlayable {
    // Convenience methods for common patterns
    func togglePlayback() async throws {
        if isPlaying {
            pause()
        } else {
            try await play()
        }
    }
}

protocol AudioConfigurable: AudioPlayable {
    func setRate(_ rate: Float) async throws
    func seek(to time: TimeInterval) async throws
}

extension AudioConfigurable {
    // Enhanced convenience methods
    func skipForward(_ seconds: TimeInterval = 30) async throws {
        // Implementation using base protocol methods
    }
}
```

## Architecture Integration Recommendations

### Swift 6 Concurrency + Combine Integration
- Use actors for audio engine management
- Expose reactive streams as `nonisolated` computed properties
- Leverage `@MainActor` for UI coordination
- Use `Sendable` types for safe actor communication

### Performance Optimization Patterns
- Swift Atomics for high-frequency operations (time updates, buffer states)
- Actor isolation prevents lock contention in audio processing
- Combine debouncing for UI updates to prevent excessive rendering
- Memory-mapped audio files for large local playback

### Testing Strategy
- Protocol-based dependency injection enables easy mocking
- Contract tests verify protocol conformance behavior
- Integration tests validate cross-platform compatibility
- Performance tests ensure real-time constraints are met

## Implementation Priority

1. **Foundation Protocols**: Define basic protocol hierarchy (`AudioPlayable` → `AudioConfigurable` → `AudioEffectable`)
2. **Actor Infrastructure**: Implement `AudioSessionActor` with cross-platform session management
3. **Reactive Integration**: Connect actors to `AudioUpdates` hub with proper isolation
4. **Progressive Enhancement**: Add protocol extensions for convenience methods
5. **Cross-Platform Testing**: Validate behavior across iOS/tvOS/macOS

---
*Research completed: 2025-09-28*
*Ready for Phase 1 design and contracts generation*