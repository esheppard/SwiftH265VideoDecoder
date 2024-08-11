
import AVFoundation

protocol VideoDecoder {
  func receive(_ packet: RTPPacket)
}

protocol VideoDecoderDelegate: AnyObject {
  func didDecode(_ sampleBuffer: CMSampleBuffer)
}
