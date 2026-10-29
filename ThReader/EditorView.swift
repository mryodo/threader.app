// The editor: an NSTextView that only displays, with every key run through
// Vim. Esc in normal mode saves and closes, as in the terminal app.
import SwiftUI
#if os(macOS)
import AppKit

struct Editor: View {
  @Environment(Store.self) var store
  var pal: Palette? = nil
  @State var vim: Vim?

  var body: some View {
    let p = pal ?? store.p
    VStack(alignment: .leading, spacing: 10) {
      if let vim {
        VimText(vim: vim, p: p)
          .padding(12)
          .background(RoundedRectangle(cornerRadius: 14).fill(p.sunk))
        if let pre = vim.prefix, case let cs = store.completions(pre), !cs.isEmpty {
          CompletionRow(cs: cs, sel: min(vim.compSel, cs.count - 1), p: p)
        }
        HStack(spacing: 10) {
          Text(vim.mode).font(face(11, .bold)).tracking(1.2)
            .foregroundStyle(p.onButton)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(badge(vim.mode, p)))
          Text(vim.status).font(face(12)).foregroundStyle(
            vim.msg.isEmpty && vim.cmd == nil ? p.inkSoft : p.ink
          ).lineLimit(1)
          Spacer()
          Button("Discard") { store.discard() }.buttonStyle(Pill(p: p))
          Button("Save") { store.commit() }.buttonStyle(Pill(p: p, primary: true))
        }
      }
    }
    .onAppear { vim = Vim(store.draft, insert: store.insertStart) }
  }

  func badge(_ mode: String, _ p: Palette) -> Color {
    switch mode {
    case "INSERT": p.teal
    case "VISUAL", "V-LINE": p.amber
    case "COMMAND", "SEARCH": p.red
    default: p.button
    }
  }
}

struct VimText: NSViewRepresentable {
  let vim: Vim
  let p: Palette
  @Environment(Store.self) var store

  func makeNSView(context: Context) -> VimTextView {
    let v = VimTextView()
    v.vim = vim
    v.isRichText = false
    v.allowsUndo = false
    v.drawsBackground = false
    v.isAutomaticQuoteSubstitutionEnabled = false
    v.isAutomaticDashSubstitutionEnabled = false
    v.isAutomaticSpellingCorrectionEnabled = false
    v.isAutomaticTextReplacementEnabled = false
    v.textContainerInset = .zero
    v.textContainer?.lineFragmentPadding = 0
    v.textContainer?.widthTracksTextView = true
    v.isVerticallyResizable = false  // SwiftUI sizes it (sizeThatFits)
    v.delegate = context.coordinator
    v.completions = { store.completions($0) }
    v.act = { act in
      store.draft = vim.value
      switch act {
      case .stay: break
      case .write: store.write()
      case .save: store.commit()
      case .discard: store.discard()
      }
    }
    DispatchQueue.main.async {
      v.window?.makeFirstResponder(v)
      v.sync()
    }
    return v
  }

  func updateNSView(_ v: VimTextView, context: Context) {
    let f = nsFont()
    // Only on a theme or font change: setting these wipes the highlighting.
    let themeChanged = v.pal.map { "\($0.ink) \($0.accent)" } != "\(p.ink) \(p.accent)"
    if f != v.lastFont || themeChanged {
      v.font = f
      v.defaultParagraphStyle = linePara()
      v.textColor = NSColor(p.ink)
      v.pal = p
      v.lastFont = f
      v.highlight()
    }
    v.insertionPointColor = NSColor(p.accent)
    v.selectedTextAttributes = [
      .backgroundColor: NSColor(p.accent).withAlphaComponent(0.35),
      .foregroundColor: NSColor(p.ink),
    ]
    v.sync()
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView v: VimTextView, context: Context)
    -> CGSize?
  {
    // Measured apart from the view: SwiftUI probes with widths like 0,
    // and squeezing the view's own text container to them blanks it.
    guard let w = proposal.width, w > 0 else { return nil }
    let s = v.string.hasSuffix("\n") || v.string.isEmpty ? v.string + " " : v.string
    let h = (s as NSString).boundingRect(
      with: NSSize(width: w, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: v.lastFont ?? nsFont(), .paragraphStyle: linePara()]
    ).height
    return CGSize(width: w, height: max(120, ceil(h) + 4))
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  /// Coordinator lets clicks move the cursor, and drags start visual mode.
  final class Coordinator: NSObject, NSTextViewDelegate {
    func textViewDidChangeSelection(_ n: Notification) {
      guard let v = n.object as? VimTextView, !v.syncing, let vim = v.vim, vim.cmd == nil else {
        return
      }
      let r = v.selectedRange()
      let a = v.charIndex(r.location)
      let b = v.charIndex(r.location + r.length)
      if b > a + 1 && !vim.insert {
        vim.visual = "v"
        vim.anchor = a
        vim.cur = b - 1
      } else {
        vim.cur = a
        if !vim.insert {
          vim.visual = nil
          vim.clamp()
        }
      }
    }
  }
}

final class VimTextView: NSTextView {
  var vim: Vim!
  var act: (Act) -> Void = { _ in }
  var completions: (String) -> [Completion] = { texCompletions($0) }
  var syncing = false
  var lastText = ""
  var pal: Palette?
  var lastFont: NSFont?

