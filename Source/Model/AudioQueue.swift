//
//  AudioQueue.swift
//  Resonance
//
//  Created by Joe Williams on 3/10/21.
//

import Foundation
import Collections
import Combine

// Reactive wrapper for audio queue with Combine integration
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

  /// Returns all items as an array for reactive publishing
  var allItems: [T] {
    return Array(audioUrls)
  }

  /// Clears the entire queue
  mutating func clear() {
    audioUrls.removeAll()
  }

  /// Inserts an item at the specified index
  mutating func insert(item: T, at index: Int) {
    let clampedIndex = max(0, min(index, audioUrls.count))
    audioUrls.insert(item, at: clampedIndex)
  }

  /// Removes an item at the specified index
  mutating func remove(at index: Int) -> T? {
    guard index >= 0 && index < audioUrls.count else { return nil }
    return audioUrls.remove(at: index)
  }
}

/// Reactive Audio Queue Manager
///
/// Manages audio queue state with reactive updates through Combine publishers.
/// Integrates with ReactiveAudioCoordinator for protocol-based architecture.
@MainActor
public class ReactiveAudioQueueManager<T: Sendable>: ObservableObject {

  // MARK: - Private State

  private var queue = AudioQueue<T>()
  private var coordinator: ReactiveAudioCoordinator?

  // MARK: - Reactive Publishers

  /// Publisher that emits queue state changes
  private let queueSubject = CurrentValueSubject<[T], Never>([])

  /// Publisher that emits current queue item changes
  private let currentItemSubject = CurrentValueSubject<T?, Never>(nil)

  /// Publisher that emits queue count changes
  private let countSubject = CurrentValueSubject<Int, Never>(0)

  /// Publisher that emits whether queue is empty
  private let isEmptySubject = CurrentValueSubject<Bool, Never>(true)

  // MARK: - Public Publishers

  /// Publisher for queue state changes
  public var queuePublisher: AnyPublisher<[T], Never> {
    queueSubject.eraseToAnyPublisher()
  }

  /// Publisher for current item changes
  public var currentItemPublisher: AnyPublisher<T?, Never> {
    currentItemSubject.eraseToAnyPublisher()
  }

  /// Publisher for queue count changes
  public var countPublisher: AnyPublisher<Int, Never> {
    countSubject.eraseToAnyPublisher()
  }

  /// Publisher for empty state changes
  public var isEmptyPublisher: AnyPublisher<Bool, Never> {
    isEmptySubject.eraseToAnyPublisher()
  }

  // MARK: - Initialization

  public init(coordinator: ReactiveAudioCoordinator? = nil) {
    self.coordinator = coordinator
    updatePublishers()
  }

  // MARK: - Public Interface

  /// Current queue contents
  public var currentQueue: [T] {
    queue.allItems
  }

  /// Current front item
  public var currentItem: T? {
    queue.front
  }

  /// Current queue count
  public var count: Int {
    queue.count
  }

  /// Whether queue is empty
  public var isEmpty: Bool {
    queue.isQueueEmpty
  }

  /// Adds an item to the end of the queue
  /// - Parameter item: Item to add
  public func enqueue(_ item: T) {
    queue.append(item: item)
    updatePublishers()
  }

  /// Adds multiple items to the end of the queue
  /// - Parameter items: Items to add
  public func enqueue(contentsOf items: [T]) {
    for item in items {
      queue.append(item: item)
    }
    updatePublishers()
  }

  /// Removes and returns the front item
  /// - Returns: The dequeued item, or nil if empty
  public func dequeue() -> T? {
    let item = queue.dequeue()
    updatePublishers()
    return item
  }

  /// Inserts an item at the specified position
  /// - Parameters:
  ///   - item: Item to insert
  ///   - index: Position to insert at (clamped to valid range)
  public func insert(_ item: T, at index: Int) {
    queue.insert(item: item, at: index)
    updatePublishers()
  }

  /// Removes an item at the specified position
  /// - Parameter index: Position to remove from
  /// - Returns: The removed item, or nil if invalid index
  public func removeItem(at index: Int) -> T? {
    let item = queue.remove(at: index)
    updatePublishers()
    return item
  }

  /// Clears all items from the queue
  public func clear() {
    queue.clear()
    updatePublishers()
  }

  /// Moves an item from one position to another
  /// - Parameters:
  ///   - fromIndex: Source position
  ///   - toIndex: Destination position
  public func moveItem(from fromIndex: Int, to toIndex: Int) {
    guard let item = queue.remove(at: fromIndex) else { return }
    queue.insert(item: item, at: toIndex)
    updatePublishers()
  }

  // MARK: - Actor System Integration

  /// Configures with ReactiveAudioCoordinator for enhanced functionality
  /// - Parameter coordinator: The coordinator to integrate with
  public func configureWithCoordinator(_ coordinator: ReactiveAudioCoordinator?) {
    self.coordinator = coordinator
  }

  /// Publishes queue updates to the coordinator's reactive system
  private func publishToCoordinator() {
    // In future iterations, could integrate with AudioUpdates.audioQueue
    coordinator?.getLegacyAudioUpdates().updateAudioQueue(currentItem as? URL)
  }

  // MARK: - Private Implementation

  private func updatePublishers() {
    queueSubject.send(queue.allItems)
    currentItemSubject.send(queue.front)
    countSubject.send(queue.count)
    isEmptySubject.send(queue.isQueueEmpty)
    publishToCoordinator()
  }
}

// MARK: - Protocol Integration

extension ReactiveAudioQueueManager {

  /// Creates a reactive queue manager for protocol integration
  /// - Parameter coordinator: ReactiveAudioCoordinator for actor system access
  /// - Returns: Configured ReactiveAudioQueueManager instance
  public static func createForProtocolIntegration(
    coordinator: ReactiveAudioCoordinator?
  ) -> ReactiveAudioQueueManager<T> {
    return ReactiveAudioQueueManager<T>(coordinator: coordinator)
  }
}

// MARK: - Convenience Extensions

extension ReactiveAudioQueueManager where T == URL {

  /// Specialized queue manager for audio URLs
  public static func audioURLQueue(coordinator: ReactiveAudioCoordinator? = nil) -> ReactiveAudioQueueManager<URL> {
    return ReactiveAudioQueueManager<URL>(coordinator: coordinator)
  }

  /// Enqueues an audio URL with metadata tracking
  /// - Parameters:
  ///   - url: Audio URL to enqueue
  ///   - metadata: Optional metadata to associate
  public func enqueueAudio(_ url: URL, metadata: AudioMetadata? = nil) {
    enqueue(url)

    // Future: Could store metadata mapping for protocol implementations
    if let metadata = metadata {
      // Store metadata association for later retrieval
    }
  }
}
