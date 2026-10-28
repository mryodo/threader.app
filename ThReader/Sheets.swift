import AppKit
import SwiftUI
import SwiftUIMath
import Textual

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

struct WorkspacePicker: View {
  @Environment(Store.self) var store
  @State var sel = 0
  @State var naming = false
  @State var name = ""
  @FocusState var focus: Bool
  @FocusState var nameFocus: Bool

  var body: some View {
    let p = store.p
    let ws = store.workspaces()
    let title = store.pickMove.flatMap { u in store.threads.first { $0.path == u }?.title }
    SheetFrame(
      label: title == nil ? "Workspaces" : "Move thread to",
      title: title ?? store.wsName(store.ws)
    ) {
      VStack(spacing: 4) {
        ForEach(Array(ws.enumerated()), id: \.offset) { i, w in
          row(
            i, w == store.ws ? "folder.fill" : "folder", store.wsName(w),
            "\(plural(store.count(w), "thread"))\(w == store.ws ? " · open" : "")"
          )
          .onTapGesture {
            sel = i
            choose(ws)
          }
        }
        if naming {
          field("New workspace name", $name, p)
            .focused($nameFocus)
            .onSubmit { create() }
            .onExitCommand {
              naming = false
              focus = true
            }
            .onAppear { DispatchQueue.main.async { nameFocus = true } }
        } else {
          row(ws.count, "plus", "New workspace", "").onTapGesture {
            sel = ws.count
            choose(ws)
          }
        }
      }
      HStack {
        Caps(text: "j k move · ⏎ choose · esc cancel", color: p.inkSoft)
        Spacer()
        Button("Cancel") { close() }.buttonStyle(Pill(p: p))
      }
      if let e = store.error { Text(e).font(face(12)).foregroundStyle(p.red) }
    }
    .focusable().focused($focus).focusEffectDisabled()
    .onKeyPress { k in
      guard !naming else { return .ignored }
      switch (k.key, k.characters) {
      case (.downArrow, _), (_, "j"): sel = min(sel + 1, ws.count)
      case (.upArrow, _), (_, "k"): sel = max(sel - 1, 0)
      case (.return, _): choose(ws)
      case (.escape, _), (_, "q"): close()
      default: return .ignored
      }
      return .handled
    }
    .onAppear {
      store.error = nil
      sel = ws.firstIndex(of: store.ws) ?? 0
      DispatchQueue.main.async { focus = true }
    }
  }

  func row(_ i: Int, _ icon: String, _ name: String, _ meta: String) -> some View {
    let p = store.p
    let on = i == sel
    return HStack(spacing: 12) {
      Image(systemName: icon).foregroundStyle(on ? p.onButton : p.accent).frame(width: 20)
      Text(name).font(face(15, .semibold)).foregroundStyle(on ? p.onButton : p.ink).lineLimit(1)
      Spacer()
      Text(meta.uppercased()).font(face(11, .semibold)).tracking(1.2).foregroundStyle(
        on ? p.onButton.opacity(0.75) : p.inkSoft)
    }
    .padding(.horizontal, 18).frame(height: 44)
    .background(Capsule().fill(on ? p.button : p.raised))
    .overlay(Capsule().strokeBorder(on ? .clear : p.line))
    .contentShape(Capsule())
  }

  func choose(_ ws: [String]) {
    if sel == ws.count {
      naming = true
      return
    }
    open(ws[sel])
  }

  func create() {
    let n = name.trimmingCharacters(in: .whitespaces)
    guard store.newWorkspace(n) else { return }
    open(n)
  }

  func open(_ w: String) {
    if let m = store.pickMove {
      store.move(m, to: w)
    } else {
      store.commit()
      store.query = ""
      store.switchTo(w)
    }
    if store.error == nil { close() }
  }

  func close() {
    store.picking = false
    store.pickMove = nil
  }
}

func row<C: View>(_ label: String, _ p: Palette, @ViewBuilder _ content: () -> C) -> some View {
  HStack(alignment: .center, spacing: 16) {
    Text(label).font(face(13, .bold)).foregroundStyle(p.ink).frame(width: 230, alignment: .leading)
    content()
  }
}

func section(_ title: String, _ p: Palette) -> some View {
  Caps(text: title, color: p.accent).padding(.top, 10)
}

struct TextSettings: View {
  @Environment(Store.self) var store

  // monospaced families first: posts and the editor read best in one
  static let families: (mono: [String], other: [String]) = {
    let fm = NSFontManager.shared
    let all = fm.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted()
    let mono = all.filter {
      fm.font(withFamily: $0, traits: [], weight: 5, size: 12)?.isFixedPitch == true
    }
    return (mono, all.filter { !mono.contains($0) })
  }()

