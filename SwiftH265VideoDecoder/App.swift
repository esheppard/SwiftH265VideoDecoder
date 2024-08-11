//
// Copyright 2024 Elijah Sheppard
//

import SwiftUI

@main
struct SwiftH265VideoDecoderApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(width: 800, height: 600)
    }
    .windowResizability(.contentSize)
  }
}
