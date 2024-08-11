//
// Copyright 2024 Elijah Sheppard
//

import Foundation

protocol SimulatedSenderDelegate: AnyObject {
  func receive(packet: RTPPacket)
}

/// Simulates sending RTP packets based on their timestamps.
class SimulatedSender {
  private var timer: Timer?
  private var index: Int = 0
  private let packets: [RTPPacket]
  private let clockRate: Double
  private var ts = RTPTimestamp()
  
  weak var delegate: SimulatedSenderDelegate?
  
  init(packets: [RTPPacket], clockRate: Double) {
    self.packets = packets
    self.clockRate = clockRate
  }
  
  func start() {
    sendNext()
  }
  
  func stop() {
    timer?.invalidate()
  }
  
  private func sendNext() {
    guard packets.count > 0 else {
      return
    }
    
    let packet = packets[index]
    delegate?.receive(packet: packet)
    
    index += 1
    if index >= packets.count {
      // Reset
      index = 0
      ts = RTPTimestamp()
      sendNext()
      return
    }
    
    let nextPacket = packets[index]
    
    let ts1 = ts.toInt64(packet.timestamp)
    let ts2 = ts.toInt64(nextPacket.timestamp)
    let interval = Double(ts2 - ts1) / clockRate
    
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
      self?.sendNext()
    }
  }
}
