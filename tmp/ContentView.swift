import Foundation
import Playgrounds
import SwiftUI
import Textual

struct MarkdownFileView: View {
  let path: String

  var body: some View {
    let raw =
      (try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8))
      ?? "Could not read \(path)"
    let md =
      (try? AttributedString(
        markdown: raw,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(raw)
    ScrollView { Text(md).textSelection(.enabled).padding() }
  }
}

struct ContentView: View {
  var body: some View {

    NavigationSplitView {
      Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200).toolbar(
        removing: .sidebarToggle)
    } detail: {

      VStack(spacing: 0) {
        ScrollView {
          Text("123").padding()
          // MarkdownFileView(path: "/Users/mryodo/Documents/notes/threads/test.md")
          MarkdownView(
            text: (try? String(
              contentsOfFile: "/Users/mryodo/Documents/notes/threads/test.md",
              encoding: .utf8))
              ?? "Could not read file",
            p: .sw1comm
          ).padding()
        }
        Rectangle()
          .foregroundColor(.clear)
          .frame(height: 32)
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