  override func keyDown(with e: NSEvent) {
    guard let k = key(e) else { return super.keyDown(with: e) }
    // completion: tab inserts the highlighted command, ⌃N ⌃P cycle
    let cs = completions(vim.prefix ?? "")
    if !cs.isEmpty, [.named("tab"), .named("ctrl+n"), .named("ctrl+p")].contains(k) {
      switch k {
      case .named("tab"): vim.complete(cs[min(vim.compSel, cs.count - 1)])  // not recorded, so "." won't repeat it
      case .named("ctrl+n"): vim.compSel = (vim.compSel + 1) % cs.count
      default: vim.compSel = (vim.compSel + cs.count - 1) % cs.count
      }
    } else {
      let a = vim.key(k)
      if a != .stay {
        sync()
        act(a)
        return
      }
    }
    let p = vim.linkPrefix().map { "[[" + $0 } ?? vim.texPrefix()
    if p != vim.prefix {
      vim.prefix = p
      vim.compSel = 0
    }
    sync()
    act(.stay)
  }

  override func performKeyEquivalent(with e: NSEvent) -> Bool {
    guard window?.firstResponder === self else { return super.performKeyEquivalent(with: e) }
    if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers == "s" {  // write like :w, back in normal mode
      if vim.insert { _ = vim.key(.named("esc")) }
      vim.orig = vim.value
      sync()
      act(.write)
      return true
    }
    return super.performKeyEquivalent(with: e)
  }

  override func paste(_ sender: Any?) {
    guard let s = NSPasteboard.general.string(forType: .string) else { return }
    vim.pasteText(s)
    sync()
    act(.stay)
  }

