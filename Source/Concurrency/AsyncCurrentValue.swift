import Foundation

/// A thread-safe broadcaster that holds a current value and emits it to async consumers.
/// Replaces `CurrentValueSubject<T, Never>` from Combine with AsyncSequence semantics.
///
/// Key differences from CurrentValueSubject:
/// - Uses `for await` iteration instead of `.sink { }`
/// - Synchronous `.value` access for current state
/// - Multi-consumer support via continuation management
/// - Automatic cleanup when consumers cancel
///
/// Usage:
/// ```swift
/// let state = AsyncCurrentValue<Int>(0)
///
/// // Synchronous access
/// print(state.value) // 0
///
/// // Async iteration
/// Task {
///     for await value in state {
///         print(value)
///     }
/// }
///
/// // Emit new values
/// state.send(1)
/// state.send(2)
/// ```
public final class AsyncCurrentValue<Element: Sendable>: AsyncSequence, @unchecked Sendable {

  private let lock = NSLock()
  private var _value: Element
  private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

  /// The current value. Thread-safe for synchronous access.
  public var value: Element {
    lock.withLock { _value }
  }

  /// Creates a new AsyncCurrentValue with an initial value.
  /// - Parameter initialValue: The initial value to hold
  public init(_ initialValue: Element) {
    self._value = initialValue
  }

  /// Sends a new value to all current subscribers.
  /// - Parameter newValue: The value to broadcast
  public func send(_ newValue: Element) {
    lock.withLock {
      _value = newValue
      for continuation in continuations.values {
        continuation.yield(newValue)
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

      // Emit current value immediately upon subscription
      let currentValue = self.lock.withLock {
        self.continuations[id] = continuation
        return self._value
      }
      continuation.yield(currentValue)

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

// MARK: - Equatable Value Extension

extension AsyncCurrentValue where Element: Equatable {

  /// Sends a new value only if it differs from the current value.
  /// - Parameter newValue: The value to potentially broadcast
  public func sendIfChanged(_ newValue: Element) {
    lock.withLock {
      guard _value != newValue else { return }
      _value = newValue
      for continuation in continuations.values {
        continuation.yield(newValue)
      }
    }
  }
}
