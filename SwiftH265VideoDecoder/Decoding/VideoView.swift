
import SwiftUI
import AVFoundation

/// Allows for ``CMSampleBuffer`` instances to be enqueued to the video player.
public class VideoViewBufferReceiver {
  #if os(macOS)
  fileprivate weak var receiverView: VideoNSView?
  #elseif os(iOS)
  fileprivate weak var receiverView: VideoUIView?
  #endif
  
  public init() {
    /* no-op */
  }
  
  public func enqueue(_ sampleBuffer: CMSampleBuffer) {
    DispatchQueue.main.async { [weak self] in
      self?.receiverView?.enqueue(sampleBuffer)
    }
  }
}

#if os(macOS)
/// Displays ``CMSampleBuffer`` instances.
public class VideoNSView: NSView {
  private let bufferReceiver: VideoViewBufferReceiver
  private let backgroundColor: Color
  
  init(bufferReceiver: VideoViewBufferReceiver, backgroundColor: Color) {
    self.bufferReceiver = bufferReceiver
    self.backgroundColor = backgroundColor
    super.init(frame: .zero)
    
    wantsLayer = true
    bufferReceiver.receiverView = self
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override public func makeBackingLayer() -> CALayer {
    let layer = AVSampleBufferDisplayLayer()
    layer.backgroundColor = backgroundColor.cgColor
    layer.videoGravity = .resizeAspect
    return layer
  }

  public var sampleBufferLayer: AVSampleBufferDisplayLayer {
    return layer as! AVSampleBufferDisplayLayer
  }
  
  override public func layout() {
    super.layout()
    sampleBufferLayer.frame = bounds
  }
  
  public func enqueue(_ sampleBuffer: CMSampleBuffer) {
    sampleBufferLayer.enqueue(sampleBuffer)
  }
}

/// Displays ``CMSampleBuffer`` instances.
public struct VideoView: NSViewRepresentable {
  private let bufferReceiver: VideoViewBufferReceiver
  private let backgroundColor: Color
  
  public init(bufferReceiver: VideoViewBufferReceiver, backgroundColor: Color = .black) {
    self.bufferReceiver = bufferReceiver
    self.backgroundColor = backgroundColor
  }
  
  public func makeNSView(context: Context) -> VideoNSView {
    return VideoNSView(bufferReceiver: bufferReceiver, backgroundColor: backgroundColor)
  }
  
  public func updateNSView(_ nsView: VideoNSView, context: Context) {
    /* no-op */
  }
}
#endif

#if os(iOS)
/// Displays ``CMSampleBuffer`` instances.
public class VideoUIView: UIView {
  private let bufferReceiver: VideoViewBufferReceiver
  private let bgColor: Color
  
  init(bufferReceiver: VideoViewBufferReceiver, backgroundColor: Color) {
    self.bufferReceiver = bufferReceiver
    self.bgColor = backgroundColor
    super.init(frame: .zero)
    
    bufferReceiver.receiverView = self
    setupLayer()
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  private func setupLayer() {
    let layer = AVSampleBufferDisplayLayer()
    layer.backgroundColor = bgColor.cgColor
    layer.videoGravity = .resizeAspect
    self.layer.addSublayer(layer)
  }

  public var sampleBufferLayer: AVSampleBufferDisplayLayer {
    return self.layer.sublayers!.first as! AVSampleBufferDisplayLayer
  }
  
  override public func layoutSubviews() {
    super.layoutSubviews()
    sampleBufferLayer.frame = bounds
  }
  
  public func enqueue(_ sampleBuffer: CMSampleBuffer) {
    sampleBufferLayer.enqueue(sampleBuffer)
  }
}

/// Displays ``CMSampleBuffer`` instances.
public struct VideoView: UIViewRepresentable {
  private let bufferReceiver: VideoViewBufferReceiver
  private let backgroundColor: Color

  public init(bufferReceiver: VideoViewBufferReceiver, backgroundColor: Color = .black) {
    self.bufferReceiver = bufferReceiver
    self.backgroundColor = backgroundColor
  }

  public func makeUIView(context: Context) -> VideoUIView {
    return VideoUIView(bufferReceiver: bufferReceiver, backgroundColor: backgroundColor)
  }

  public func updateUIView(_ uiView: VideoUIView, context: Context) {
    /* no-op */
  }
}

#endif
