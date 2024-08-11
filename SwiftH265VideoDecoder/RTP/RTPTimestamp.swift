
import Foundation

/// RTP timestamp values are initialised to a random UInt32. We need to properly
/// handle when this value overflows and wraps around.
class RTPTimestamp {
  private var lastTimestamp: UInt32?
  private var wrapCount: Int64 = 0

  /// Converts a UInt32 timestamp to Int64 handling wrap arounds
  func toInt64(_ timestamp: UInt32) -> Int64 {
    defer {
      lastTimestamp = timestamp
    }

    guard let lastTimestamp = lastTimestamp else {
      return Int64(timestamp)
    }

    if timestamp < lastTimestamp && timestamp < UInt32.max/2 {
      wrapCount += 1
    }

    return Int64(timestamp) + wrapCount * Int64(UInt32.max)
  }
}