  var body: some View {
    @Bindable var store = store
    let p = store.p
    VStack(alignment: .leading, spacing: 8) {
      section("Text", p)
      row("Font", p) {
        Menu {
          Section("Monospaced") {
            ForEach(TextSettings.families.mono, id: \.self) { f in
              Button(f) { store.fontFamily = f }
            }
          }
          Section("Other") {
            ForEach(TextSettings.families.other, id: \.self) { f in
              Button(f) { store.fontFamily = f }
            }
          }
        } label: {
          Text(store.fontFamily + "  ▾").font(face(13, .semibold)).foregroundStyle(p.ink)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(p.sunk))
      }
      row("Style", p) {
        styleMenu($store.fontStyle, "Regular", p)
        Text("for body text and the editor").font(face(13)).foregroundStyle(p.inkSoft)
      }
      row("Bold", p) {
        styleMenu($store.boldStyle, "Bold", p)
        Text("for bold text and headings").font(face(13)).foregroundStyle(p.inkSoft)
      }
      row("Size", p) {
        Button("−") { store.fontSize -= 1 }.buttonStyle(Pill(p: p))
        Text("\(Int(store.fontSize)) pt").font(face(13, .bold)).foregroundStyle(p.ink).frame(
          width: 52)
        Button("+") { store.fontSize += 1 }.buttonStyle(Pill(p: p))
        Text("⌘+ ⌘− ⌘0").font(face(13)).foregroundStyle(p.inkSoft)
      }
      row("Math font", p) {
        Menu {
          ForEach(mathFaces, id: \.name) { m in Button(m.name) { store.mathFont = m.name } }
        } label: {
          Text(store.mathFont + "  ▾").font(face(13, .semibold)).foregroundStyle(p.ink)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Capsule().fill(p.sunk))
        Math("e^{i\\pi} + 1 = 0").mathFont(.init(name: .init(rawValue: mathFace.rawValue), size: 14))
          .foregroundStyle(p.inkSoft).id(store.mathFont)
      }
      row("Line spacing", p) {
        Slider(value: $store.lineSpacing, in: 0...0.5, step: 0.02).tint(p.accent)
        Text(String(format: "%.2f em", store.lineSpacing)).font(face(13))
          .foregroundStyle(p.inkSoft).frame(width: 96, alignment: .trailing)
      }
    }
  }
}

extension TextSettings {
  /// A menu of the font family's styles, showing `fallback` if `style` isn't one.
  func styleMenu(_ style: Binding<String>, _ fallback: String, _ p: Palette) -> some View {
    let styles = fontStyles(store.fontFamily).map(\.style)
    return Menu {
      ForEach(styles, id: \.self) { st in Button(st) { style.wrappedValue = st } }
    } label: {
      Text((styles.contains(style.wrappedValue) ? style.wrappedValue : fallback) + "  ▾")
        .font(face(13, .semibold)).foregroundStyle(p.ink)
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .padding(.horizontal, 14).padding(.vertical, 6)
    .background(Capsule().fill(p.sunk))
    .disabled(styles.count < 2)
  }
}

struct SettingsView: View {
  @Environment(Store.self) var store
  @State var draft: String?

