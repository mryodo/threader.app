import Foundation
import Playgrounds
import SwiftUI

@main struct MyApp: App {
  @State private var store = Store()

  var body: some Scene {
    WindowGroup {
      ContentView().environment(store)
    }
  }
}
