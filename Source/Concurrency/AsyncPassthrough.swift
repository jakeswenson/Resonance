import Foundation

/// A thread-safe event broadcaster that emits values to async consumers without storing state.
/// Replaces `PassthroughSubject<T, Never>` from Combine with AsyncSequence semantics.
///
/// Key differences from PassthroughSubject:
/// - Uses `for await` iteration instead of `.sink { }`
/// - No stored value - events are fire-and-forget
/// - Multi-consumer support via continuation management
/// - Automatic cleanup when consumers cancel
///
/// Usage:
/// ```swift
/// let events = AsyncPassthrough<String>()
///
/// // Async iteration
/// Task {
///     for await event in events {
///         print("Received: \(event)")
///     }
/// }
///
/// // Emit events
/// events.send("Hello")
/// events.send("World")
/// ```
public final class AsyncPassthrough<Element: Sendable>: AsyncSequence, @unchecked Sendable {

  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

  /// Creates a new AsyncPassthrough broadcaster.
  public init() {}

  /// Sends a value to all current subscribers.
  /// - Parameter value: The value to broadcast
  public func send(_ value: Element) {
    lock.withLock {
      for continuation in continuations.values {
        continuation.yield(value)
      }
    }
  }

  /// Finishes all streams, signaling no more values will be sent.
  /// Call this when the broadcaster is being deallocated or should stop.
  public func finish() {
    lock.withLock {
      for continuation in continuations.values {
        continuation.finish()
      }
      continuations.removeAll()
    }
  }

  // MARK: - AsyncSequence Conformance

  public struct AsyncIterator: AsyncIteratorProtocol {
    private var iterator: AsyncStream<Element>.Iterator

    init(stream: AsyncStream<Element>) {
      self.iterator = stream.makeAsyncIterator()
    }

    public mutating func next() async -> Element? {
      await iterator.next()
    }
  }

  public func makeAsyncIterator() -> AsyncIterator {
    let id = UUID()

    let stream = AsyncStream<Element> { [weak self] continuation in
      guard let self else {
        continuation.finish()
        return
      }

      // Register the continuation
      self.lock.withLock {
        self.continuations[id] = continuation
      }

      // Clean up when the consumer cancels
      continuation.onTermination = { @Sendable [weak self] _ in
        guard let self else { return }
        self.lock.withLock {
          _ = self.continuations.removeValue(forKey: id)
        }
      }
    }

    return AsyncIterator(stream: stream)
  }
}

