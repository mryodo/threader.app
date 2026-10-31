// The iPhone app: the same cards and timeline, with buttons standing in for
// the keys, and Runestone (the editor from the Runestone app) for writing.
#if os(iOS)
import Runestone
import SwiftUI
import TreeSitterMarkdownInlineRunestone
import TreeSitterMarkdownRunestone
import UIKit
import UniformTypeIdentifiers
import WidgetKit

struct PhoneView: View {
  @Environment(Store.self) var store
  @Environment(\.scenePhase) var phase
  @State var pickingFolder = false
  @State var settings = false

  var body: some View {
    @Bindable var store = store
    let p = store.p
    let shown = store.shown()
    NavigationStack {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            if shown.isEmpty {
              Text(store.threads.isEmpty ? "No threads yet. Tap ✎ to start one." : "Nothing matches.")
                .font(face(15)).foregroundStyle(p.inkSoft).padding(.top, 40)
                .frame(maxWidth: .infinity)
            }
            ForEach(shown, id: \.0.id) { t, notes in ThreadView(t: t, notes: notes) }
          }
          .padding(.horizontal, 16).padding(.vertical, 12)
        }
        // fonts and spacing are read when views are built
        .id("\(store.fontSize) \(store.fontFamily) \(store.fontStyle) \(store.boldStyle) \(store.mathFont) \(store.lineSpacing) \(store.preambleVersion)")
        // only for links: scrolling on every tap moves the post from under the finger
        .onChange(of: store.jump) {
          if let s = store.jump { withAnimation(.snappy) { proxy.scrollTo(s, anchor: .top) } }
        }
      }
      .background(p.paper.ignoresSafeArea())
      .navigationTitle(store.wsName(store.ws))
      .searchable(text: $store.query, prompt: "Search, or #tag")
      .refreshable { store.reload() }
      .toolbar {
        ToolbarItemGroup(placement: .topBarLeading) {
          workspaces
          Button { settings = true } label: { Image(systemName: "gearshape") }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button { store.toggleTheme() } label: {
            Image(systemName: store.light ? "moon" : "sun.max")
          }
          Button { store.ask = .thread } label: { Image(systemName: "square.and.pencil") }
        }
      }
      .safeAreaInset(edge: .bottom) {
        if let e = store.error {
          Text(e).font(face(12, .medium)).foregroundStyle(p.red)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.sunk)
            .onTapGesture { store.error = nil }
        }
      }
    }
    .environment(\.openURL, followLinks(store))
    .onOpenURL { _ = followLinks(store)($0) }  // the widget's threads
    .preferredColorScheme(store.light ? .light : .dark)
    .tint(p.accent)
    .onChange(of: phase) { if $1 == .active { store.reload() } }
    // pick the Mac's threads folder in iCloud Drive to share it
    .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) {
      if case .success(let u) = $0 { store.pickRoot(u) }
    }
    .sheet(isPresented: $settings) { PhoneSettings() }
    .sheet(isPresented: Binding(get: { store.ask != nil }, set: { if !$0 { store.ask = nil } })) {
      NameSheet().presentationDetents([.medium])
    }
  }

  var workspaces: some View {
    Menu {
      ForEach(store.workspaces(), id: \.self) { w in
        Button {
          store.commit()
          store.query = ""
          store.switchTo(w)
        } label: {
          Label(
            "\(store.wsName(w))  \(store.count(w))", systemImage: w == store.ws ? "checkmark" : "folder")
        }
      }
      Divider()
      Button("New Workspace…", systemImage: "plus") { store.ask = .workspace(moving: nil) }
      Button("Threads Folder…", systemImage: "icloud") { pickingFolder = true }
    } label: {
      Image(systemName: "folder")
    }
  }
}

/// What the widget shows; the same shape as Recent in ThReaderWidget.swift.
struct WidgetRecent: Codable {
  var workspace: String
  var threads: [Item]
  struct Item: Codable { var title, name: String, posts: Int, date: Date }
}

extension Store {
  /// Leaves the latest threads where the widget can read them.
  func shareWithWidget() {
    guard
      let u = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.com.mryodo.threader")
    else { return }
    let r = WidgetRecent(
      workspace: wsName(ws),
      threads: threads.prefix(8).map {
        .init(
          title: $0.title, name: $0.path.deletingPathExtension().lastPathComponent,
          posts: $0.notes.count, date: $0.mtime)
      })
    guard let d = try? JSONEncoder().encode(r) else { return }
    let file = u.appendingPathComponent("recent.json")
    if (try? Data(contentsOf: file)) == d { return }  // reloads are frequent; widget reloads are budgeted
    try? d.write(to: file)
    WidgetCenter.shared.reloadAllTimelines()
  }
}

/// The post or card being edited, in place in the list, as on the Mac.
struct Editor: View {
  @Environment(Store.self) var store
  var pal: Palette? = nil
  @State var height: CGFloat = 44

