// The iPhone app: the same cards and timeline, with buttons standing in for
// the keys, and Runestone (the editor from the Runestone app) for writing.
#if os(iOS)
import Runestone
import SwiftUI
import TreeSitterMarkdownInlineRunestone
import TreeSitterMarkdownRunestone
import UIKit
import UniformTypeIdentifiers

struct PhoneView: View {
  @Environment(Store.self) var store
  @Environment(\.scenePhase) var phase
  @State var pickingFolder = false

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
        .onChange(of: store.sel) {
          if let s = store.sel { withAnimation(.snappy) { proxy.scrollTo(s) } }
        }
      }
      .background(p.paper.ignoresSafeArea())
      .navigationTitle(store.wsName(store.ws))
      .searchable(text: $store.query, prompt: "Search, or #tag")
      .refreshable { store.reload() }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) { workspaces }
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
    .preferredColorScheme(store.light ? .light : .dark)
    .tint(p.accent)
    .onChange(of: phase) { if $1 == .active { store.reload() } }
    // pick the Mac's threads folder in iCloud Drive to share it
    .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) {
      if case .success(let u) = $0 { store.pickRoot(u) }
    }
    .sheet(isPresented: Binding(get: { store.ask != nil }, set: { if !$0 { store.ask = nil } })) {
      NameSheet().presentationDetents([.medium])
    }
    // swiping the editor away saves, as esc does on the Mac
    .sheet(
      isPresented: Binding(
        get: { store.editing != nil || store.adding != nil }, set: { if !$0 { store.commit() } })
    ) { PhoneEditor() }
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

/// In the list the post being edited just shows its draft; the editing
/// happens in PhoneEditor's sheet.
struct Editor: View {
  @Environment(Store.self) var store
  var pal: Palette? = nil

  var body: some View {
    Text(store.draft).font(face()).foregroundStyle((pal ?? store.p).inkSoft)
  }
}

struct PhoneEditor: View {
  @Environment(Store.self) var store

  var body: some View {
    let p = store.p
    NavigationStack {
      MarkdownEditor(text: Bindable(store).draft, p: p)
        .background(p.paper.ignoresSafeArea())
        .navigationTitle(
          store.adding != nil ? "New post" : store.editing?.note == -1 ? "Card" : "Edit post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Discard") { store.discard() }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("Save") { store.commit() }
          }
        }
    }
    .preferredColorScheme(store.light ? .light : .dark)
  }
}

/// Runestone's TextView, with tree-sitter's markdown grammar and the theme's colours.
struct MarkdownEditor: UIViewRepresentable {
  @Binding var text: String
  let p: Palette

  func makeUIView(context: Context) -> TextView {
    let v = TextView()
    v.editorDelegate = context.coordinator
    v.backgroundColor = .clear
    v.isLineWrappingEnabled = true
    v.lineHeightMultiplier = 1 + lineGap
    v.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    v.smartQuotesType = .no  // they'd break code and math
    v.smartDashesType = .no
    v.insertionPointColor = UIColor(p.accent)
    v.selectionBarColor = UIColor(p.accent)
    v.selectionHighlightColor = UIColor(p.accent).withAlphaComponent(0.25)
    v.setState(
      TextViewState(
        text: text, theme: MarkdownTheme(p), language: .markdown,
        languageProvider: context.coordinator))
    DispatchQueue.main.async { _ = v.becomeFirstResponder() }
    return v
  }

  func updateUIView(_ v: TextView, context: Context) {}  // text only flows out of the view

  func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

  final class Coordinator: TextViewDelegate, TreeSitterLanguageProvider {
    let text: Binding<String>
    init(text: Binding<String>) { self.text = text }

    func textViewDidChange(_ v: TextView) { text.wrappedValue = v.text }

    // the block grammar hands paragraphs and headings to the inline one
    func treeSitterLanguage(named name: String) -> TreeSitterLanguage? {
      name == "markdown_inline" ? .markdownInline : nil
    }
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
