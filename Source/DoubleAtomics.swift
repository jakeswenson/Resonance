import Atomics

// Temporarily commented out due to swift-atomics version conflicts
// This will be restored once atomic storage is properly configured

/*
extension Double: AtomicValue {
  public typealias AtomicRepresentation = DoubleStorage
}

public struct DoubleStorage: AtomicStorage {
  public typealias Value = Double
  private let _storage: ManagedAtomic<UInt64>

  public init(_ value: __owned Double) {
    _storage = ManagedAtomic<UInt64>(value.bitPattern)
  }

  public __consuming func dispose() -> Double {
    Double(bitPattern: _storage.load(ordering: .sequentiallyConsistent))
  }
}
*/

// Rest of implementation commented out temporarily
/*
  public static func atomicLoad(at pointer: UnsafeMutablePointer<DoubleStorage>, ordering: AtomicLoadOrdering) -> Double {

    let result = pointer.withMemoryRebound(to: Inner.self, capacity: 1) { (p: UnsafeMutablePointer<Inner>) -> Inner.Value in
      switch ordering {
        case .acquiring: return Inner.atomicLoad(at: p, ordering: .acquiring)
        case .relaxed: return Inner.atomicLoad(at: p, ordering: .relaxed)
        case .sequentiallyConsistent: fallthrough
        default: return Inner.atomicLoad(at: p, ordering: .sequentiallyConsistent)
      }
    }

    return Double(bitPattern: result)
  }

  public static func atomicStore(_ desired: __owned Double, at pointer: UnsafeMutablePointer<DoubleStorage>, ordering: AtomicStoreOrdering) {

    pointer.withMemoryRebound(to: Inner.self, capacity: 1) { (p: UnsafeMutablePointer<Inner>) -> Void in
      switch ordering {
        case .releasing: Inner.atomicStore(desired.bitPattern, at: p, ordering: .releasing)
        case .relaxed: Inner.atomicStore(desired.bitPattern, at: p, ordering: .relaxed)
        case .sequentiallyConsistent: fallthrough
        default: Inner.atomicStore(desired.bitPattern, at: p, ordering: .sequentiallyConsistent)
      }
    }
  }

  public static func atomicExchange(_ desired: __owned Double, at pointer: UnsafeMutablePointer<DoubleStorage>, ordering: AtomicUpdateOrdering) -> Double {
    let result = pointer.withMemoryRebound(to: Inner.self, capacity: 1) { (p: UnsafeMutablePointer<Inner>) -> Inner.Value in
      switch ordering {
        case .acquiring: return Inner.atomicExchange(desired.bitPattern, at: p, ordering: .acquiring)
        case .relaxed: return Inner.atomicExchange(desired.bitPattern, at: p, ordering: .relaxed)
        case .sequentiallyConsistent: fallthrough
        default: return Inner.atomicExchange(desired.bitPattern, at: p, ordering: .sequentiallyConsistent)
      }
    }

    return Double(bitPattern: result)
  }

  public static func atomicCompareExchange(expected: Double, desired: __owned Double, at pointer: UnsafeMutablePointer<DoubleStorage>, ordering: AtomicUpdateOrdering) -> (exchanged: Bool, original: Double) {
    let result: (exchanged: Bool, original: Inner.Value)  = pointer.withMemoryRebound(to: Inner.self, capacity: 1) { p in
      switch ordering {
        case .acquiring: return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, ordering: .acquiring)
        case .relaxed: return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, ordering: .relaxed)
        case .releasing: return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, ordering: .releasing)
        case .acquiringAndReleasing: return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, ordering: .acquiringAndReleasing)
        case .sequentiallyConsistent: fallthrough
        default: return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, ordering: .sequentiallyConsistent)
      }
    }

    return (exchanged: result.exchanged, original: Double(bitPattern: result.original))
  }

  public static func atomicCompareExchange(expected: Double, desired: __owned Double, at pointer: UnsafeMutablePointer<DoubleStorage>, successOrdering: AtomicUpdateOrdering, failureOrdering: AtomicLoadOrdering) -> (exchanged: Bool, original: Double) {
    let result: (exchanged: Bool, original: Inner.Value)  = pointer.withMemoryRebound(to: Inner.self, capacity: 1) { p in
      switch (successOrdering, failureOrdering) {
        case (.acquiring, .acquiring): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiring, failureOrdering: .acquiring)
        case (.acquiring, .sequentiallyConsistent): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiring, failureOrdering: .sequentiallyConsistent)
        case (.acquiring, .relaxed): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiring, failureOrdering: .relaxed)

        case (.relaxed, .relaxed): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .relaxed, failureOrdering: .relaxed)
        case (.relaxed, .acquiring): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .relaxed, failureOrdering: .acquiring)
        case (.relaxed, .sequentiallyConsistent): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .relaxed, failureOrdering: .sequentiallyConsistent)

        case (.releasing, .relaxed): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .releasing, failureOrdering: .relaxed)
        case (.releasing, .acquiring): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .releasing, failureOrdering: .acquiring)
        case (.releasing, .sequentiallyConsistent): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .releasing, failureOrdering: .sequentiallyConsistent)

        case (.acquiringAndReleasing, .relaxed): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiringAndReleasing, failureOrdering: .relaxed)
        case (.acquiringAndReleasing, .acquiring): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiringAndReleasing, failureOrdering: .acquiring)
        case (.acquiringAndReleasing, .sequentiallyConsistent): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiringAndReleasing, failureOrdering: .sequentiallyConsistent)

        case (.sequentiallyConsistent, .relaxed): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .sequentiallyConsistent, failureOrdering: .relaxed)
        case (.sequentiallyConsistent, .acquiring): return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .sequentiallyConsistent, failureOrdering: .acquiring)
        case (.sequentiallyConsistent, .sequentiallyConsistent): fallthrough
        default: return Inner.atomicCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .sequentiallyConsistent, failureOrdering: .sequentiallyConsistent)
      }
    }

    return (exchanged: result.exchanged, original: Double(bitPattern: result.original))
  }

  public static func atomicWeakCompareExchange(expected: Double, desired: __owned Double, at pointer: UnsafeMutablePointer<DoubleStorage>, successOrdering: AtomicUpdateOrdering, failureOrdering: AtomicLoadOrdering) -> (exchanged: Bool, original: Double) {
    let result: (exchanged: Bool, original: Inner.Value)  = pointer.withMemoryRebound(to: Inner.self, capacity: 1) { p in
      switch (successOrdering, failureOrdering) {
        case (.acquiring, .acquiring): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiring, failureOrdering: .acquiring)
        case (.acquiring, .sequentiallyConsistent): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiring, failureOrdering: .sequentiallyConsistent)
        case (.acquiring, .relaxed): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiring, failureOrdering: .relaxed)

        case (.relaxed, .relaxed): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .relaxed, failureOrdering: .relaxed)
        case (.relaxed, .acquiring): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .relaxed, failureOrdering: .acquiring)
        case (.relaxed, .sequentiallyConsistent): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .relaxed, failureOrdering: .sequentiallyConsistent)

        case (.releasing, .relaxed): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .releasing, failureOrdering: .relaxed)
        case (.releasing, .acquiring): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .releasing, failureOrdering: .acquiring)
        case (.releasing, .sequentiallyConsistent): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .releasing, failureOrdering: .sequentiallyConsistent)

        case (.acquiringAndReleasing, .relaxed): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiringAndReleasing, failureOrdering: .relaxed)
        case (.acquiringAndReleasing, .acquiring): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiringAndReleasing, failureOrdering: .acquiring)
        case (.acquiringAndReleasing, .sequentiallyConsistent): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .acquiringAndReleasing, failureOrdering: .sequentiallyConsistent)

        case (.sequentiallyConsistent, .relaxed): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .sequentiallyConsistent, failureOrdering: .relaxed)
        case (.sequentiallyConsistent, .acquiring): return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .sequentiallyConsistent, failureOrdering: .acquiring)
        case (.sequentiallyConsistent, .sequentiallyConsistent): fallthrough
        default: return Inner.atomicWeakCompareExchange(expected: expected.bitPattern, desired: desired.bitPattern, at: p, successOrdering: .sequentiallyConsistent, failureOrdering: .sequentiallyConsistent)
      }
    }

    return (exchanged: result.exchanged, original: Double(bitPattern: result.original))
  }


}
*/