  /// key names a keypress the way the terminal app's editor reads them.
  func key(_ e: NSEvent) -> Key? {
    let named: [UInt16: String] = [
      53: "esc", 36: "enter", 76: "enter", 48: "tab", 51: "backspace", 117: "delete",
      123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end",
    ]
    if let n = named[e.keyCode] { return .named(n) }
    if e.modifierFlags.contains(.command) { return nil }
    if e.modifierFlags.contains(.control), let c = e.charactersIgnoringModifiers?.lowercased() {
      return c == "[" ? .named("esc") : .named("ctrl+" + c)
    }
    // Keys go straight to vim, so dead keys and input methods (IME) don't
    // work. Fixing that means routing insert mode through
    // interpretKeyEvents(_:) and NSTextInputClient.
    guard let t = e.characters, !t.isEmpty,
      t.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 })
    else { return nil }
    return .text(t)
  }

  /// Shows vim's buffer: a caret in insert mode, a one-character
  /// selection as the normal-mode block, the selection in visual mode.
  func sync() {
    guard let vim else { return }
    syncing = true
    defer { syncing = false }
    let s = vim.value
    if s != lastText {
      string = s
      lastText = s
      highlight()
      invalidateIntrinsicContentSize()
    }
    var a = vim.cur
    var b = vim.cur
    if let v = vim.visual {
      a = min(vim.anchor, vim.cur)
      b = max(vim.anchor, vim.cur) + 1
      if v == "V" {
        a = vim.lineStart(a)
        b = min(vim.lineEnd(b - 1) + 1, vim.text.count)
      }
    } else if !vim.insert && vim.cur < vim.text.count && vim.text[vim.cur] != "\n" {
      b = vim.cur + 1
    }
    b = min(b, vim.text.count)
    let r = NSRange(location: u16(a), length: u16(b) - u16(a))
    setSelectedRange(r)
    scrollRangeToVisible(r)
  }

  /// Styles the markdown as it's typed: headings, **bold**, *italic*,
  /// ~~strike~~, `code`, links, #tags, $math$, lists, quotes and fenced
  /// code, with the markers dimmed. Font sizes never change, so lines
  /// don't jump around. The whole post is restyled on every keystroke,
  /// which is fast enough at post length.
  func highlight() {
    guard let ts = textStorage, let p = pal else { return }
    let all = NSRange(location: 0, length: ts.length)
    let s = ts.string
    let base = nsFont()
    let fm = NSFontManager.shared
    let bold =
      boldFace.flatMap { NSFont(name: $0, size: base.pointSize) }
      ?? fm.convert(base, toHaveTrait: .boldFontMask)
    let italic = fm.convert(base, toHaveTrait: .italicFontMask)
    let dim = NSColor(p.inkSoft)
    let accent = NSColor(p.accent)
    func paint(
      _ re: NSRegularExpression, _ attrs: [NSAttributedString.Key: Any], markers: [Int] = []
    ) {
      for m in re.matches(in: s, range: all) {
        ts.addAttributes(attrs, range: m.range)
        for g in markers where m.range(at: g).location != NSNotFound {
          ts.addAttribute(.foregroundColor, value: dim, range: m.range(at: g))
        }
      }
    }
    ts.beginEditing()
    ts.setAttributes([.font: base, .foregroundColor: NSColor(p.ink)], range: all)
    for m in mdList.matches(in: s, range: all) {
      ts.addAttribute(.foregroundColor, value: NSColor(p.amber), range: m.range(at: 1))
    }
    paint(mdQuote, [.foregroundColor: dim, .font: italic])
    paint(mdHeading, [.font: bold, .foregroundColor: accent], markers: [1])
    paint(mdBold, [.font: bold], markers: [1, 3, 4])
    paint(mdItalic, [.font: italic], markers: [1, 3])
    paint(mdStrike, [.strikethroughStyle: NSUnderlineStyle.single.rawValue], markers: [1, 3])
    paint(
      mdLink, [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue],
      markers: [1, 2])
    paint(linkRe, [.foregroundColor: accent])
    paint(mdURL, [.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue])
    for m in tagRe.matches(in: s, range: all) {
      ts.addAttributes([.foregroundColor: accent, .font: bold], range: m.range(at: 2))
    }
    paint(mdMath, [.foregroundColor: NSColor(p.amber)])
    paint(mdCode, [.foregroundColor: NSColor(p.teal), .font: base], markers: [1, 3])
    for m in mdFence.matches(in: s, range: all) {  // coloured as in the preview, fence lines dimmed
      ts.setAttributes([.font: base, .foregroundColor: NSColor(p.ink)], range: m.range)
      for st in codeStyles((s as NSString).substring(with: m.range), p) {
        let r = NSRange(location: m.range.location + st.range.location, length: st.range.length)
        ts.addAttributes(
          [.foregroundColor: NSColor(st.color), .font: st.italic ? italic : base], range: r)
      }
      for f in mdFenceLine.matches(in: s, range: m.range) {
        ts.setAttributes([.font: base, .foregroundColor: dim], range: f.range)
      }
    }
    ts.addAttribute(.paragraphStyle, value: linePara(), range: all)
    ts.endEditing()
  }

  // NSTextView counts in UTF-16 units, Vim in Characters. Both conversions
  // walk the buffer from the start, which is fine at post length.

  /// The UTF-16 offset of character `i`.
  func u16(_ i: Int) -> Int {
    vim.text[..<min(i, vim.text.count)].reduce(0) { $0 + $1.utf16.count }
  }

  /// The character index at UTF-16 offset `u`.
  func charIndex(_ u: Int) -> Int {
    var n = 0
    var acc = 0
    while n < vim.text.count && acc < u {
      acc += vim.text[n].utf16.count
      n += 1
    }
    return n
  }
}

#endif

/// Shows the commands matching the \\name, or the threads
/// and posts matching the [[link, being typed.
struct CompletionRow: View {
  let cs: [Completion]
  let sel: Int
  let p: Palette

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        ForEach(Array(cs.enumerated()), id: \.offset) { i, c in
          HStack(spacing: 6) {
            Text(c.link ? c.name : "\\" + c.name + String(repeating: "{}", count: c.args)).font(
              face(12, .semibold))
            Text(c.preview).font(face(12)).opacity(0.75)
            if c.mine { Circle().fill(i == sel ? p.onButton : p.amber).frame(width: 5, height: 5) }
          }
          .foregroundStyle(i == sel ? p.onButton : p.ink)
          .padding(.horizontal, 10).padding(.vertical, 4)
          .background(Capsule().fill(i == sel ? p.button : p.sunk))
        }
        Text("tab inserts · ⌃N ⌃P").font(face(11)).foregroundStyle(p.inkSoft).padding(.leading, 4)
      }
    }
  }
}

