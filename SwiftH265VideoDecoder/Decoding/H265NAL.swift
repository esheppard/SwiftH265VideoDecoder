//
// Copyright 2024 Elijah Sheppard
//

import Foundation

/// Represents an H265 (HEVC) Network Abstraction Layer Unit
struct H265NALUnit {
  var type: H265NALUnitType
  
  /// NAL data (header included)
  var data: Data
  
  /// NAL payload (header excluded)
  var payload: Data
}

enum H265NALUnitType: UInt8 {
  
  /// Trailing picture, non-reference
  case Trail_N = 0
  
  /// Trailing picture, reference
  case Trail_R = 1
  
  /// Broken Link Access with Associated RASL
  case BLA_W_LP = 16
  
  /// Broken Link Access with Associated RADL
  case BLA_W_RADL = 17
  
  /// Broken Link Access
  case BLA_N_LP = 18
  
  /// Instantaneous Decoder Refresh with Associated RADL
  case IDR_W_RADL = 19
  
  /// Instantaneous Decoder Refresh
  case IDR_N_LP = 20
  
  /// Clean Random Access
  case CRA = 21
  
  /// Video Parameter Set
  case VPS = 32
  
  /// Sequence Parameter Set
  case SPS = 33
  
  /// Picture Parameter Set
  case PPS = 34
  
  /// Access Unit Delimiter
  case accessUnitDelimiter = 35
  
  /// End of Sequence
  case endOfSequence = 36
  
  /// End of Bitstream
  case endOfBitstream = 37
  
  /// Supplemental Enhancement Information, prefix
  case SEI_prefix = 39
  
  /// Supplemental Enhancement Information, suffix
  case SEI_suffix = 40
  
  /// RTP Aggregation Packet
  case aggregationPacket = 48

  /// RTP Fragmentation Unit
  case fragmentationPacket = 49

  /// Payload Access Content Information
  case PACI = 50
}

extension H265NALUnit {
  /// H.265 NAL layer ID
  var layerID: UInt8 {
    guard data.count >= 2 else { return 0 }
    return ((data[0] & 0b00000001) << 5) | ((data[1] & 0b11111000) >> 3)
  }
  
  /// H.265 NAL temporal ID
  var temporalID: Int {
    guard data.count >= 2 else { return 0 }
    return Int((data[1] & 0b00000111)) - 1
  }
  
  /// Checks if this is the first slice in a picture (frame)
  var isFirstSliceInPicture: Bool {
    guard !payload.isEmpty, isSlice else { return false }
    return (payload[0] & 0x80) != 0
  }
}

extension H265NALUnit {
  func splitOnAnnexB() -> [H265NALUnit] {
    return data.splitOnAnnexBStartCodes()
      .compactMap { data in
        let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: ptr, count: data.count)
        defer { ptr.deallocate() }
        let data = Data(bytes: ptr, count: data.count)
        
        return decodeH265NALUnit(data: data)
      }
  }
}

extension H265NALUnit {
  var isSlice: Bool {
    return [
      .Trail_N, 
      .Trail_R,
      .BLA_W_LP, 
      .BLA_W_RADL,
      .BLA_N_LP,
      .IDR_W_RADL,
      .IDR_N_LP
    ].contains(type)
  }
}

extension Array where Element == H265NALUnit {
  var containsSlice: Bool {
    contains(where: { nalu in nalu.isSlice })
  }
}


// MARK: - Decoding

func decodeH265NALUnit(data: Data) -> H265NALUnit? {
  guard data.count >= 2 else {
    return nil
  }
  
  /* H.265 NAL Unit header
   * +---------------+---------------+
   * |0|1|2|3|4|5|6|7|0|1|2|3|4|5|6|7|
   * +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
   * |F|   Type    |  LayerID  | TID |
   * +-------------+-----------------+
   */
  let header = data[0]
  let forbiddenZeroBit = (header & 0b10000000) >> 7
  let typeValue = (header & 0b01111110) >> 1
  
  guard let type = H265NALUnitType(rawValue: typeValue) else {
    return nil
  }
  
  // Check the forbideen zero bit – it must always be 0 for H.265/HEVC
  guard forbiddenZeroBit == 0 else{
    return nil
  }
  
  let payload = data.subdata(in: 2..<data.count)
  return H265NALUnit(type: type, data: data, payload: payload)
}


// MARK: - Debug description

extension H265NALUnitType: CustomDebugStringConvertible {
  var debugDescription: String {
    switch rawValue {
    case 0 : return "HEVC Trail_N (Trailing picture, non-reference)"
    case 1 : return "HEVC Trail_R (Trailing picture, reference)"
    case 16: return "HEVC BLA_W_LP"
    case 17: return "HEVC BLA_W_RADL"
    case 18: return "HEVC BLA_N_LP"
    case 19: return "HEVC IDR_W_RADL"
    case 20: return "HEVC IDR_N_LP"
    case 21: return "HEVC Clean Random Access"
    case 32: return "HEVC Video Parameter Set"
    case 33: return "HEVC Sequence Parameter Set"
    case 34: return "HEVC Picture Parameter Set"
    case 35: return "HEVC Access Unit Delimiter"
    case 39: return "HEVC Supplemental Enhancement Information, prefix"
    case 40: return "HEVC Supplemental Enhancement Information, suffix"
    case 48: return "HEVC RTP Aggregation Packet"
    case 49: return "HEVC RTP Fragmentation Unit"
    case 50: return "HEVC Payload Content Information"
    default: return "Unknown HEVC NAL unit type \(rawValue)"
    }
  }
}
