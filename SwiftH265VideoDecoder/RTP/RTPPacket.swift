
import Foundation

public struct RTPPacket {
  
  /// RTP Version
  public var version: UInt8
  
  /// Payload containing video data
  public var payload: Data
  
  /// Payload type
  public var payloadType: UInt8
  
  /// Sequece number
  public var sequence: UInt16
  
  /// Synchronization source
  public var ssrc: UInt32
  
  /// Contributing source
  public var csrc: [UInt32]
  
  /// Packet timestamp
  public var timestamp: UInt32
  
  /// Marker bit
  public var marker: Bool
  
  /// Extensions
  public var extensions: Data?
}
