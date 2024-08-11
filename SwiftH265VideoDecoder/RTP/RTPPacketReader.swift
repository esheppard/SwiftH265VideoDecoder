
import Foundation

func readPackets(data: Data) -> [RTPPacket] {
  var offset: Int = 0
  var packets: [RTPPacket] = []
  
  while (offset + 4) < data.count {
    // Packets are stored as raw data prefixed with a 4-byte length header
    let lengthData = Array(data[offset..<offset+4])
    let length = Int(CFSwapInt32HostToBig(bytesToUInt32(lengthData)))
    offset += 4
    
    let packetData = data.subdata(in: offset..<offset+length)
    offset += length
    
    if let packet = RTPPacket(data: packetData) {
      packets.append(packet)
    }
  }
  
  return packets
}

private let RTP_PACKET_HEADER_LENGTH = 12

private extension RTPPacket {
  init?(data: Data) {
    guard data.count >= RTP_PACKET_HEADER_LENGTH else {
      return nil
    }
    
    let version       = data[0] & 0b11000000 >> 6
    let hasExtensions = data[0] & 0b00010000 != 0
    let csrcCount     = data[0] & 0b00001111
    let marker        = data[1] & 0b10000000 != 0
    let payloadType   = data[1] & 0b01111111
    
    let timestamp = bytesToUInt32(Array(data[4...7]))
    let sequence  = bytesToUInt16(Array(data[2...3]))
    let ssrc      = bytesToUInt32(Array(data[8...11]))
    
    var csrc: [UInt32] = []
    for i in 0 ..< csrcCount {
      let csrcOffset: Int = 12 + Int(i*4)
      let csrcBytes = Array(data[csrcOffset...(csrcOffset+3)])
      csrc.append(bytesToUInt32(csrcBytes))
    }
    
    var headerLength = Int(12 + csrcCount*4)
    var extensions: Data?
    
    if hasExtensions {
      let extensionCount = bytesToUInt16(Array(data[headerLength+2...headerLength+3]))
      extensions = Data(data[headerLength + 4...headerLength + 4 + Int(extensionCount*4) - 1])
      headerLength = headerLength + 4 + Int(extensionCount*4)
    }
    
    let payload = Data(data[headerLength...])
    
    self.version = version
    self.payload = payload
    self.payloadType = payloadType
    self.sequence = sequence
    self.ssrc = ssrc
    self.csrc = csrc
    self.timestamp = timestamp
    self.marker = marker
    self.extensions = extensions
  }
}


// MARK: - Utils

private func bytesToUInt16(_ bytes: Array<UInt8>) -> UInt16 {
  return UInt16(bytes[bytes.startIndex]) << 8 | UInt16(bytes[bytes.startIndex + 1])
}

private func bytesToUInt32(_ bytes: Array<UInt8>) -> UInt32 {
  return UInt32(bytes[bytes.startIndex]) << 24 | UInt32(bytes[bytes.startIndex + 1]) << 16 |
         UInt32(bytes[bytes.startIndex + 2]) << 8 | UInt32(bytes[bytes.startIndex + 3])
}