  var body: some View {
    let p = pal ?? store.p
    VStack(alignment: .leading, spacing: 10) {
      MarkdownEditor(text: Bindable(store).draft, p: p, height: $height)
        .frame(height: height)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(p.sunk))
      HStack(spacing: 10) {
        Spacer()
        Button("Discard") { store.discard() }.buttonStyle(Pill(p: p))
        Button("Save") { store.commit() }.buttonStyle(Pill(p: p, primary: true))
      }
    }
  }
}

/// Runestone's TextView, with tree-sitter's markdown grammar and the theme's
/// colours, as tall as its text: the list scrolls, not the editor.
struct MarkdownEditor: UIViewRepresentable {
  @Binding var text: String
  let p: Palette
  @Binding var height: CGFloat

  func makeUIView(context: Context) -> FitTextView {
    let v = FitTextView()
    v.onHeight = { h in DispatchQueue.main.async { height = h } }  // not during layout
    v.isScrollEnabled = false
    v.editorDelegate = context.coordinator
    v.backgroundColor = .clear
    v.isLineWrappingEnabled = true
    v.lineHeightMultiplier = 1 + lineGap
    v.textContainerInset = .zero
    v.smartQuotesType = .no  // they'd break code and math
    v.smartDashesType = .no
    v.insertionPointColor = UIColor(p.accent)
    v.selectionBarColor = UIColor(p.accent)
    v.selectionHighlightColor = UIColor(p.accent).withAlphaComponent(0.25)
    let bar = UIHostingController(
      rootView: KeyBar(p: p) { [weak v] key in
        guard let v else { return }
        if let key { typeKey(key, in: v) } else { _ = v.resignFirstResponder() }
        text = v.text
      })
    bar.view.frame.size.height = 52
    bar.view.autoresizingMask = .flexibleWidth
    bar.view.backgroundColor = .clear
    bar.safeAreaRegions = []  // following the keyboard's insets, it lays itself out forever
    v.inputAccessoryView = bar.view
    context.coordinator.bar = bar  // the view alone doesn't keep its controller
    v.setState(
      TextViewState(
        text: text, theme: MarkdownTheme(p), language: .markdown,
        languageProvider: context.coordinator))
    DispatchQueue.main.async { _ = v.becomeFirstResponder() }
    return v
  }

  func updateUIView(_ v: FitTextView, context: Context) {}  // text only flows out of the view

  // let the keyboard go before the view does, not while SwiftUI tears it down
  static func dismantleUIView(_ v: FitTextView, coordinator: Coordinator) {
    v.onHeight = { _ in }
    v.inputAccessoryView = nil
    _ = v.resignFirstResponder()
  }

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  final class Coordinator: TextViewDelegate, TreeSitterLanguageProvider {
    let text: Binding<String>
    var bar: UIViewController?
    init(text: Binding<String>) { self.text = text }

    func textViewDidChange(_ v: TextView) { text.wrappedValue = v.text }

    // the editor doesn't scroll, so keep the cursor above the keyboard by
    // scrolling the list; after the height has caught up with a new line
    func textViewDidChangeSelection(_ v: TextView) {
      DispatchQueue.main.async {
        guard let end = v.selectedTextRange?.end else { return }
        var s = v.superview
        while s != nil, !(s is UIScrollView) { s = s?.superview }
        guard let list = s as? UIScrollView else { return }
        list.scrollRectToVisible(
          v.convert(v.caretRect(for: end), to: list).insetBy(dx: 0, dy: -32), animated: true)
      }
    }

    // the block grammar hands paragraphs and headings to the inline one
    func treeSitterLanguage(named name: String) -> TreeSitterLanguage? {
      name == "markdown_inline" ? .markdownInline : nil
    }
  }
}

final class FitTextView: TextView {
  var onHeight: (CGFloat) -> Void = { _ in }
  private var last: CGFloat = 0

  override func layoutSubviews() {
    super.layoutSubviews()
    let h = max(contentSize.height, 44)
    if h != last {
      last = h
      onHeight(h)
    }
  }
}

/// The markdown keys over the keyboard: a pair wraps the selection
/// (or the cursor), a line marker toggles at the start of the line.
let mdKeys: [(label: String, open: String, close: String?)] = [
  ("H", "# ", nil), ("B", "**", "**"), ("I", "*", "*"), ("S", "~~", "~~"), ("`", "`", "`"),
  ("$", "$", "$"), ("•", "- ", nil), ("☐", "- [ ] ", nil), (">", "> ", nil), ("[[", "[[", "]]"),
  ("#", "#", ""),
]

