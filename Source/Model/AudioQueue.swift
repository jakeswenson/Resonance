//
//  AudioQueue.swift
//  Resonance
//
//  Created by Joe Williams on 3/10/21.
//

import Foundation
import Collections

// wrapper for array of urls
struct AudioQueue<T> {
  private var audioUrls: Deque<T> = []

  var isQueueEmpty: Bool {
    return audioUrls.isEmpty
  }

  var count: Int {
    return audioUrls.count
  }

  var front: T? {
    return audioUrls.first
  }

  mutating func append(item: T) {
    audioUrls.append(item)
  }

  mutating func dequeue() -> T? {
    guard !isQueueEmpty else { return nil }
    return audioUrls.removeFirst()
  }
}
