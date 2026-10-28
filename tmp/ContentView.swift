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

  @Environment(Store.self) var store
  let thr = loadThread("/Users/mryodo/Documents/notes/threads/test.md")
  var body: some View {

    NavigationSplitView {
      Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200).toolbar(
        removing: .sidebarToggle)
    } detail: {

      VStack(spacing: 0) {
        ScrollView {
          Text("123").padding()
          // MarkdownView(
          //   text: (try? String(
          //     contentsOfFile: "/Users/mryodo/Documents/notes/threads/test.md",
          //     encoding: .utf8))
          //     ?? "Could not read file",
          //   p: .sw1comm
          // ).padding()
          MarkdownView(
            text: thr?.card ?? "Could not read file", p: .sw1comm
          ).padding()
        }
        footer
      }

    }
    .sheet(isPresented: Binding(get: { store.ask != nil }, set: { if !$0 { store.ask = nil } })) {
      if store.ask == .root { FolderSheet() } else { NameSheet() }
    }
    .onAppear { if Store.askRoot { store.ask = .root } }
  }

  var footer: some View {
    let p = store.p
    let hints = [
      ("j/k", "move"), ("⏎", "fold"), ("e", "edit"), ("p", "post"), ("d", "delete"),
      ("a", "new"), ("w", "workspace"), ("u", "undo"), ("b", "theme"), ("?", "keys"),
    ]
    return HStack {
      // if let e = store.error {
      //   Text(e).font(face(12, .medium)).foregroundStyle(p.red)
      // } else {
      hints.reduce(Text("")) {
        $0 + Text($1.0).font(face(12, .bold)).foregroundColor(p.ink)
          + Text(" \($1.1)    ").font(face(12)).foregroundColor(p.inkSoft)
      }
      .lineLimit(1)
      // }
      Spacer()
    }
    .padding(.horizontal, 20).padding(.vertical, 9)
    .background(p.sunk.opacity(0.6))
  }
}

struct Sidebar: View {

  @Environment(Store.self) var store

  // let rootPath = "/Users/mryodo/Documents/notes/threads"
  //
  @State private var folders: [URL] = []
  @State private var selection: URL?

  var body: some View {
    let p = store.p
    List {
      Section {
        ForEach(store.workspaces(), id: \.self) { w in
          row(
            w == store.ws ? "folder.fill" : "folder", store.wsName(w),
            store.count(w), on: w == store.ws
          ) {
            // store.commit()
            store.switchTo(w)
          }
        }
        row("plus", "New workspace", nil, on: false) {
          store.ask = .workspace(moving: nil)
        }
      } header: {
        Caps(text: "Workspaces", color: p.inkSoft)
      }
      // Section {
      //   let tags = store.allTags()
      //   if tags.isEmpty {
      //     Text("Write #something in a post").font(face(12)).foregroundStyle(p.inkSoft)
      //   }
      //   ForEach(tags, id: \.0) { tag, n in
      //     row("number", String(tag.dropFirst()), n, on: store.query == tag) {
      //       store.query = store.query == tag ? "" : tag
      //     }
      //   }
      // } header: {
      //   Caps(text: "Tags", color: p.inkSoft)
      // }
    }
    .scrollContentBackground(.hidden)
    .background(p.sunk.opacity(store.opacity).ignoresSafeArea())
  }
  func row(_ icon: String, _ name: String, _ n: Int?, on: Bool, _ tap: @escaping () -> Void)
    -> some View
  {
    let p = store.p
    return Button(action: tap) {
      HStack(spacing: 8) {
        Image(systemName: icon).foregroundStyle(on ? p.accent : p.inkSoft).frame(width: 18)
        Text(name).font(face(13, on ? .semibold : .regular)).foregroundStyle(p.ink)
          .lineLimit(1)
        Spacer()
        if let n {
          Text("\(n)").font(face(12, .semibold)).foregroundStyle(p.inkSoft)
            .monospacedDigit()
        }
      }
      .padding(.horizontal, 10).padding(.vertical, 6)
      .background(Capsule().fill(on ? p.raised : .clear))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
  }
}
