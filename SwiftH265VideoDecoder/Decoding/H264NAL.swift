//
// Copyright 2024 Elijah Sheppard
//

import Foundation

/// Represents an H264 (AVC) Network Abstraction Layer Unit
struct H264NALUnit {
  var type: H264NALUnitType
  
  /// NAL data (header included)
  var data: Data
  
  /// NAL payload (header excluded)
  var payload: Data
}

enum H264NALUnitType: UInt8 {
  /// Coded slice of a non-IDR picture (P/B-frame)
  case sliceNonIDR = 1
  
  /// Coded slice data partition A
  case sliceA = 2
  
  /// Coded slice data partition B
  case sliceB = 3
  
  /// Coded slice data partition C
  case sliceC = 4
  
  /// Coded slice of an IDR (Instantaneous Decoder Referesh) picture (I-frame)
  case sliceIDR = 5
  
  /// Supplemental enhancement information
  case SEI = 6
  
  /// Sequence parameter set
  case SPS = 7
  
  /// Picture parameter set
  case PPS = 8
  
  /// Access unit delimiter
  case accessUnitDelimiter = 9
  
  /// End of sequence
  case endOfSequence = 10
  
  /// End of stream
  case endOfStream = 11
  
  /// Filler data
  case filler = 12
  
  /// RTP Single-Time Aggregation Packet type A (RFC 6184)
  case STAP_A = 24
  
  /// RTP Single-Time Aggregation Packet type A (RFC 6184)
  case STAP_B = 25
  
  /// RTP Multi-Time Aggregation Packet with 16-bit offset (RFC 6184)
  case MTAP_16 = 26
  
  /// RTP Multi-Time Aggregation Packet with 24-bit offset (RFC 6184)
  case MTAP_24 = 27
  
  /// RTP Fragmentation Unit A (RFC 6184)
  case FU_A = 28
  
  /// RTP Fragmentation Unit B (RFC 6184)
  case FU_B = 29
}

extension H264NALUnit {
  /// H.264 NAL ref IDC
  var refIDC: UInt8 {
    guard data.count >= 1 else { return 0 }
    return (data[0] & 0b01100000) >> 5
  }
}

extension H264NALUnit {
  func splitOnAnnexB() -> [H264NALUnit] {
    // This non-aggregation NALU may contain mutliple NALU packets, even
    // though this should not be possible according to the RTP standard.
    //
    // We need to look for Annex B start codes (3-byte and 4-byte) and split into multiple
    // NALUs.
    //
    // All of these NALUs need to be passed to CMBlockBuffer together in order to
    // correctly decode the frame.
    return data.splitOnAnnexBStartCodes()
      .compactMap { data in decodeH264NALUnit(data: data) }
  }
}

extension H264NALUnit {
  var isSlice: Bool {
    return [
      .sliceA,
      .sliceB,
      .sliceC,
      .sliceIDR,
      .sliceNonIDR
    ].contains(type)
  }
}

extension Array where Element == H264NALUnit {
  var containsSlice: Bool {
    contains(where: { nalu in nalu.isSlice })
  }
}


// MARK: - Decoding

func decodeH264NALUnit(data: Data) -> H264NALUnit? {
  guard data.count >= 1 else {
    return nil
  }
  
  /* H.264 NAL Unit header
   * +---------------+
   * |0|1|2|3|4|5|6|7|
   * +-+-+-+-+-+-+-+-+
   * |F|NRI|  Type   |
   * +---------------+
   */
  let header = data[0]
  let forbiddenZeroBit = (header & 0b10000000) >> 7
  let typeValue = header & 0b00011111
  
  guard let type = H264NALUnitType(rawValue: typeValue) else {
    return nil
  }
  
  // Check the forbideen zero bit – it must always be 0 for H.264/AVC
  guard forbiddenZeroBit == 0 else{
    return nil
  }
  
  let payload = data.subdata(in: 1..<data.count)
  return H264NALUnit(type: type, data: data, payload: payload)
}


// MARK: - Debug description

extension H264NALUnitType: CustomDebugStringConvertible {
  var debugDescription: String {
    switch rawValue {
    case 1:  return "Coded slice of a non-IDR picture (P/B-frame)"
    case 2:  return "Coded slice data partition A"
    case 3:  return "Coded slice data partition B"
    case 4:  return "Coded slice data partition C"
    case 5:  return "Coded slice of an IDR picture (I-frame)"
    case 6:  return "Supplemental enhancement information (SEI)"
    case 7:  return "Sequence parameter set (SPS)"
    case 8:  return "Picture parameter set (PPS)"
    case 9:  return "Access unit delimiter (AU)"
    case 10: return "End of sequence"
    case 11: return "End of stream"
    case 12: return "Filler data"
    case 28: return "RTP Fragmentation Unit A"
    case 29: return "RTP Fragmentation Unit B"
    default: return "Unknown H.264 NAL unit type \(rawValue)"
    }
  }
}
