# SwiftAudioPlayer

[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat)](https://github.com/jakeswenson/SwiftAudioPlayer/blob/master/LICENSE)
[![Swift Package Manager](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-brightgreen.svg)](https://github.com/apple/swift-package-manager)
[![Platform](https://img.shields.io/badge/Platform-iOS%2010%2B%20%7C%20tvOS%2010%2B%20%7C%20macOS%2011%2B-lightgrey.svg)](https://github.com/jakeswenson/SwiftAudioPlayer)

Modern Swift audio player built with **AVAudioEngine** and **Combine** for reactive programming. Features streaming audio, local file playback, real-time audio manipulation (3.5X, 4X, 32X speed), pitch control, and custom [audio enhancements](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements) using functional programming patterns.

**Platforms**: iOS 10+, tvOS 10+, macOS 11+

This player was built for [podcasting](https://chameleonpodcast.com/) using modern reactive programming with Apple's Combine framework. The architecture has been modernized from callback-based patterns to declarative, functional programming using Publishers and Subscribers for type-safe, reactive audio event handling.

Using [AudioToolbox](https://developer.apple.com/documentation/audiotoolbox) for streaming data conversion and AVAudioEngine for playback, combined with Combine for reactive data flow. For technical details see the original [blog post](https://medium.com/chameleon-podcast/creating-an-advanced-streaming-audio-engine-for-ios-9fbc7aef4115).

## Credits

This project is a modernized fork of the original [SwiftAudioPlayer](https://github.com/tanhakabir/SwiftAudioPlayer) by [Tanha Kabir](https://github.com/tanhakabir) and [Jon Mercer](https://github.com/JonMercer). The original work was built for [Chameleon Podcast](https://chameleonpodcast.com/). This fork focuses on modernizing the codebase with functional programming patterns, Combine framework integration, and Swift Package Manager support.

### Modern Features

1. **Reactive Programming**: Built with Combine framework for declarative, type-safe audio event handling
1. **Real-time Audio Effects**: Up to 10x speed manipulation using [AVAudioUnit effects](https://developer.apple.com/documentation/avfaudio/avaudiouniteq)
1. **Streaming & Local Playback**: Unified API for both remote streaming and local file playback using AVAudioEngine
1. **Cross-Platform**: iOS, tvOS, and macOS support with conditional compilation
1. **Background Downloads**: Automatic download management with reactive progress tracking
1. **Audio Queue**: Reactive autoplay queue for downloaded and streamed audio
1. **Performance Optimized**: Uses only 1-2% CPU with lock-free atomic operations
1. **Extensible**: Install AVAudioEngine taps and custom audio processing nodes
1. **Thread-Safe**: Swift Atomics for high-performance concurrent operations

### Special Features
These are community supported audio manipulation features using this audio engine. You can implement your own version of these features and you can look at [SAPlayerFeatures](https://github.com/tanhakabir/SwiftAudioPlayer/blob/master/Source/SAPlayerFeatures.swift) to learn how they were implemented using the library.
1. Skip silences in audio
1. Sleep timer to stop playing audio after a delay
1. Loop audio playback for both streamed and saved audio

### Requirements

- **iOS 10.0+**, **tvOS 10.0+**, **macOS 11.0+**
- **Swift 5.5+**
- **Xcode 13.0+**

## Getting Started

### Running the Example Project

1. Clone repo
2. CD to the `Example` folder where the Example app lives
3. Run `pod install` in terminal
4. Build and run

### Installation

#### Swift Package Manager
```swift
dependencies: [
    .package(url: "https://github.com/jakeswenson/SwiftAudioPlayer.git", from: "7.6.0")
]
```

### Usage

Import the player at the top:
```swift
import SwiftAudioPlayer
```

**Important:** For app in background downloading please refer to [note](#important-step-for-background-downloads).

To play remote audio:
```swift
let url = URL(string: "https://randomwebsite.com/audio.mp3")!
SAPlayer.shared.startRemoteAudio(withRemoteUrl: url)
SAPlayer.shared.play()
```

To set the display information for the lockscreen:
```swift
let info = SALockScreenInfo(title: "Random audio", artist: "Foo", artwork: UIImage(), releaseDate: 123456789)
SAPlayer.shared.mediaInfo = info
```

To receive streaming progress using modern Combine (reactive approach):
```swift
import Combine

@IBOutlet weak var bufferProgress: UIProgressView!
private var cancellables = Set<AnyCancellable>()

override func viewDidLoad() {
    super.viewDidLoad()

    // Reactive streaming buffer updates
    SAPlayer.shared.updates.streamingBuffer
        .compactMap { $0 }
        .sink { [weak self] buffer in
            self?.bufferProgress.progress = Float(buffer.bufferingProgress)
            self?.isPlayable = buffer.isReadyForPlaying
        }
        .store(in: &cancellables)
}
```


For realtime audio manipulations, [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/avaudiounit) nodes are used. For example to adjust the reverb through a slider in the UI:
```swift
@IBOutlet weak var reverbSlider: UISlider!

override func viewDidLoad() {
    super.viewDidLoad()

    let node = AVAudioUnitReverb()
    SAPlayer.shared.audioModifiers.append(node)
    node.wetDryMix = 300
}

@IBAction func reverbSliderChanged(_ sender: Any) {
    if let node = SAPlayer.shared.audioModifiers[1] as? AVAudioUnitReverb {
            node.wetDryMix = reverbSlider.value
        }
}
```
For a more detailed explanation on usage, look at the [Realtime Audio Manipulations](#realtime-audio-manipulation) section.

### Modern Reactive Examples

#### Multiple Reactive Subscriptions
```swift
import Combine

class AudioViewController: UIViewController {
    private var cancellables = Set<AnyCancellable>()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupReactiveSubscriptions()
    }

    private func setupReactiveSubscriptions() {
        // Playing status updates
        SAPlayer.shared.updates.playingStatus
            .sink { [weak self] status in
                self?.updatePlayButton(for: status)
            }
            .store(in: &cancellables)

        // Elapsed time updates
        SAPlayer.shared.updates.elapsedTime
            .filter { $0 >= 0 }
            .sink { [weak self] time in
                self?.updateTimeLabel(time)
            }
            .store(in: &cancellables)

        // Duration updates
        SAPlayer.shared.updates.duration
            .filter { $0 > 0 }
            .sink { [weak self] duration in
                self?.setupProgressSlider(maxValue: duration)
            }
            .store(in: &cancellables)

        // Download progress
        SAPlayer.shared.updates.audioDownloading
            .sink { [weak self] progress in
                self?.updateDownloadProgress(progress)
            }
            .store(in: &cancellables)
    }
}
```

For more details and specifics look at the [API documentation](#api-in-detail) below.


## Contact

### Issues or questions

Submit any issues, requests, and questions [on the Github repo](https://github.com/jakeswenson/SwiftAudioPlayer/issues).

### Original Project

For reference to the original implementation, see the [original SwiftAudioPlayer repository](https://github.com/tanhakabir/SwiftAudioPlayer).

### License

SwiftAudioPlayer is available under the MIT license. See the LICENSE file for more info.

---

# API in detail

## SAPlayer

Access the player and all of its fields and functions through `SAPlayer.shared`.

### Supported file types

Known supported file types are `.mp3` and `.wav`.

### Playing Audio (Basic Commands)

To set up player with audio to play, use either:
* `startSavedAudio(withSavedUrl url: URL, mediaInfo: SALockScreenInfo?)` to play audio that is saved on the device.
* `startRemoteAudio(withRemoteUrl url: URL, bitrate: SAPlayerBitrate, mediaInfo: SALockScreenInfo?)` to play audio streamed from a remote location.

Both of these expect a URL of the location of the audio and an optional media information to display on the lockscreen.  For streamed audio you can optionally set the bitrate to be `.high` or `.low`. High is more performant but won't work well for radio streams; for radio streams you should use low. The default bitrate if you don't set it is `.high`.

For streaming remote audio, subscribe to `SAPlayer.Updates.StreamingBuffer` for updates on streaming progress.

Basic controls available:
```swift
play()
pause()
togglePlayAndPause()
seekTo(seconds: Double)
skipForward()
skipBackwards()
```

### Queuing Audio for Autoplay

You can queue either remote or locally saved audio to be played automatically next.

To queue:
```swift
SAPlayer.shared.queueSavedAudio(withSavedUrl: C://random_folder/audio.mp3) // or
SAPlayer.shared.queueRemoteAudio(withRemoteUrl: https://randomwebsite.com/audio.mp3)
```

You can also directly access and modify the queue from `SAPlayer.shared.audioQueued`.

#### Important

The engine can handle audio manipulations like speed, pitch, effects, etc. To do this, nodes for effects must be finalized before initialize is called. Look at [audio manipulation documentation](#realtime-audio-manipulation) for more information.

### LockScreen Media Player

Update and set what displays on the lockscreen's media player when the player is active.

`skipForwardSeconds` and `skipBackwardSeconds` for the intervals to skip forward and back with.

`mediaInfo` for the audio's information to display on the lockscreen. Is of type `SALockScreenInfo` which contains:
```swift
title: String
artist: String
artwork: UIImage?
releaseDate: UTC // Int
```

`playbackRateOfAudioChanged(rate: Float)` is used to update the lockscreen media player that the playback rate has changed.

## SAPlayer.Downloader

Use functionaity from Downloader to save audio files from remote locations for future offline playback.

Audio files are saved under custom naming scheme on device and are recoverable with original remote URL for file.

#### Important step for background downloads

To ensure that your app will keep downloading audio in the background be sure to add the following to `AppDelegate.swift`:

```swift
func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
    SAPlayer.Downloader.setBackgroundCompletionHandler(completionHandler)
}
```

### Downloading

All downloads will be paused when audio is streamed from a URL. They will automatically resume when streaming is done.

Use the following to start downloading audio in the background:

```swift
func downloadAudio(withRemoteUrl url: URL, completion: @escaping (_ savedUrl: URL) -> ())
```

It will call the completion handler you pass after successful download with the location of the downloaded file on the device.

Subscribe to `SAPlayer.Updates.AudioDownloading` for downloading progress updates.

And use the following to stop any active or prevent future downloads of the corresponding remote URL:

```swift
func cancelDownload(withRemoteUrl url: URL)
```

By default downloading will be allowed on cellular data. If you would like to turn this off set:
```swift
SAPlayer.Downloader.allowUsingCellularData = false
```
You can also retrieve what preference you have set for cellular downloads through `allowUsingCellularData`.

### Manage Downloaded

Use the following to manage downloaded audio files.

Checks if downloaded already:
```swift
func isDownloaded(withRemoteUrl url: URL) -> Bool
```

Get URL of audio file saved on device corresponding to remote location:
```swift
func getSavedUrl(forRemoteUrl url: URL) -> URL?
```

Delete downloaded audio if it exists:
```swift
func deleteDownloaded(withSavedUrl url: URL)
```

**NOTE:** You're in charge or clearing downloads when your don't need them anymore

## Modern Reactive Updates with Combine

The player provides reactive updates through Combine Publishers. Access them via `SAPlayer.shared.updates`:

### Available Publishers

All publishers are `CurrentValueSubject` types that emit updates automatically:

```swift
// Playing status changes
SAPlayer.shared.updates.playingStatus: CurrentValueSubject<SAPlayingStatus, Never>

// Elapsed time updates
SAPlayer.shared.updates.elapsedTime: CurrentValueSubject<TimeInterval, Never>

// Duration changes (especially for streaming audio)
SAPlayer.shared.updates.duration: CurrentValueSubject<TimeInterval, Never>

// Streaming buffer progress
SAPlayer.shared.updates.streamingBuffer: CurrentValueSubject<SAAudioAvailabilityRange?, Never>

// Download progress
SAPlayer.shared.updates.audioDownloading: CurrentValueSubject<Double, Never>

// Streaming download progress with URL
SAPlayer.shared.updates.streamingDownloadProgress: CurrentValueSubject<(url: URL, progress: Double)?, Never>

// Next audio in queue
SAPlayer.shared.updates.audioQueue: CurrentValueSubject<URL?, Never>
```

### Subscription Pattern

Use standard Combine patterns for subscription management:

```swift
private var cancellables = Set<AnyCancellable>()

// Automatic memory management - no manual unsubscribe needed
SAPlayer.shared.updates.playingStatus
    .sink { status in
        // Handle status changes
    }
    .store(in: &cancellables)
```


### Publisher Details

- **ElapsedTime**: `TimeInterval` - Current playback position (scrubber position)
- **Duration**: `TimeInterval` - Total audio duration (updates as streaming progresses)
- **PlayingStatus**: `SAPlayingStatus` - Current state: `.playing`, `.paused`, `.buffering`, `.ended`
- **StreamingBuffer**: `SAAudioAvailabilityRange?` - Streaming progress and playability info
- **AudioDownloading**: `Double` - Background download progress (0.0 to 1.0)
- **AudioQueue**: `URL?` - Next audio URL in the autoplay queue

## Audio Effects

### Realtime Audio Manipulation

All audio effects on the player is done through [AVAudioUnit](https://developer.apple.com/documentation/avfoundation/avaudiounit) nodes. These include adding reverb, changing pitch and playback rate, and adding distortion. Full list of effects available [here](https://developer.apple.com/documentation/avfoundation/audio_track_engineering/audio_engine_building_blocks/audio_enhancements).

The effects intended to use are stored in `audioModifiers` as a list of nodes. These nodes are in the order that the engine will attach them to one another.

**Note:** By default `SAPlayer` starts off with one node, an [AVAudioUnitTimePitch](https://developer.apple.com/documentation/avfoundation/avaudiounittimepitch) node, that is set to change the rate of audio without changing the pitch of the audio (intended for changing the rate of spoken word).

#### Important
All the nodes intended to be used on the playing audio must be finalized before calling `initializeSavedAudio(...)` or `initializeRemoteAudio(...)`. Any changes to list of nodes after initialize is called for a given audio file will not be reflected in playback.

Once all nodes are added to `audioModifiers` and the player has been initialized, any manipulations done with the nodes are performed in realtime. The example app shows manipulating the playback rate in realtime:

```swift
let speed = rateSlider.value
if let node = SAPlayer.shared.audioModifiers[0] as? AVAudioUnitTimePitch {
    node.rate = speed
    SAPlayer.shared.playbackRateOfAudioChanged(rate: speed)
}
```

**Note:** if the rate of the audio is changed, `playbackRateOfAudioChanged` should also be called to update the lockscreen's media player.

