//
// Copyright 2024 Elijah Sheppard
//

import Foundation
import AVFoundation
import CoreMedia

class H265VideoDecoder: VideoDecoder {
  weak var delegate: VideoDecoderDelegate?
  
  private let decompressionSession = DecompressionSession()
  private let queue = DispatchQueue(label: "h265.queue")
  private let ts = RTPTimestamp()
  
  // Fragmented Unit NALU data buffer
  private var fuDataBuffer: Data?
  
  // Decoding state
  private var sps: H265NALUnit?
  private var pps: H265NALUnit?
  private var vps: H265NALUnit?
  private var sequence: [H265NALUnit] = []
  private var sequencePTS: CMTime = .zero
  private var description: CMFormatDescription?
  
  init() {
    decompressionSession.delegate = self
  }
  
  func receive(_ packet: RTPPacket) {
    queue.sync {
      guard let nalu = decodeH265NALUnit(data: packet.payload) else {
        return
      }
      
      let pts = CMTime(value: ts.toInt64(packet.timestamp), timescale: 90_000)
      
      switch nalu.type {
      case .VPS,
           .SPS,
           .PPS,
           .SEI_prefix,
           .SEI_suffix,
           .BLA_W_LP,
           .BLA_W_RADL,
           .BLA_N_LP,
           .IDR_W_RADL,
           .IDR_N_LP,
           .CRA,
           .Trail_N,
           .Trail_R,
           .endOfSequence,
           .endOfBitstream:
        process(nalu, pts: pts)
        
      case .fragmentationPacket:
        if let nalu = decodeFU(nalu) {
          process(nalu, pts: pts)
        }
        
      case .aggregationPacket:
        for nalu in decodeAggregationPacket(nalu) {
          process(nalu, pts: pts)
        }
        
      default:
        // Not supported
        print("Unsupported H.265 NAL Unit received: \(nalu.type)")
        return
      }
    }
  }
  
  /// Process a NAL unit a supplied presentation timestamp
  private func process(_ nalu: H265NALUnit, pts: CMTime) {
    
    // If the current sequence contains slices we need to output them
    // before we accept NALUs that may belong to the next sequence.
    func flushSequence() {
      if sequence.containsSlice {
        outputSequence()
      }
    }
    
    switch nalu.type {
    case .accessUnitDelimiter:
      /* Delimiters are always the start of a new Access Unit/Sequence */
      outputSequence()
      sequence.append(nalu)
      sequencePTS = pts
      
    case .endOfSequence,
         .endOfBitstream:
      outputSequence()
      
    case .SEI_prefix,
         .SEI_suffix,
         .PACI:
      /* not used */
      break
      
    case .VPS:
      flushSequence()
      vps = nalu
      reconfigure()
      sequence.append(nalu)
      sequencePTS = pts
      
    case .SPS:
      flushSequence()
      sps = nalu
      reconfigure()
      sequence.append(nalu)
      sequencePTS = pts
     
    case .PPS:
      flushSequence()
      pps = nalu
      reconfigure()
      sequence.append(nalu)
      sequencePTS = pts
      
    case .BLA_W_LP,
         .BLA_W_RADL,
         .BLA_N_LP,
         .IDR_W_RADL,
         .IDR_N_LP,
         .CRA,
         .Trail_N,
         .Trail_R:
      // Note: several slices can make up one picture (frame)
      if nalu.isFirstSliceInPicture {
        flushSequence()
      }
      
      // Note: this NALU may actually be composed of multiple NALU's that make up the
      // entire picture – so we need to split them by Annex B start code.
      sequence += nalu.splitOnAnnexB()
      sequencePTS = pts
      
    default:
      return
    }
  }
  
  private func reconfigure() {
    guard let sps = self.sps,
          let pps = self.pps,
          let vps = self.vps else {
      return
    }
    description = createDescription(sps: sps.data.withoutEPB,
                                    pps: pps.data.withoutEPB,
                                    vps: vps.data.withoutEPB)
  }
  
