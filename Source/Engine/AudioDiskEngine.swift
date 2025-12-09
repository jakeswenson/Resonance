//
//  AudioDiskEngine.swift
//  Resonance
//
//  Created by Tanha Kabir on 2019-01-29.
//  Copyright © 2019 Tanha Kabir, Jon Mercer
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import AVFoundation
import Foundation
import Combine

/// Audio engine for disk-based playback - adapted for protocol-based architecture integration
///
/// Optimized for local audio file playback with immediate access to file information.
/// Provides efficient seeking and duration calculation for local content.
///
/// PROTOCOL INTEGRATION. Works with ReactiveAudioCoordinator for coordinated
/// access to actors and provides state updates through AudioUpdates
class AudioDiskEngine: AudioEngine {
  var audioFormat: AVAudioFormat?
  var audioSampleRate: Float = 0
  var audioLengthSamples: AVAudioFramePosition = 0
  var seekFrame: AVAudioFramePosition = 0
  var currentPosition: AVAudioFramePosition = 0

  var audioFile: AVAudioFile?

  // Protocol integration
  private weak var coordinator: ReactiveAudioCoordinator?
  private var audioMetadata: AudioMetadata?

  var currentFrame: AVAudioFramePosition {
    guard let lastRenderTime = playerNode.lastRenderTime,
      let playerTime = playerNode.playerTime(forNodeTime: lastRenderTime)
    else {
      return 0
    }

    return playerTime.sampleTime
  }

  var audioLengthSeconds: Float = 0

  init(withSavedUrl url: AudioURL, delegate: AudioEngineDelegate?, updates: AudioUpdates, coordinator: ReactiveAudioCoordinator? = nil, metadata: AudioMetadata? = nil) {
    Log.info(url.key)

    do {
      audioFile = try AVAudioFile(forReading: url)
    } catch {
      Log.monitor(error.localizedDescription)
    }

    super.init(
      url: url, delegate: delegate,
      engineAudioFormat: audioFile?.processingFormat ?? AudioEngine.defaultEngineAudioFormat,
      updates: updates)

    // Store protocol integration dependencies
    self.coordinator = coordinator
    self.audioMetadata = metadata

    if let file = audioFile {
      Log.debug("Audio file exists")
      audioLengthSamples = file.length
      audioFormat = file.processingFormat
      audioSampleRate = Float(audioFormat?.sampleRate ?? 44100)
      audioLengthSeconds = Float(audioLengthSamples) / audioSampleRate
      duration = Duration(audioLengthSeconds)
      bufferedSeconds = SAAudioAvailabilityRange(
        startingNeedle: 0, durationLoadedByNetwork: duration, predictedDurationToLoad: duration,
        isPlayable: true)
    } else {
      Log.monitor("Could not load downloaded file with url: \(url)")
    }

    doRepeatedly(timeInterval: 0.2) { [weak self] in
      guard let self = self else { return }

      self.updateIsPlaying()
      self.updateNeedle()
    }

    scheduleAudioFile()
  }

  private func scheduleAudioFile() {
    guard let audioFile = audioFile else { return }

    playerNode.scheduleFile(audioFile, at: nil, completionHandler: nil)
  }

  private func updateNeedle() {
    guard engine.isRunning else { return }

    currentPosition = currentFrame + seekFrame
    currentPosition = max(currentPosition, 0)
    currentPosition = min(currentPosition, audioLengthSamples)

    if currentPosition >= audioLengthSamples {
      playerNode.stop()
      if state == .resumed {
        state = .suspended
      }
      playingStatus = .ended
    }

    guard audioSampleRate != 0 else {
      Log.error("Missing audio sample rate in update needle timer function!")
      return
    }

    needle = Double(Float(currentPosition) / audioSampleRate)
  }

  override func seek(toNeedle needle: Needle) {
    guard let audioFile = audioFile else {
      Log.error("did not have audio file when trying to seek")
      return
    }

    let playing = playerNode.isPlaying
    let seekToNeedle = needle > Needle(duration) ? Needle(duration) : needle

    self.needle = seekToNeedle  // to tick while paused

    seekFrame = AVAudioFramePosition(Float(seekToNeedle) * audioSampleRate)
    seekFrame = max(seekFrame, 0)
    seekFrame = min(seekFrame, audioLengthSamples)
    currentPosition = seekFrame

    playerNode.stop()

    if currentPosition < audioLengthSamples {
      playerNode.scheduleSegment(
        audioFile, startingFrame: seekFrame,
        frameCount: AVAudioFrameCount(audioLengthSamples - seekFrame), at: nil,
        completionHandler: nil)

      if playing {
        playerNode.play()
      }
    }
  }

  override func invalidate() {
    super.invalidate()
    //Nothing to invalidate for disk
  }
}

// MARK: - Protocol Integration

extension AudioDiskEngine {

  /// Creates a disk engine configured for protocol integration
  /// - Parameters:
  ///   - url: Local URL to play
  ///   - coordinator: ReactiveAudioCoordinator for actor access
  ///   - metadata: Audio metadata for protocol compliance
  ///   - delegate: Engine delegate for callbacks
  /// - Returns: Configured AudioDiskEngine instance
  static func createForProtocolIntegration(
    withSavedUrl url: AudioURL,
    coordinator: ReactiveAudioCoordinator?,
    metadata: AudioMetadata?,
    delegate: AudioEngineDelegate? = nil
  ) -> AudioDiskEngine {
    return AudioDiskEngine(
      withSavedUrl: url,
      delegate: delegate,
      updates: coordinator?.getLegacyAudioUpdates() ?? AudioUpdates(),
      coordinator: coordinator,
      metadata: metadata
    )
  }

  /// Gets the current audio metadata
  func getCurrentMetadata() -> AudioMetadata? {
    return audioMetadata
  }

  /// Updates the audio metadata
  func updateMetadata(_ metadata: AudioMetadata?) {
    self.audioMetadata = metadata
  }

  /// Gets the coordinator reference for actor access
  func getCoordinator() -> ReactiveAudioCoordinator? {
    return coordinator
  }

  /// Gets file information for protocol compliance
  func getFileInfo() -> (duration: TimeInterval, sampleRate: Float, length: AVAudioFramePosition)? {
    guard let audioFile = audioFile else { return nil }
    return (
      duration: TimeInterval(audioLengthSeconds),
      sampleRate: audioSampleRate,
      length: audioLengthSamples
    )
  }
}
