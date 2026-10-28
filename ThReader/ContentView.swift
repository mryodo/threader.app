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
  @FocusState var listFocus: Bool
  @FocusState var searchFocus: Bool
  @State var hover = false  // the pointer is over the top of the list
  @State var searching = false

  var body: some View {

    NavigationSplitView(
      columnVisibility: Binding(
        get: { store.showSidebar ? .all : .detailOnly },
        set: { store.showSidebar = $0 != .detailOnly })
    ) {
      Sidebar().navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200).toolbar(
        removing: .sidebarToggle)
    } detail: {

      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            list.padding(.horizontal, 36).padding(.top, 52).padding(.bottom, 28)
              .frame(maxWidth: 820).frame(maxWidth: .infinity)
          }
          .onChange(of: store.sel) {
            if let s = store.sel { withAnimation(.snappy) { proxy.scrollTo(s) } }
          }
        }
        footer
      }
      .background(store.p.paper.opacity(store.opacity).ignoresSafeArea())
      .focusable().focused($listFocus).focusEffectDisabled()
      // outside the focusable list, or the search field can't take focus
      .overlay(alignment: .topTrailing) { topBar }
      .onContinuousHover { phase in
        if case .active(let at) = phase { hover = at.y < 64 } else { hover = false }
      }
      .onAppear { listFocus = true }

    }
    .background(WindowGlass(clear: store.opacity < 1, blur: store.blur, paper: store.p.paper))
    // on the whole window, so the keys work with the sidebar focused too
    .onKeyPress(action: keys)
    .id("\(store.fontSize) \(store.fontFamily) \(store.fontStyle) \(store.lineSpacing) \(store.preambleVersion)")  // read when views are built
    .environment(
      \.openURL,
      OpenURLAction { url in
        let rest = url.absoluteString.drop { $0 != ":" }.dropFirst().removingPercentEncoding ?? ""
        switch url.scheme {
        case "threader-link":
          // deferred so it runs after the card's own tap handler, which selects the clicked card
          DispatchQueue.main.async { store.follow(rest) }
        case "threader-tag": store.query = "#" + rest
        default: return .systemAction
        }
        return .handled
      })
    .preferredColorScheme(store.light ? .light : .dark)
    .tint(store.p.accent)
    .onReceive(
      NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
    ) { _ in store.reload() }
    .onChange(of: store.editing == nil && store.adding == nil) { if $1 { listFocus = true } }
    .sheet(isPresented: Bindable(store).help) { Help() }
    .sheet(isPresented: Bindable(store).picking) { WorkspacePicker() }
    .sheet(isPresented: Binding(get: { store.ask != nil }, set: { if !$0 { store.ask = nil } })) {
      if store.ask == .root { FolderSheet() } else { NameSheet() }
    }
    .onAppear { if Store.askRoot { store.ask = .root } }
  }

  var list: some View {
    let p = store.p
    let shown = store.shown()
    return VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 4) {
        Caps(
          text: store.query.isEmpty
            ? plural(store.threads.count, "thread")
            : "\(plural(shown.count, "thread")) matching \(store.query)", color: p.inkSoft)
        Text(store.wsName(store.ws)).font(display(24)).foregroundStyle(p.ink)
      }
      if shown.isEmpty {
        Text(store.threads.isEmpty ? "No threads yet. Press a to start one." : "Nothing matches.")
          .font(face(15)).foregroundStyle(p.inkSoft).padding(.top, 40).frame(maxWidth: .infinity)
      }
      ForEach(shown, id: \.0.id) { t, notes in ThreadView(t: t, notes: notes) }
    }
  }

  /// The new-thread, theme and search buttons, shown while the pointer is near the
  /// top or a search is open.
  var topBar: some View {
    @Bindable var store = store
    let p = store.p
    let open = searching || !store.query.isEmpty
    func round(_ icon: String, _ help: String, _ tap: @escaping () -> Void) -> some View {
      Button(action: tap) {
        Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(p.ink)
          .frame(width: 32, height: 32)
          .background(Circle().fill(p.raised)).overlay(Circle().strokeBorder(p.line))
      }.buttonStyle(.plain).help(help)
    }
    return HStack(spacing: 8) {
      if open {
        TextField("Search, or #tag", text: $store.query)
          .textFieldStyle(.plain).font(face(13)).foregroundStyle(p.ink)
          .padding(.horizontal, 14).frame(width: 240, height: 32)
          .background(Capsule().fill(p.raised)).overlay(Capsule().strokeBorder(p.line))
          .focused($searchFocus)
          // it didn't exist yet when search opened
          .onAppear { DispatchQueue.main.async { searchFocus = true } }
          .onSubmit { listFocus = true }
          .onKeyPress(.escape) {
            closeSearch()
            return .handled
          }
      }
      round("square.and.pencil", "New thread (a)") { store.ask = .thread }
      round(store.light ? "moon.fill" : "sun.max.fill", "Light / dark (b)") {
        store.toggleTheme()
      }
      round(open ? "xmark" : "magnifyingglass", "Search (/)") {
        open ? closeSearch() : openSearch()
      }
    }
    .padding(.top, 12).padding(.trailing, 16)
    .opacity(hover || open ? 1 : 0)
    .allowsHitTesting(hover || open)
    .animation(.easeOut(duration: 0.15), value: hover || open)
  }

  func openSearch() {
    searching = true
    DispatchQueue.main.async { searchFocus = true }
  }
  func closeSearch() {
    searching = false
    store.query = ""
    listFocus = true
  }

  /// The terminal app's list keys, without the editing ones.
  func keys(_ k: KeyPress) -> KeyPress.Result {
    // typing goes to the editor, the search field and the sheets' fields
    guard store.editing == nil, store.adding == nil, !searchFocus, !store.help, !store.picking,
      store.ask == nil
    else { return .ignored }
    store.error = nil
    let s = store.sel
    if k.modifiers.contains(.control), k.key == "r" {
      store.undoFile(redoing: true)
      return .handled
    }
    if !k.modifiers.subtracting([.shift, .numericPad, .function]).isEmpty { return .ignored }
    switch k.characters {
    case "j": store.step(1)
    case "k": store.step(-1)
    case "g": store.sel = store.items().first
    case "G": store.sel = store.items().last
    case "\r", " ":
      if let s {
        store.unfolded.formSymmetricDifference([s.path])
        store.sel = Pos(path: s.path, note: -1)
      }
    case "l": if let s { store.unfolded.insert(s.path) }
    case "h":
      if let s {
        store.unfolded.remove(s.path)
        store.sel = Pos(path: s.path, note: -1)
      }
    case "e", "i": if let s { store.edit(s) }
    case "p", "o": if let s { store.addNote(s.path) }
    case "s": store.showSidebar.toggle()
    case "w":
      store.pickMove = nil
      store.picking = true
    case "m":
      if let s {
        store.pickMove = s.path
        store.picking = true
      }
    case "P": if let s { store.togglePin(s.path) }
    case "d": if let s { store.deleteNote(s) }
    case "a": store.ask = .thread
    case "u": store.undoFile()
    case "b": store.toggleTheme()
    case "?": store.help = true
    case "/": openSearch()
    case "\u{1b}": closeSearch()
    default:
      switch k.key {
      case .downArrow: store.step(1)
      case .upArrow: store.step(-1)
      default: return .ignored
      }
    }
    return .handled
  }

  var footer: some View {
    let p = store.p
    let hints = [
      ("j/k", "move"), ("⏎", "fold"), ("e", "edit"), ("p", "post"), ("d", "delete"),
      ("a", "new"), ("w", "workspace"), ("u", "undo"), ("b", "theme"), ("?", "keys"),
    ]
    return HStack {
      if let e = store.error {
        Text(e).font(face(12, .medium)).foregroundStyle(p.red)
      } else {
        hints.reduce(Text("")) {
          $0 + Text($1.0).font(face(12, .bold)).foregroundColor(p.ink)
            + Text(" \($1.1)    ").font(face(12)).foregroundColor(p.inkSoft)
        }
        .lineLimit(1)
      }
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
            store.commit()
            store.query = ""
            store.switchTo(w)
          }
        }
        row("plus", "New workspace", nil, on: false) {
          store.ask = .workspace(moving: nil)
        }
      } header: {
        Caps(text: "Workspaces", color: p.inkSoft).padding(.top, 32)
      }
      Section {
        let tags = store.allTags()
        if tags.isEmpty {
          Text("Write #something in a post").font(face(12)).foregroundStyle(p.inkSoft)
        }
        ForEach(tags, id: \.0) { tag, n in
          row("number", String(tag.dropFirst()), n, on: store.query == tag) {
            store.query = store.query == tag ? "" : tag
          }
        }
      } header: {
        Caps(text: "Tags", color: p.inkSoft)
      }
    }
    .scrollContentBackground(.hidden)
    // just below the window buttons, rather than below a whole title bar
    .ignoresSafeArea(edges: .top)
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