  /// Output the current NALU sequence and reset the current sequence
  private func outputSequence() {
    defer {
      sequence.removeAll()
    }
    
    guard let description = description else {
      return
    }
    
    // Reserve enough data for each NALU + 4 bytes AVCC length header for each
    let requiredDataSize = sequence.reduce(0) { count, nalu in count + nalu.data.count }
      + sequence.count * 4
    
    var bufferData = Data(capacity: requiredDataSize)
    for nalu in sequence {
      // BlockBuffer requires each NALU to have a 4 byte AVCC length header
      bufferData.append(nalu.data.withAVCCLengthHeader)
    }
    
    guard let blockBuffer = createBlockBuffer(with: bufferData) else {
      return
    }
    
    if let sb = createSampleBuffer(with: blockBuffer,
                                   description: description,
                                   presentationTime: sequencePTS) {
      decompressionSession.decompress(sb)
    }
  }
}

extension H265VideoDecoder: DecompressionSessionDelegate {
  func didDecompress(_ sampleBuffer: CMSampleBuffer) {
    delegate?.didDecode(sampleBuffer)
  }
}

extension H265VideoDecoder {
  /// Decode HEVC Fragmentation Unit data by buffering fragments until a complete NALU arives
  private func decodeFU(_ nalu: H265NALUnit) -> H265NALUnit? {
    guard nalu.payload.count >= 1 else {
      print("HEVC FU packet is too short")
      return nil
    }
    
    let fuHeader = nalu.payload[0]
    let fuType = (fuHeader & 0b00111111)
    let start  = (fuHeader & 0b10000000) >> 7
    let end    = (fuHeader & 0b01000000) >> 6
    
    if start == 1 {
      // Start the NALU data buffer with the reconstructed NALU header
      let byte0 = (nalu.data[0] & 0b10000001) | (fuType << 1)
      let byte1 =  nalu.data[1]
      fuDataBuffer = Data([byte0, byte1])
    }
    
    fuDataBuffer?.append(nalu.payload.subdata(in: 1..<nalu.payload.count))
    
    if end == 1, let data = fuDataBuffer {
      let nalu = decodeH265NALUnit(data: data)
      fuDataBuffer = nil
      return nalu
    }
    
    return nil
  }
}

/// Decode multiple NAL units from a single Aggregation Packet payload
private func decodeAggregationPacket(_ nalu: H265NALUnit) -> [H265NALUnit] {
  let data = nalu.payload
  var offset = 0
  var nalUnits: [H265NALUnit] = []

  while offset < data.count {
    let sizeBytes = data.subdata(in: offset..<offset+2)
    let size = UInt16(bigEndian: sizeBytes.withUnsafeBytes { $0.load(as: UInt16.self) })
    offset += 2
    
    guard offset + Int(size) <= data.count else {
      // Invalid AP packet: size exceeds payload bounds
      return nalUnits
    }
    
    let nalUnitData = data.subdata(in: offset..<offset+Int(size))
    offset += Int(size)
    
    if let nalUnit = decodeH265NALUnit(data: nalUnitData) {
      nalUnits.append(nalUnit)
    }
  }

  return nalUnits
}

private func createDescription(sps: Data, pps: Data, vps: Data) -> CMFormatDescription? {
  let spsPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: sps.count)
  sps.copyBytes(to: spsPointer, count: sps.count)
  
  let ppsPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: pps.count)
  pps.copyBytes(to: ppsPointer, count: pps.count)
  
  let vpsPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: vps.count)
  vps.copyBytes(to: vpsPointer, count: vps.count)
  
  defer {
    spsPointer.deallocate()
    ppsPointer.deallocate()
    vpsPointer.deallocate()
  }
  
  var description: CMFormatDescription?
  let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
    allocator: kCFAllocatorDefault,
    parameterSetCount: 3,
    parameterSetPointers: [
      UnsafePointer(vpsPointer),
      UnsafePointer(spsPointer),
      UnsafePointer(ppsPointer)
    ],
    parameterSetSizes: [
      vps.count,
      sps.count,
      pps.count
    ],
    nalUnitHeaderLength: 4,
    extensions: nil,
    formatDescriptionOut: &description
  )
  
  guard status == noErr, let description = description else {
    print("H265VideoDecoder: Failed to create format description \(status)")
    return nil
  }
  
  return description
}
