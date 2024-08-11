
import CoreMedia

extension CMSampleBuffer {
  
  enum Attachment {
    case displayImmediately
  }
  
  func setAttachment(_ attach: Attachment, value: Bool) {
    guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: true) else {
      return
    }
    
    let key: CFString
    
    switch attach {
    case .displayImmediately:
      key = kCMSampleAttachmentKey_DisplayImmediately
    }

    let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
    CFDictionarySetValue(dict,
                         Unmanaged.passUnretained(key).toOpaque(),
                         Unmanaged.passUnretained(value ? kCFBooleanTrue : kCFBooleanFalse).toOpaque())
  }
}

/// Create a SampleBuffer from a BlockBuffer and description
func createSampleBuffer(with blockBuffer: CMBlockBuffer,
                        description: CMFormatDescription,
                        presentationTime: CMTime) -> CMSampleBuffer? {
  var timingInfo = CMSampleTimingInfo(
    duration: .invalid,
    presentationTimeStamp: presentationTime,
    decodeTimeStamp: .invalid
  )
  
  var sampleBuffer : CMSampleBuffer?
  let status = CMSampleBufferCreateReady(
    allocator: kCFAllocatorDefault,
    dataBuffer: blockBuffer,
    formatDescription: description,
    sampleCount: 1,
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timingInfo,
    sampleSizeEntryCount: 0,
    sampleSizeArray: nil,
    sampleBufferOut: &sampleBuffer
  )
  
  guard status == noErr, let sampleBuffer = sampleBuffer else {
    print("VideoDecoder: Failed to create sample buffer")
    return nil
  }
  
  return sampleBuffer
}

/// Create a BlockBuffer with the given data
func createBlockBuffer(with data: Data) -> CMBlockBuffer? {
  let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
  data.copyBytes(to: pointer, count: data.count)
  
  var blockBuffer: CMBlockBuffer?
  let status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                                  memoryBlock: pointer,
                                                  blockLength: data.count,
                                                  blockAllocator: kCFAllocatorDefault,
                                                  customBlockSource: nil,
                                                  offsetToData: 0,
                                                  dataLength: data.count,
                                                  flags: .zero,
                                                  blockBufferOut: &blockBuffer)
  guard status == kCMBlockBufferNoErr else {
    print("VideoDecoder: Failed to create block buffer \(status)")
    return nil
  }
  
  return blockBuffer
}

extension Data {
  /// CMBlockBuffer requires data in AVCC format (ie. prefixed with a 4-byte length field)
  var withAVCCLengthHeader: Data {
    var length = CFSwapInt32HostToBig(UInt32(count))
    let lengthData = Data(bytes: &length, count: 4)
    return lengthData + self
  }
}

extension Data {
  /// Check if the data contains an Emulation Prevention Byte
  var containsEPB: Bool {
    var i = 0
    
    while i < count {
      if i + 2 < count,
         self[i] == 0x00,
         self[i + 1] == 0x00,
         self[i + 2] == 0x03 {
        return true
      }
      i += 1
    }
    
    return false
  }
  
  /// Remove emulation prevention bytes from the data
  var withoutEPB: Data {
    guard containsEPB else {
      return self
    }
    
    var result = Data(capacity: count)
    var i = 0

    while i < count {
      if i + 2 < count,
         self[i] == 0x00,
         self[i + 1] == 0x00,
         self[i + 2] == 0x03 {
        result.append(self[i])
        result.append(self[i + 1])
        i += 3
      }
      else {
        result.append(self[i])
        i += 1
      }
    }

    return result
  }
}

extension Data {
  
  /// Split the data on Annex B 3-byte and 4-byte start codes
  func splitOnAnnexBStartCodes() -> [Data] {
    var buffers: [Data] = []
    
    let startCode3Byte: [UInt8] = [0x00, 0x00, 0x01]
    let startCode4Byte: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    
    var offset = 0
    while offset < count {
      if let startCodeIndex = index(of: startCode3Byte, from: offset) {
        // 3 byte start code found
        buffers.append(subdata(in: offset..<startCodeIndex))
        offset = startCodeIndex + startCode3Byte.count
      }
      else if let startCodeIndex = index(of: startCode4Byte, from: offset) {
        // 4 byte start code found
        buffers.append(subdata(in: offset..<startCodeIndex))
        offset = startCodeIndex + startCode4Byte.count
      }
      else {
        // No more start codes found – add the rest of the data
        buffers.append(offset == 0 ? self : suffix(from: offset))
        break
      }
    }
    
    return buffers
  }
  
  /// Find the first index of a given sequence of bytes from a supplied starting offset
  func index(of sequence: [UInt8], from start: Int) -> Int? {
    guard sequence.count > 0, start >= 0, start < count else { return nil }
        
    var offset = start
    
    while offset + sequence.count <= count {
      let range = offset..<(offset + sequence.count)
      if self[range].elementsEqual(sequence) {
        return offset
      }
      offset += 1
    }
    
    return nil
  }
}
