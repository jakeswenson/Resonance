//
//  DirectorThreadSafeClosures.swift
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

import Foundation

/// P for payload
actor DirectorThreadSafeClosures<P> {
  typealias TypeClosure = (P) throws -> Void
  private var closures: [UInt: TypeClosure] = [:]
  private var cache: P? = nil
  private var counter: UInt = 0

  var count: Int {
    return closures.count
  }

  func resetCache() {
    cache = nil
  }

  func broadcast(payload: P) {
    self.cache = payload
    var iterator = self.closures.makeIterator()
    while let element = iterator.next() {
      do {
        try element.value(payload)
      } catch {
        helperRemove(withKey: element.key)
      }
    }
  }

  //UInt is actually 64-bits on modern devices
  func attach(closure: @escaping TypeClosure) -> UInt {
    counter+=1
    let id: UInt = counter

    //The director may not yet have the status yet. We should only call the closure if we have it
    //Let the caller know the immediate value. If it's dead already then stop
    if let val = cache {
      do {
        try closure(val)
      } catch {
        return id
      }
    }

    //Replace what's in the map with the new closure
    helperInsert(withKey: id, closure: closure)

    return id
  }

  func detach(id: UInt) {
    helperRemove(withKey: id)
  }

  func clear() {
    self.closures.removeAll()
    self.cache = nil
  }

  private func helperRemove(withKey key: UInt) {
    self.closures.removeValue(forKey: key)
  }

  private func helperInsert(withKey key: UInt, closure: @escaping TypeClosure) {
    self.closures[key] = closure
  }
}