let mdHeading = try! NSRegularExpression(pattern: #"^(#{1,6}\s).*$"#, options: .anchorsMatchLines)
let mdList = try! NSRegularExpression(
  pattern: #"^\s*([-*+]|\d+[.)])(?:\s+\[[ xX]\])?\s"#, options: .anchorsMatchLines)
let mdQuote = try! NSRegularExpression(pattern: #"^\s*>.*$"#, options: .anchorsMatchLines)
// closed, or still being typed: bold to the line's end until it's closed
let mdBold = try! NSRegularExpression(
  pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)(\1)|(\*\*|__)(?=\S)(?!.*\4)(.*)$"#,
  options: .anchorsMatchLines)
let mdItalic = try! NSRegularExpression(
  pattern: #"(?<![*\w])(\*|_)(?=[^\s*_])(.+?)(?<=[^\s*_])(\1)(?![*\w])"#)
let mdStrike = try! NSRegularExpression(pattern: #"(~~)(?=\S)(.+?)(?<=\S)(~~)"#)
let mdLink = try! NSRegularExpression(pattern: #"!?\[[^\]\n]*(\])(\([^)\n]*\))"#)
let mdURL = try! NSRegularExpression(pattern: #"(?<![(<])\bhttps?://[^\s)>]+"#)
let mdMath = try! NSRegularExpression(pattern: #"(?s)\$\$.+?\$\$|\$[^$\s](?:[^$\n]*[^$\s])?\$"#)
let mdCode = try! NSRegularExpression(pattern: #"(`)([^`\n]+)(`)"#)
let mdFenceLine = try! NSRegularExpression(pattern: #"^\s*```.*$"#, options: .anchorsMatchLines)
let mdFence = try! NSRegularExpression(
  pattern: #"(?ms)^\s*```.*?^\s*```[ \t]*$|^\s*```(?:(?!^\s*```).)*\z"#)  // an unclosed fence runs to the end

// One regex for every language rather than a grammar per language: it finds
// comments, strings, numbers and words, and the words in codeKeywords are
// coloured. Good enough for snippets in notes.
let codeRe = try! NSRegularExpression(
  pattern:
    #"(//[^\n]*|/\*[\s\S]*?\*/|#=[\s\S]*?=#|(?:^|(?<=\s))(?:#|--|%)[^\n]*)|("""[\s\S]*?"""|"(?:\\.|[^"\\\n])*"|(?<![\w)\]}'])'(?:\\.|[^'\\\n])*'|`[^`\n]*`)|(\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)\b)|(@?[A-Za-z_]\w*!?)"#,
  options: .anchorsMatchLines)

let codeKeywords: Set<String> = [
  "and", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "def",
  "default", "defer", "do", "elif",
  "else", "end", "enum", "except", "export", "extends", "extension", "false", "finally", "fn",
  "for", "from", "func", "function",
  "go", "guard", "if", "impl", "import", "in", "interface", "is", "let", "local", "loop", "match",
  "mod", "module", "mut", "new",
  "nil", "none", "None", "not", "null", "or", "package", "private", "protocol", "pub", "public",
  "raise", "return", "self", "Self",
  "static", "struct", "super", "switch", "then", "this", "throw", "throws", "trait", "true", "True",
  "False", "try", "type",
  "typedef", "use", "var", "void", "where", "while", "with", "yield", "lambda", "select", "range",
  "chan", "map", "begin",
  "using", "elseif", "mutable", "macro", "quote", "abstract", "primitive", "global", "nothing",
  "missing", "baremodule",  // Julia
]

/// codeStyles colours code: comments, strings, numbers, keywords; the
/// preview and the editor both paint with it.
func codeStyles(_ code: String, _ p: Palette) -> [(range: NSRange, color: Color, italic: Bool)] {
  let ns = code as NSString
  return codeRe.matches(in: code, range: NSRange(location: 0, length: ns.length)).compactMap { m in
    switch (1...4).first(where: { m.range(at: $0).location != NSNotFound }) {
    case 1: (m.range, p.inkSoft, true)
    case 2: (m.range, p.teal, false)
    case 3: (m.range, p.amber, false)
    default:
      codeKeywords.contains(ns.substring(with: m.range))
        || ns.substring(with: m.range).hasPrefix("@") ? (m.range, p.accent, false) : nil  // @macros too
    }
  }
}

/// A link is [[thread]], or [[thread#n]] for its nth post. The thread is
/// named by its title or its file name.
let linkRe = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#)
