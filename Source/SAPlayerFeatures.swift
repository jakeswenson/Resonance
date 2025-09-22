//
//  SAPlayerFeature.swift
//  Resonance
//
//  Created by Tanha Kabir on 3/10/21.
//

import AVFoundation
import Foundation
import Combine

protocol PlayerFeature: AnyObject {
  init()
}

extension SAPlayer {

  /**
   Special features for audio manipulation. These are examples of manipulations you can do with the player outside of this library. This is just an aggregation of community contibuted ones.

   - Note: These features assume default state of the player and `audioModifiers` meaning some expect the first audio modifier to be the default `AVAudioUnitTimePitch` that comes with the SAPlayer.
   */
  public class Features {
    private var featureState: [ObjectIdentifier: PlayerFeature] = [:]

    subscript<K>(key: K.Type) -> K where K: PlayerFeature {
      get {
        let key = ObjectIdentifier(key)

        guard let feature = featureState[key] else {
          let state = K.init()
          featureState[key] = state
          return state
        }

        return feature as! K
      }
      set { featureState[ObjectIdentifier(key)] = newValue }
    }
  }
}


/**
 Feature to skip silences in spoken word audio. The player will speed up the rate of audio playback when silence is detected.

 - Important: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
 */
public class SkipSilences: PlayerFeature {

  var enabled: Bool = false
  var originalRate: Float = 1.0

  required init() {

  }
}

extension SAPlayer {

  /**
   Enable feature to skip silences in spoken word audio. The player will speed up the rate of audio playback when silence is detected. This can be called at any point of audio playback.

   - Precondition: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
   - Important: If you want to change the rate of the overall player while having skip silences on, please use `SAPlayer.Features.SkipSilences.setRateSafely()` to properly set the rate of the player. Any rate changes to the player will be ignored while using Skip Silences otherwise.
   */
  @discardableResult
  public func skipSilences() -> Bool {
    let feature = self.features[SkipSilences.self]
    guard let engine = self.engine else { return false }

    feature.enabled = true
    feature.originalRate = self.rate ?? feature.originalRate

    Log.info("enabling skip silences feature")

    let format = engine.mainMixerNode.outputFormat(forBus: 0)

    // look at documentation here to get an understanding of what is happening here:
    //   https://www.raywenderlich.com/5154-avaudioengine-tutorial-for-ios-getting-started#toc-anchor-005
    engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, when in
      guard let channelData = buffer.floatChannelData else { return }

      let channelDataValue = channelData.pointee
      let channelDataValueArray = stride(
        from: 0,
        to: Int(buffer.frameLength),
        by: buffer.stride
      ).map { channelDataValue[$0] }

      let rms = sqrt(
        channelDataValueArray.map { $0 * $0 }
          .reduce(0, +) / Float(buffer.frameLength))

      let avgPower = 20 * log10(rms)

      Log.debug("power db: \(avgPower)")

      let meterLevel = Self.scaledPower(power: avgPower)
      Log.debug("meterLevel: \(meterLevel)")
      if meterLevel < 0.6 {  // below 0.6 decibels is below audible audio
        self.rate = feature.originalRate + 0.9
        Log.info("speed up rate to \(String(describing: SAPlayer.shared.rate))")
      } else {
        self.rate = feature.originalRate
        Log.info("slow down rate to \(String(describing: SAPlayer.shared.rate))")
      }
    }

    return true
  }

  /**
   Disable feature to skip silences in spoken word audio. The player will speed up the rate of audio playback when silence is detected. This can be called at any point of audio playback.

   - Precondition: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
   */
  public func disableSkipSilences() -> Bool {
    let feature = self.features[SkipSilences.self]
    guard let engine = self.engine else { return false }
    Log.info("disabling skip silences feature")
    engine.mainMixerNode.removeTap(onBus: 0)
    self.rate = feature.originalRate
    feature.enabled = false
    return true
  }

  /**
   Use this function to set the overall rate of the player for when skip silences is on. This ensures that the overall rate will be what is set through this function even as skip silences is on; if this function is not used then any changes asked of from the overall player while skip silences is on won't be recorded!

   - Important: The first audio modifier must be the default `AVAudioUnitTimePitch` that comes with the SAPlayer for this feature to work.
   */
  public func setRateSafely(_ rate: Float) {
    let feature = self.features[SkipSilences.self]
    feature.originalRate = rate
    self.rate = rate
  }

  private static func scaledPower(power: Float) -> Float {
    guard power.isFinite else { return 0.0 }
    let minDb: Float = -80.0
    if power < minDb {
      return 0.0
    } else if power >= 1.0 {
      return 1.0
    } else {
      return (abs(minDb) - abs(power)) / abs(minDb)
    }
  }
}

/**
 Feature to play the current playing audio on repeat until feature is disabled.
 */
public class Loop: PlayerFeature {
  var enabled: Bool = false
  var playingStatusId: AnyCancellable? = nil
  required init() {
  }
}


extension SAPlayer {
  /**
   Enable feature to play the current playing audio on loop. This will continue until the feature is disabled. And this feature works for both remote and saved audio.
   */
  public func loop() {
    let feature = self.features[Loop.self]
    feature.enabled = true

    guard feature.playingStatusId == nil else { return }

    feature.playingStatusId = updates.playingStatus.sink { status in
      if status == .ended && feature.enabled {
        self.seekTo(seconds: 0.0)
        self.play()
      }
    }
  }

  /**
   Disable feature playing audio on loop.
   */
  public func stopLooping() {
    let feature = self.features[Loop.self]
    feature.enabled = false
  }
}

/**
 Feature to pause the player after a delay. This will happen regardless of if another audio clip has started.
 */
public class SleepTimer: PlayerFeature {
  var timer: Timer? = nil
  required init() { }
}

extension SAPlayer {
  /**
   Enable feature to pause the player after a delay. This will happen regardless of if another audio clip has started.

   - Parameter afterDelay: The number of seconds to wait before pausing the audio
   */
  public func sleepTimer(afterDelay delay: Double) {
    let feature = self.features[SleepTimer.self]
    if let existingTimer = feature.timer {
      existingTimer.invalidate()
    }

    feature.timer = Timer.scheduledTimer(
      withTimeInterval: delay, repeats: false,
      block: { _ in
        self.pause()
      })
  }

  /**
   Disable feature to pause the player after a delay.
   */
  public func disableSleepTimer() {
    let feature = self.features[SleepTimer.self]
    feature.timer?.invalidate()
  }
}
