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
        ScrollView {
          Text("123").padding()
        }
        Rectangle()
          .foregroundColor(.clear)
          .frame(height: 16)
          .frame(maxWidth: .infinity)
          .background(Color(red: 1, green: 0.78, blue: 0.17))
      }

    }
  }

}

struct Sidebar: View {
  let rootPath = "/Users/mryodo/threads"
  @State private var folders: [URL] = []
  @State private var selection: URL?

  var body: some View {
    List {
      Section {
        List(folders, id: \.self, selection: $selection) { url in
          Label(url.lastPathComponent, systemImage: "folder")
        }
        .task {
          let urls =
            (try? FileManager.default.contentsOfDirectory(
              at: URL(filePath: rootPath),
              includingPropertiesForKeys: [.isDirectoryKey],
              options: .skipsHiddenFiles)) ?? []
          folders = urls.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
          }
          .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
      } header: {
        Text("workspaces".uppercased())
      }
      Section {
      } header: {
        Text("tags".uppercased())
      }
    }
  }

}
