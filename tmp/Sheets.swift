import AppKit
import SwiftUI

struct SheetFrame<Content: View>: View {
  @Environment(Store.self) var store
  let label: String
  let title: String
  @ViewBuilder let content: Content

  var body: some View {
    let p = store.p
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Caps(text: label, color: p.inkSoft)
        Text(title).font(display(22)).foregroundStyle(p.ink).lineLimit(1)
      }
      content
    }
    .padding(28)
    .frame(width: 460)
    .background(p.paper)
  }
}

func field(_ prompt: String, _ text: Binding<String>, _ p: Palette) -> some View {
  TextField("", text: text, prompt: Text(prompt).foregroundColor(p.inkSoft))
    .textFieldStyle(.plain).font(face()).foregroundStyle(p.ink)
    .padding(.horizontal, 18).frame(height: 44)
    .background(Capsule().fill(p.raised)).overlay(Capsule().strokeBorder(p.line))
}

struct NameSheet: View {
  @Environment(Store.self) var store
  @State var name = ""
  @FocusState var focus: Bool

  var body: some View {
    let p = store.p
    let thread = store.ask == .thread
    let moving: URL? = if case .workspace(let m) = store.ask { m } else { nil }
    SheetFrame(
      label: thread
        ? "New thread in \(store.wsName(store.ws))"
        : moving != nil ? "Move to a new workspace" : "New workspace",
      title: name.isEmpty ? (thread ? "Untitled" : "Unnamed") : name
    ) {
      field(thread ? "Title" : "Name", $name, p)
        .focused($focus)
        .onSubmit { store.answer(name) }
      HStack(spacing: 8) {
        Caps(
          text: thread
            ? "⏎ creates · esc cancels" : "a folder in \(store.root.lastPathComponent)",
          color: p.inkSoft)
        Spacer()
        Button("Cancel") { store.ask = nil }.buttonStyle(Pill(p: p)).keyboardShortcut(
          .cancelAction)
        Button("Create") { store.answer(name) }.buttonStyle(Pill(p: p, primary: true))
          .disabled(
            name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      if let e = store.error { Text(e).font(face(12)).foregroundStyle(p.red) }
    }
    .onAppear {
      store.error = nil
      DispatchQueue.main.async { focus = true }
    }
  }
}

struct FolderSheet: View {
  @Environment(Store.self) var store
  @State var path = ""
  @FocusState var focus: Bool

  var body: some View {
    let p = store.p
    SheetFrame(label: "Welcome to Threader", title: "Where do threads live?") {
      field("Folder", $path, p)
        .focused($focus)
        .onSubmit { store.answer(path) }
      HStack(spacing: 8) {
        Caps(text: "created if missing · ⌘, changes it", color: p.inkSoft)
        Spacer()
        Button("Browse…") {
          if let u = pickFolder(
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
          {
            path = tilde(u)
          }
        }.buttonStyle(Pill(p: p))
        Button("Use") { store.answer(path) }.buttonStyle(Pill(p: p, primary: true))
          .disabled(
            path.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .interactiveDismissDisabled()
    .onAppear {
      path = tilde(store.root)
      DispatchQueue.main.async { focus = true }
    }
  }
}

func pickFolder(_ at: URL) -> URL? {
  let panel = NSOpenPanel()
  panel.canChooseDirectories = true
  panel.canChooseFiles = false
  panel.canCreateDirectories = true
  panel.message = "Choose the folder Threader keeps its threads in"
  panel.prompt = "Use Folder"
  panel.directoryURL = at
  return panel.runModal() == .OK ? panel.url : nil
}
