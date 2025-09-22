# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Resonance is a modern Swift Package Manager library providing advanced audio streaming and playback capabilities. The project has been extensively modernized to use functional programming patterns with Apple's Combine framework, replacing legacy callback-based architecture.

**Supported Platforms**: iOS 10+, tvOS 10+, macOS 11+

## Development Commands

### Building and Testing
```bash
# Build the Swift package
swift build -v

# Run tests
swift test -v

# Build and run example app (requires CocoaPods)
cd Example
pod install
# Then open Resonance.xcodeproj in Xcode
```

### Package Management
- **Primary**: Swift Package Manager with dependencies on swift-collections and swift-atomics
- **Distribution**: CocoaPods (.podspec) and Carthage support for legacy projects
- **CI/CD**: GitHub Actions workflow runs `swift build` and `swift test` on macOS

## Modern Architecture (Post-Combine Migration)

### Core Reactive System
The library has been modernized from callback-based directors to a reactive Combine-based architecture:

**Central Reactive Hub**: `AudioUpdates.swift`
```swift
public struct AudioUpdates {
  public let playingStatus: CurrentValueSubject<SAPlayingStatus, Never>
  public let elapsedTime: CurrentValueSubject<TimeInterval, Never>
  public let duration: CurrentValueSubject<TimeInterval, Never>
  public let streamingBuffer: CurrentValueSubject<SAAudioAvailabilityRange?, Never>
  public let audioDownloading: CurrentValueSubject<Double, Never>
  public let streamingDownloadProgress: CurrentValueSubject<(url: URL, progress: Double)?, Never>
  public let audioQueue: CurrentValueSubject<URL?, Never>
}
```

### Eliminated Legacy Patterns
The modernization **removed 861 lines** of legacy director pattern code:
- ❌ `AudioClockDirector` - manual subscription management
- ❌ `AudioQueueDirector` - imperative queue updates
- ❌ `DownloadProgressDirector` - callback-based progress tracking
- ❌ `StreamingDownloadDirector` - manual stream coordination
- ❌ Manual subscription ID management and memory cleanup

### Modern Functional Patterns

#### Dependency Injection
```swift
// Modern constructor injection
player = AudioStreamEngine(
  withRemoteUrl: url,
  delegate: presenter,
  bitrate: bitrate,
  updates: updates,  // ← Combine publishers injected
  audioModifiers: audioModifiers
)
```

#### Reactive Data Flow
```swift
// Subscribe to updates using Combine
SAPlayer.shared.updates.playingStatus
  .sink { status in
    // Handle status changes reactively
  }
  .store(in: &cancellables)
```

### Thread Safety with Swift Atomics
Custom atomic operations for performance-critical sections:

**File**: `DoubleAtomics.swift`
- Extends `Double` to conform to `AtomicValue`
- Thread-safe audio position/timing operations
- Uses Apple's Atomics framework for lock-free operations

### Audio Engine Architecture

**Protocol-Based Design**: All engines implement `AudioEngineProtocol`

**Specialized Engines**:
- `AudioStreamEngine`: Handles streaming audio from remote URLs with real-time conversion
- `AudioDiskEngine`: Optimized for local audio file playback
- `AudioThrottler`: Performance optimization and resource management

**Audio Processing Pipeline**:
1. **Streaming**: AudioToolbox APIs (AudioFileStream, AudioConverter) convert incoming data
2. **Real-time**: AVAudioEngine processes converted PCM data
3. **Effects**: AVAudioUnit nodes in `audioModifiers` array for real-time manipulation
4. **Updates**: Direct publishing to Combine subjects for reactive UI updates

### Data Models

**Simplified Data Flow**:
- `StreamProgress`: Clean data transfer object (replaced legacy PTO/DTO pattern)
- `AudioDataManager`: Central coordination with Combine integration
- `AudioQueue`: Manages autoplay queue with reactive updates

## Development Patterns

### Real-time Audio Effects
Effects must be added to `audioModifiers` array **before** audio initialization:

```swift
// Add effects before initialization
let reverb = AVAudioUnitReverb()
SAPlayer.shared.audioModifiers.append(reverb)

// Then initialize audio
SAPlayer.shared.startRemoteAudio(withRemoteUrl: url)

// Real-time manipulation
reverb.wetDryMix = newValue // Applied immediately
```

### Reactive UI Integration
Use Combine for declarative UI updates:

```swift
// Streaming progress
SAPlayer.shared.updates.streamingBuffer
  .compactMap { $0?.bufferingProgress }
  .assign(to: \.progress, on: progressView)
  .store(in: &cancellables)

// Playback time
SAPlayer.shared.updates.elapsedTime
  .filter { $0 >= 0 }
  .sink { [weak self] time in
    self?.updateTimeDisplay(time)
  }
  .store(in: &cancellables)
```

### Cross-Platform Development
The codebase uses conditional compilation for iOS/macOS differences:

```swift
#if os(iOS)
// iOS-specific implementations
#elseif os(macOS)
// macOS-specific implementations
#endif
```

### Performance Considerations
- **Lock-free Operations**: Uses Swift Atomics for high-frequency updates
- **Minimal CPU Usage**: Optimized to use only 1-2% CPU during playback
- **Memory Efficiency**: Combine's automatic subscription management prevents leaks
- **Background Processing**: Dedicated workers for streaming and downloading

## API Usage Patterns

### Basic Playback
```swift
// Remote streaming
SAPlayer.shared.startRemoteAudio(withRemoteUrl: url)
SAPlayer.shared.play()

// Local playback
SAPlayer.shared.startSavedAudio(withSavedUrl: localUrl)
SAPlayer.shared.play()
```

### Reactive Subscriptions
```swift
// Modern Combine approach
let cancellables = Set<AnyCancellable>()

SAPlayer.shared.updates.playingStatus
  .sink { status in
    switch status {
    case .playing: updateUI(for: .playing)
    case .paused: updateUI(for: .paused)
    case .buffering: updateUI(for: .loading)
    case .ended: updateUI(for: .finished)
    }
  }
  .store(in: &cancellables)
```

### Download Management
```swift
// Download with progress tracking
SAPlayer.shared.downloader.downloadAudio(withRemoteUrl: url) { savedUrl in
  // Handle completion
}

// Track download progress reactively
SAPlayer.shared.updates.audioDownloading
  .sink { progress in
    progressBar.progress = Float(progress)
  }
  .store(in: &cancellables)
```

## Testing Considerations
- **Reactive Testing**: Use Combine's testing utilities for verifying publisher behavior
- **Engine Mocking**: Protocol-based engine design enables easy mocking
- **Atomic Operations**: Swift Atomics provide deterministic testing of concurrent operations
- **CI Integration**: GitHub Actions runs tests automatically on push/PR

## Future Development Guidelines
- **Maintain Reactive Patterns**: Continue using Combine for new features
- **Avoid Legacy Patterns**: Don't reintroduce director pattern or manual subscription management
- **Performance First**: Use Swift Atomics for high-frequency operations
- **Type Safety**: Leverage Combine's type system for compile-time guarantees
- **Functional Composition**: Prefer declarative over imperative approaches