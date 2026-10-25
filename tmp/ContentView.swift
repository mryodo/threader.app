import Foundation
import Playgrounds
import SwiftUI

struct ContentView: View {
  var body: some View {

    NavigationSplitView {
      Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 230).toolbar(
        removing: .sidebarToggle)
    } detail: {
      VStack(spacing: 0) {
        Text("123").padding()
        //footer
      }
    }
  }

}

struct Sidebar: View {
  let rootPath = "/Users/mryodo/threads"
  @State private var folders: [URL] = []
  @State private var selection: URL?

  var body: some View {
    Text("1234").padding()
  }

}
