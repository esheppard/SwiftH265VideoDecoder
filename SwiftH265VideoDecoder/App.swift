
import SwiftUI

@main
struct SwiftH265VideoDecoderApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
#if os(macOS)
        .frame(width: 800, height: 600)
#endif
    }
    .windowResizability(.contentSize)
  }
}
