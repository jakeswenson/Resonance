//
//  URL.swift
//  Pods-Resonance_Example
//
//  Created by Tanha Kabir on 2019-01-29.
//

import Foundation
import CryptoKit

extension URL {
  var key: String {
    return "audio_\(self.absoluteString.hashed)"
  }
}

extension String {
  fileprivate var hashed: String {
    var sha = SHA256()
    sha.update(data: self.data(using: Encoding.utf8)!)
    let digest:SHA256.Digest = sha.finalize()
    let hash = String(describing: digest)
    Log.debug("Url Hash \(hash)")
    return hash
  }
}