  var body: some View {
    @Bindable var store = store
    let p = store.p
    VStack(alignment: .leading, spacing: 8) {
      TextSettings()
      section("Theme", p)
      ScrollView(.horizontal) {
        HStack(spacing: 8) {
          ForEach(Palette.themes, id: \.name) { t in
            Button {
              store.setTheme(t.name)
            } label: {
              HStack(spacing: 7) {
                Circle().fill(t.palette.card).frame(width: 12, height: 12)
                  .overlay(Circle().strokeBorder(t.palette.paper, lineWidth: 2))
                Text(t.name)
              }
            }.buttonStyle(Pill(p: p, primary: store.theme == t.name)).fixedSize()
          }
        }.padding(.bottom, 10)  // room for the scroller
      }
      section("Folder", p)
      row("Threads folder", p) {
        Text(tilde(store.root)).font(face(13)).foregroundStyle(p.inkSoft)
          .lineLimit(1).truncationMode(.middle)
        Spacer()
        Button("Change…") { if let u = pickFolder(store.root) { store.setRoot(u) } }
          .buttonStyle(Pill(p: p)).fixedSize()
      }
      section("Window", p)
      row("Opacity", p) {
        Slider(value: $store.opacity, in: 0.3...1).tint(p.accent)
        Text(store.opacity >= 1 ? "solid" : "\(Int(store.opacity * 100))%").font(face(13))
          .foregroundStyle(p.inkSoft).frame(width: 96, alignment: .trailing)
      }
      row("Blur", p) {
        Slider(value: $store.blur, in: 0...40).tint(p.accent)
        Text(
          store.opacity >= 1 ? "when see-through" : store.blur < 1 ? "none" : "\(Int(store.blur)) px"
        ).font(face(13)).foregroundStyle(p.inkSoft).frame(width: 96, alignment: .trailing)
      }
      .disabled(store.opacity >= 1)
      row("Title cards", p) {
        Toggle("", isOn: $store.cardsClear).toggleStyle(.switch).labelsHidden().tint(p.accent)
        Text(store.cardsClear ? "see-through with the window" : "always solid").font(face(13))
          .foregroundStyle(p.inkSoft)
      }
      .disabled(store.opacity >= 1)
      row("Glass cards", p) {
        Toggle("", isOn: $store.cardsGlass).toggleStyle(.switch).labelsHidden().tint(p.accent)
        Text(store.cardsGlass ? "title cards in Liquid Glass" : "off").font(face(13))
          .foregroundStyle(p.inkSoft)
      }
      row("Glass colour", p) {
        Slider(value: $store.glassTint, in: 0...1).tint(p.accent)
        Text("\(Int(store.glassTint * 100))% card").font(face(13))
          .foregroundStyle(p.inkSoft).frame(width: 96, alignment: .trailing)
      }
      .disabled(!store.cardsGlass)
      section("LaTeX preamble", p)
      row("\\newcommand  \\def", p) {
        Text("macros for math previews and completion").font(face(13)).foregroundStyle(p.inkSoft)
      }
      row("\\usepackage{name}", p) {
        Text("reads name.sty from the threads folder").font(face(13)).foregroundStyle(p.inkSoft)
      }
      TextEditor(text: Binding(get: { draft ?? store.preamble }, set: { draft = $0 }))
        .font(face(13)).foregroundStyle(p.ink)
        .scrollContentBackground(.hidden)
        .padding(10).frame(height: 150)
        .background(RoundedRectangle(cornerRadius: 14).fill(p.sunk))
        .padding(.top, 4)
      HStack(spacing: 8) {
        Text("\(texMacros.count) macros · \(Store.preambleFile)").font(face(13)).foregroundStyle(
          p.inkSoft)
        Spacer()
        Button("Revert") { draft = nil }.buttonStyle(Pill(p: p)).disabled(draft == nil)
        Button("Save") {
          store.savePreamble(draft ?? store.preamble)
          draft = nil
        }.buttonStyle(Pill(p: p, primary: true)).disabled(draft == nil)
      }
    }
    .padding(28)
    .frame(width: 620)
    .ignoresSafeArea(edges: .top)  // up into the hidden title bar
    .background(p.paper.ignoresSafeArea())
    // no title bar at all: ⌘W closes it
    .background(WindowGlass(clear: false, blur: 0, paper: p.paper, buttons: false))
    .toolbar(removing: .title)
    .toolbarBackground(.hidden, for: .windowToolbar)
    .preferredColorScheme(store.light ? .light : .dark)
  }
}

struct Help: View {
  @Environment(Store.self) var store
  @FocusState var focus: Bool

  static let keys: [(String, String)] = [
    ("", "List"),
    ("j k  g G", "move between cards and posts · first / last"),
    ("⏎ space  l h", "fold or unfold · unfold · fold"),
    ("e  p  d", "edit selected · new post · delete post"),
    ("u  ⌃R", "undo / redo saved changes"),
    ("a  P", "new thread · pin / unpin thread to the top"),
    ("/  esc", "search, or #tag · clear"),
    ("click #tag", "the posts with that tag"),
    ("click [[thread#2]]", "jump to a thread, or its 2nd post"),
    ("w  m  ⌘O", "switch workspace · move thread to a workspace"),
    ("s  ⌃⌘S", "show or hide the sidebar"),
    ("b  ⌘,", "light / dark · themes: sw1comm ayugloom everforest minischeme2"),
    ("⌘+ ⌘−  ⌘0  ⌘,", "text size · default · font"),
    ("", "Editor (vim)"),
    ("h j k l w b e 0 ^ $", "motions, with counts · gg G"),
    ("d c y  dd cc yy", "operators + motion or text object (iw a\" i( ap)"),
    ("x X D C s S r J p P", "edit in place · paste"),
    ("i a I A o O", "insert mode · esc back to normal"),
    ("v V  .  u ⌃R", "visual · repeat last change · undo / redo"),
    ("/ ? n N * #", "search inside the post"),
    ("\\na… tab  ⌃N ⌃P", "complete a command · preamble macros first"),
    ("[[na…  [[thread#", "complete a thread link · then one of its posts"),
    (":w ⌘S  :wq esc  :q!", "write · write and close · discard"),
  ]

  var body: some View {
    let p = store.p
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(Help.keys.enumerated()), id: \.offset) { _, kv in
        if kv.0.isEmpty {
          Caps(text: kv.1, color: p.accent).padding(.top, 10)
        } else {
          HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(kv.0).font(face(13, .bold)).foregroundStyle(p.ink).frame(
              width: 230, alignment: .leading)
            Text(kv.1).font(face(13)).foregroundStyle(p.inkSoft)
          }
        }
      }
      TextSettings()
      HStack {
        Spacer()
        Button("Close") { store.help = false }.buttonStyle(Pill(p: p, primary: true))
      }
    }
    .padding(28)
    .frame(width: 620)
    .background(p.paper)
    .focusable().focused($focus).focusEffectDisabled()
    .onKeyPress { _ in
      store.help = false  // any key closes, as in the terminal
      return .handled
    }
    .onAppear { focus = true }
  }
}