func typeKey(_ k: (label: String, open: String, close: String?), in v: TextView) {
  let r = v.selectedRange
  let ns = v.text as NSString
  guard let close = k.close else {
    let start = ns.lineRange(for: NSRange(location: r.location, length: 0)).location
    let has = ns.substring(from: start).hasPrefix(k.open)
    let n = (k.open as NSString).length
    v.replace(NSRange(location: start, length: has ? n : 0), withText: has ? "" : k.open)
    v.selectedRange = NSRange(location: max(start, r.location + (has ? -n : n)), length: r.length)
    return
  }
  v.replace(r, withText: k.open + ns.substring(with: r) + close)
  v.selectedRange = NSRange(location: r.location + (k.open as NSString).length, length: r.length)
}

struct KeyBar: View {
  let p: Palette
  let press: ((label: String, open: String, close: String?)?) -> Void  // nil hides the keyboard

  var body: some View {
    GlassEffectContainer {
      HStack(spacing: 8) {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(mdKeys, id: \.label) { k in
              Button { press(k) } label: { Text(k.label).font(face(15, .semibold)).frame(minWidth: 22) }
            }
          }
          .padding(.horizontal, 10).padding(.vertical, 6)
        }
        Button { press(nil) } label: {
          Image(systemName: "keyboard.chevron.compact.down").font(.system(size: 15, weight: .semibold))
        }
        .padding(.trailing, 10)
      }
      .buttonStyle(.glass).foregroundStyle(p.ink)
    }
    .frame(height: 52)
  }
}

struct PhoneSettings: View {
  @Environment(Store.self) var store
  @Environment(\.dismiss) var dismiss
  static let families = UIFont.familyNames.sorted()

  var body: some View {
    @Bindable var store = store
    let styles = fontStyles(store.fontFamily).map(\.style)
    NavigationStack {
      Form {
        Section("Theme") {
          Picker("Theme", selection: Binding(get: { store.theme }, set: { store.setTheme($0) })) {
            ForEach(Palette.themes, id: \.name) { Text($0.name).tag($0.name) }
          }
        }
        Section("Text") {
          Picker("Font", selection: $store.fontFamily) {
            ForEach(Self.families, id: \.self) { Text($0).tag($0) }
          }
          if styles.count > 1 {
            Picker("Style", selection: $store.fontStyle) {
              ForEach(styles, id: \.self) { Text($0).tag($0) }
            }
            Picker("Bold", selection: $store.boldStyle) {
              ForEach(styles, id: \.self) { Text($0).tag($0) }
            }
          }
          Stepper("Size \(Int(store.fontSize)) pt", value: $store.fontSize, in: 11...24)
          Picker("Math font", selection: $store.mathFont) {
            ForEach(mathFaces, id: \.name) { Text($0.name).tag($0.name) }
          }
          LabeledContent("Line spacing") {
            Slider(value: $store.lineSpacing, in: 0...0.5, step: 0.02)
          }
        }
        Section("Cards") {
          Toggle("Liquid Glass", isOn: $store.cardsGlass)
          if store.cardsGlass {
            LabeledContent("Glass colour") { Slider(value: $store.glassTint, in: 0...1) }
          }
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
    .preferredColorScheme(store.light ? .light : .dark)
    .tint(store.p.accent)
  }
}

func uiFont(_ size: CGFloat = 15) -> UIFont {
  let size = size * fontScale
  return regularFace.flatMap { UIFont(name: $0, size: size) } ?? UIFont(name: fontName, size: size)
    ?? .monospacedSystemFont(ofSize: size, weight: .regular)
}

/// The capture names come from TreeSitterMarkdownQueries' highlights.scm.
final class MarkdownTheme: Runestone.Theme {
  let p: Palette
  init(_ p: Palette) { self.p = p }

  var font: UIFont { uiFont() }
  var textColor: UIColor { UIColor(p.ink) }
  var gutterBackgroundColor: UIColor { .clear }
  var gutterHairlineColor: UIColor { .clear }
  var lineNumberColor: UIColor { UIColor(p.inkSoft) }
  var lineNumberFont: UIFont { uiFont(12) }
  var selectedLineBackgroundColor: UIColor { .clear }
  var selectedLinesLineNumberColor: UIColor { UIColor(p.ink) }
  var selectedLinesGutterBackgroundColor: UIColor { .clear }
  var invisibleCharactersColor: UIColor { UIColor(p.line) }
  var pageGuideHairlineColor: UIColor { .clear }
  var pageGuideBackgroundColor: UIColor { .clear }
  var markedTextBackgroundColor: UIColor { UIColor(p.sunk) }

  func textColor(for name: String) -> UIColor? {
    switch name {
    case "text.title", "text.uri", "text.reference": UIColor(p.accent)
    case "punctuation.special": UIColor(p.amber)  // heading and list markers
    case "punctuation.delimiter", "string.escape": UIColor(p.inkSoft)
    case "text.literal": UIColor(p.teal)  // code
    default: nil
    }
  }

  func fontTraits(for name: String) -> FontTraits {
    switch name {
    case "text.title", "text.strong": .bold
    case "text.emphasis": .italic
    default: []
    }
  }
}
#endif
