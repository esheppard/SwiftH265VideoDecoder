//
// Copyright 2024 Elijah Sheppard
//

import Foundation
import AVFoundation
import CoreMedia
import CoreVideo

class H264VideoDecoder: VideoDecoder {
  weak var delegate: VideoDecoderDelegate?
  
  private let decompressionSession = DecompressionSession()
  private let queue = DispatchQueue(label: "h264.queue")
  private let ts = RTPTimestamp()
  
  /// Fragmented Unit NALU data buffer
  private var fuDataBuffer: Data?
  
  /// Decoding state
  private var sps: H264NALUnit?
  private var pps: H264NALUnit?
  private var sequence: [H264NALUnit] = []
  private var sequencePTS: CMTime = .zero
  private var description: CMFormatDescription?
  
  init() {
    decompressionSession.delegate = self
  }
  
  func receive(_ packet: RTPPacket) {
    queue.sync {
      guard let nalu = decodeH264NALUnit(data: packet.payload) else {
        return
      }
      
      let pts = CMTime(value: ts.toInt64(packet.timestamp), timescale: 90_000)
      
      switch nalu.type {
      case .SPS,
           .PPS,
           .SEI,
           .sliceIDR,
           .sliceNonIDR,
           .accessUnitDelimiter,
           .filler,
           .endOfSequence,
           .endOfStream:
        process(nalu, pts: pts)
        
      case .FU_A:
        if let nalu = decodeFU_A(nalu) {
          process(nalu, pts: pts)
        }
        
      case .STAP_A:
        for nalu in decodeSTAP_A(payload: nalu.payload) {
          process(nalu, pts: pts)
        }
        
      default:
        // Not supported
        print("Unsupported H.264 NAL Unit received: \(nalu.type)")
        return
      }
    }
  }
  
  /// Process a NAL unit a supplied presentation timestamp
  private func process(_ nalu: H264NALUnit, pts: CMTime) {
    switch nalu.type {
    case .accessUnitDelimiter:
      outputSequence()
      sequence.append(nalu)
      sequencePTS = pts
      
    case .endOfSequence,
         .endOfStream,
         .filler:
      outputSequence()
      
    case .SEI:
      sequence.append(nalu)
      sequencePTS = pts
      
    case .SPS:
      sps = nalu
      reconfigure()
      sequence.append(nalu)
      sequencePTS = pts
      
    case .PPS:
      pps = nalu
      reconfigure()
      sequence.append(nalu)
      sequencePTS = pts
      
    case .sliceIDR,
         .sliceNonIDR:
      // This payload of the NALU may actually be composed of multiple NALU's that make up the entire picture.
      sequence += nalu.splitOnAnnexB()
      sequencePTS = pts
      
      // TODO: Find a better way to determine if all slices for a frame have been received. In this
      // case we are assuming that full frames are received in a single (or aggregate) NALU.
      outputSequence()
      
    default:
      return
    }
  }
  
  private func reconfigure() {
    guard let sps = self.sps, let pps = self.pps else {
      return
    }
    description = createDescription(sps: sps.data.withoutEPB,
                                    pps: pps.data.withoutEPB)
  }
  
  /// Output the current NALU sequence and reset the current sequence
  private func outputSequence() {
    defer {
      sequence.removeAll()
    }
    
    guard sequence.containsSlice, let description = description else {
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

extension H264VideoDecoder: DecompressionSessionDelegate {
  func didDecompress(_ sampleBuffer: CMSampleBuffer) {
    delegate?.didDecode(sampleBuffer)
  }
}

extension H264VideoDecoder {
  /// Decode Fragmentation Unit A data by buffering fragments until a complete NALU arives
  private func decodeFU_A(_ nalu: H264NALUnit) -> H264NALUnit? {
    guard nalu.payload.count >= 1 else {
      return nil
    }
    
    let fuHeader = nalu.payload[0]
    let start = (fuHeader & 0b10000000) >> 7
    let end   = (fuHeader & 0b01000000) >> 6
    
    if start == 1 {
      // Start the NALU data buffer with the reconstructed NALU header
      fuDataBuffer = Data([(nalu.refIDC << 5) | (fuHeader & 0x1F)])
    }
    
    fuDataBuffer?.append(nalu.payload.subdata(in: 1..<nalu.payload.count))
    
    if end == 1, let data = fuDataBuffer {
      let nalu = decodeH264NALUnit(data: data)
      fuDataBuffer = nil
      return nalu
    }
    
    return nil
  }
}

/// Decode multiple NAL units from a single STAP A (Single-Time Aggregation Packet type A) payload
private func decodeSTAP_A(payload: Data) -> [H264NALUnit] {
  var offset = 0
  var nalUnits: [H264NALUnit] = []

  while offset < payload.count {
    let sizeBytes = payload.subdata(in: offset..<offset+2)
    let size = UInt16(bigEndian: sizeBytes.withUnsafeBytes { $0.load(as: UInt16.self) })
    offset += 2
    
    guard offset + Int(size) <= payload.count else {
      // Invalid STAP_A packet
      return nalUnits
    }
    
    let nalUnitData = payload.subdata(in: offset..<offset+Int(size))
    offset += Int(size)
    
    if let nalUnit = decodeH264NALUnit(data: nalUnitData) {
      nalUnits.append(nalUnit)
    }
  }

  return nalUnits
}

private func createDescription(sps: Data, pps: Data) -> CMFormatDescription? {
  let spsPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: sps.count)
  sps.copyBytes(to: spsPointer, count: sps.count)
  
  let ppsPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: pps.count)
  pps.copyBytes(to: ppsPointer, count: pps.count)
  
  defer {
    spsPointer.deallocate()
    ppsPointer.deallocate()
  }
  
  var description: CMFormatDescription?
  let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
    allocator: kCFAllocatorDefault,
    parameterSetCount: 2,
    parameterSetPointers: [
      UnsafePointer(spsPointer),
      UnsafePointer(ppsPointer),
    ],
    parameterSetSizes: [
      sps.count,
      pps.count
    ],
    nalUnitHeaderLength: 4,
    formatDescriptionOut: &description
  )
  
  guard status == noErr, let description = description else {
    print("H264VideoDecoder: Failed to create format description \(status)")
    return nil
  }
  
  return description
}
