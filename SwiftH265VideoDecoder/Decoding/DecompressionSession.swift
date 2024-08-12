
import Foundation
import CoreVideo
import VideoToolbox

protocol DecompressionSessionDelegate: AnyObject {
  func didDecompress(_ sampleBuffer: CMSampleBuffer)
}

/// Decompresses a ``CMSampleBuffer`` created from a CMBlockBuffer (which is composed of
/// compressed H.264 or H.265 NAL units).
///
/// Decompressed ``CMSampleBuffer`` objects are returned asynchronously via the delegate.
///
/// These decompressed sample buffers are created from ``CVImageBuffer`` which can then
/// be used for display as well as other image operations (like motion detection or filters).
class DecompressionSession {
  private var session: VTDecompressionSession?
  
  weak var delegate: DecompressionSessionDelegate?
  
  deinit {
    if let session = session {
      VTDecompressionSessionInvalidate(session)
    }
  }
  
  func decompress(_ sampleBuffer: CMSampleBuffer) {
    guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      print("DecompressionSession: Unable to get sample buffer format")
      return
    }
    
    if let session = session, !session.canAccept(description) {
      session.waitForAsynchronousFrames()
      session.invalidate()
      self.session = nil
    }
    
    if session == nil {
      startSession(with: description)
    }
    
    guard let session = session else {
      return
    }
    
    var flagsOut = VTDecodeInfoFlags()
    let status = VTDecompressionSessionDecodeFrame(session,
                                                   sampleBuffer: sampleBuffer,
                                                   flags: [._EnableAsynchronousDecompression],
                                                   frameRefcon: nil,
                                                   infoFlagsOut: &flagsOut)

    if status != noErr {
      VTDecompressionSessionInvalidate(session)
      self.session = nil
    }
  }
  
  private func startSession(with description: CMFormatDescription) {
    let callback: VTDecompressionOutputCallback = { (
          decompressionOutputRefCon: UnsafeMutableRawPointer?,
          sourceFrameRefCon: UnsafeMutableRawPointer?,
          status: OSStatus,
          infoFlags: VTDecodeInfoFlags,
          imageBuffer: CVImageBuffer?,
          presentationTime: CMTime,
          duration: CMTime) in
      guard status == 0, let imageBuffer = imageBuffer, let outputRef = decompressionOutputRefCon else {
        print("DecompressionSession: Failed to decompress frame \(status)")
        return
      }
      let selfRef = Unmanaged<DecompressionSession>.fromOpaque(outputRef).takeUnretainedValue()
      selfRef.didDecompress(imageBuffer, presentationTime: presentationTime, duration: duration)
    }
    
    var callbackRecord = VTDecompressionOutputCallbackRecord()
    callbackRecord.decompressionOutputCallback = callback
    callbackRecord.decompressionOutputRefCon = Unmanaged.passUnretained(self).toOpaque()
    
    let decoderSpec = NSMutableDictionary()
    
    #if os(macOS)
    // Note: Hardware decoding is enable by defualt on iOS
    decoderSpec[kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder] = true
    #endif

    let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                                              formatDescription: description,
                                              decoderSpecification: decoderSpec,
                                              imageBufferAttributes: nil,
                                              outputCallback: &callbackRecord,
                                              decompressionSessionOut: &session)

    guard status == noErr, session != nil else {
      print("DecompressionSession: Failed to create decompression session")
      return
    }
  }
  
  private func didDecompress(_ imageBuffer: CVImageBuffer, presentationTime: CMTime, duration: CMTime) {
    var timimgInfo = CMSampleTimingInfo(
      duration: duration,
      presentationTimeStamp: presentationTime,
      decodeTimeStamp: .invalid
    )
    
    var videoInfo: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: imageBuffer,
      formatDescriptionOut: &videoInfo
    )

    guard let videoInfo = videoInfo else {
      print("DecompressionSession: Failed to create video format description")
      return
    }

    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: imageBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: videoInfo,
      sampleTiming: &timimgInfo,
      sampleBufferOut: &sampleBuffer
    )

    if let sampleBuffer = sampleBuffer {
      sampleBuffer.setAttachment(.displayImmediately, value: true)
      delegate?.didDecompress(sampleBuffer)
    }
  }
}

private extension VTDecompressionSession {
  func canAccept(_ description: CMFormatDescription) -> Bool {
    VTDecompressionSessionCanAcceptFormatDescription(self, formatDescription: description)
  }
  
  func invalidate() {
    VTDecompressionSessionInvalidate(self)
  }
  
  func waitForAsynchronousFrames() {
    VTDecompressionSessionWaitForAsynchronousFrames(self)
  }
}
