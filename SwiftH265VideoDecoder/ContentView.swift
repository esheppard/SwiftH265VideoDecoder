//
// Copyright 2024 Elijah Sheppard
//

import SwiftUI
import AVFoundation

private let H26xClockRate: Double = 90_000

// MARK: - ContentViewState

private class ContentViewState: ObservableObject {
  let bufferReceiver = VideoViewBufferReceiver()
  private var decoder: VideoDecoder?
  private var sender: SimulatedSender?
  
  func loadH264() {
    sender?.stop()
    sender = nil
  
    let packets = loadPackets("h264_nal_rtp")
    guard packets.count > 0 else { return }
    
    let h264Decoder = H264VideoDecoder()
    h264Decoder.delegate = self
    decoder = h264Decoder
    
    sender = SimulatedSender(packets: packets, clockRate: H26xClockRate)
    sender?.delegate = self
    sender?.start()
  }
  
  func loadH265() {
    sender?.stop()
    sender = nil
    
    let packets = loadPackets("h265_nal_rtp")
    guard packets.count > 0 else { return }
    
    let h265Decoder = H265VideoDecoder()
    h265Decoder.delegate = self
    decoder = h265Decoder
    
    sender = SimulatedSender(packets: packets, clockRate: H26xClockRate)
    sender?.delegate = self
    sender?.start()
  }
  
  private func loadPackets(_ fileName: String) -> [RTPPacket] {
    guard let data = readBundle(fileName: fileName, withExtension: "dat") else {
      return []
    }
    return readPackets(data: data)
  }
}

extension ContentViewState: SimulatedSenderDelegate {
  func receive(packet: RTPPacket) {
    decoder?.receive(packet)
  }
}

extension ContentViewState: VideoDecoderDelegate {
  func didDecode(_ sampleBuffer: CMSampleBuffer) {
    bufferReceiver.enqueue(sampleBuffer)
  }
}


// MARK: - ContentView

struct ContentView: View {
  @StateObject private var state: ContentViewState
  
  init() {
    let state = ContentViewState()
    self._state = StateObject(wrappedValue: state)
  }
  
  var body: some View {
    VideoView(bufferReceiver: state.bufferReceiver)
      .task {
        // Modify this line to loadH264 or loadH265
        state.loadH265()
      }
  }
}

#Preview {
  ContentView()
}


// MARK: - Utils

private func readBundle(fileName: String, withExtension ext: String) -> Data? {
  guard let fileURL = Bundle.main.url(forResource: fileName, withExtension: ext) else {
    return nil
  }
  return try? Data(contentsOf: fileURL, options: .uncached)
}
