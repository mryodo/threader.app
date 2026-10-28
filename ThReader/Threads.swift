// The thread list, ported from threader/mac without the editor.
import SwiftUI
import Textual

func slug(_ s: String) -> String {
  s.lowercased()
    .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

/// A tag is #word after a space or at the start of a line, so headings
/// ("# x"), numbers (#1) and anchors (page#x) aren't tags.
let tagRe = try! NSRegularExpression(pattern: #"(?m)(^|\s)(#[\p{L}_][\p{L}\p{N}_/-]*)"#)

/// The lowercased tags in a post, ignoring fenced code.
func tagsIn(_ text: String) -> Set<String> {
  var fence = false
  let s = text.components(separatedBy: "\n").filter { line in
    let t = line.trimmingCharacters(in: .whitespaces)
    if t.hasPrefix("```") || t.hasPrefix("~~~") {
      fence.toggle()
      return false
    }
    return !fence
  }.joined(separator: "\n")
  var tags = Set<String>()
  for m in tagRe.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
    tags.insert(String(s[Range(m.range(at: 2), in: s)!]).lowercased())
  }
  return tags
}

let linkifyRe = try! Regex(#"(`[^`\n]*`)|\[\[([^\[\]\n]+)\]\]|(^|\s)(#[\p{L}_][\p{L}\p{N}_/-]*)"#)

/// Turns [[links]] and #tags outside code into threader-link: and
/// threader-tag: markdown links, which ContentView's openURL follows.
func linkify(_ md: String) -> String {
  var fence = false
  return md.components(separatedBy: "\n").map { line in
    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
      fence.toggle()
      return line
    }
    if fence { return line }
    return line.replacing(linkifyRe) { m in
      let enc = { (s: Substring) in s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "" }
      if let link = m.output[2].substring {
        return "[↗\u{a0}\(link)](threader-link:\(enc(link)))"
      }
      if let tag = m.output[4].substring {
        return "\(m.output[3].substring ?? "")[\(tag)](threader-tag:\(enc(tag.dropFirst())))"
      }
      return String(m.output[0].substring ?? "")  // inline code, untouched
    }
  }.joined(separator: "\n")
}

extension Store {
  func toggleTheme() {
    setTheme(Palette.themes.first { $0.name == theme }?.pair ?? "sw1comm")
  }

  /// Creates a thread and opens its card in the editor.
  func newThread(_ title: String) {
    let s = slug(title)
    guard !s.isEmpty else { return }
    let path = dir.appendingPathComponent(s + ".md")
    if !FileManager.default.fileExists(atPath: path.path) {
      guard write("# \(title)\n", to: path) else { return }
    }
    reload()
    unfolded.insert(path)
    edit(Pos(path: path, note: -1), insert: true)
  }

  func edit(_ p: Pos, insert: Bool = false) {
    guard let t = threads.first(where: { $0.path == p.path }) else { return }
    commit()
    sel = p
    editing = p
    insertStart = insert
    draft = p.note < 0 ? "# \(t.title)\n\n\(t.card)" : t.notes[p.note].body
    draftOrig = draft
  }

  func addNote(_ path: URL) {
    commit()
    unfolded.insert(path)
    adding = path
    insertStart = true
    draft = ""
  }

  /// Resolves \usepackage{name} to name.sty in the threads folder.
  func loadPackage(_ name: String) -> String? {
    guard !name.contains("/") else { return nil }
    return read(root.appendingPathComponent(name + ".sty"))
  }

  func savePreamble(_ s: String) {
    guard write(s, to: root.appendingPathComponent(Store.preambleFile)) else { return }
    preamble = s
    texMacros = parseMacros(s, load: loadPackage)
    preambleVersion += 1
  }

  /// Completions for what's being typed in the editor: threads for a
  /// `[[link`, that thread's posts after `[[link#`, LaTeX commands for `\name`.
  func completions(_ prefix: String, limit: Int = 8) -> [Completion] {
    guard prefix.hasPrefix("[[") else { return texCompletions(prefix, limit: limit) }
    let q = String(prefix.dropFirst(2))

    if let hash = q.lastIndex(of: "#"),
      let t = threads.first(where: { slug($0.title) == slug(String(q[..<hash])) })
    {
      let n = q[q.index(after: hash)...]
      return t.notes.indices.filter { String($0 + 1).hasPrefix(n) }.map { j in
        let firstLine = t.notes[j].body.split(separator: "\n").first.map(String.init) ?? ""
        return Completion(
          name: "\(t.title)#\(j + 1)", args: 0, preview: String(firstLine.prefix(40)), mine: false,
          link: true)
      }
    }

    let hits = threads.filter { q.isEmpty || $0.title.range(of: q, options: .caseInsensitive) != nil }
    return hits.prefix(limit).map {
      Completion(
        name: $0.title, args: 0, preview: plural($0.notes.count, "post"), mine: $0.pinned,
        link: true)
    }
  }

  /// Selects what a [[link]] points at, unfolding its thread.
  func follow(_ target: String) {
    var name = target
    var n = 0
    if let hash = target.lastIndex(of: "#"),
      let k = Int(target[target.index(after: hash)...].trimmingCharacters(in: .whitespaces))
    {
      name = String(target[..<hash])
      n = k
    }
    let s = slug(name)
    guard
      let t = threads.first(where: {
        slug($0.title) == s || $0.path.deletingPathExtension().lastPathComponent == s
      })
    else {
      error = "no thread \(name)"
      return
    }
    guard n <= t.notes.count else {
      error = "\(t.title) has no post \(n)"
      return
    }
    query = ""
    unfolded.insert(t.path)
    sel = Pos(path: t.path, note: max(n - 1, -1))
  }

  /// Saves the open editor and keeps it open (⌘S).
  func write() {
    let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty && adding != nil { return }  // nothing to save yet
    let wasEditing = editing, wasAdding = adding != nil, text = draft
    commit()
    // commit selected the new note; an emptied note was deleted, so there's nothing to reopen
    guard !value.isEmpty, let reopen = wasAdding ? sel : wasEditing else { return }
    editing = reopen
    draft = text
    draftOrig = text
    insertStart = false
  }

  /// Saves and closes the open editor. An emptied note is deleted, and an
  /// empty new note is dropped.
  func commit() {
    let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    defer { discard() }
    if editing != nil && draft == draftOrig { return }

    if let path = adding {
      guard !value.isEmpty else { return }
      let f = DateFormatter()
      f.dateFormat = stampFormat
      var index = 0
      change(path) {
        $0.notes.append(Note(timestamp: f.string(from: Date()), body: value))
        index = $0.notes.count - 1
      }
      sel = Pos(path: path, note: index)
    } else if let p = editing {
      change(p.path) { t in
        if p.note < 0 {
          // the card's first line is its title
          let parts = value.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
          let title = (parts.first ?? "").drop { $0 == "#" }.trimmingCharacters(in: .whitespaces)
          if !title.isEmpty {
            t.title = title
          }
          t.card = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        } else if p.note < t.notes.count {
          if value.isEmpty {
            t.notes.remove(at: p.note)
          } else {
            t.notes[p.note].body = value
          }
        }
      }
    }
  }

  func discard() {
    editing = nil
    adding = nil
    draft = ""
  }

  /// Rereads the thread at `path`, applies `f` and writes it back,
  /// remembering the old contents for undo.
  func change(_ path: URL, _ f: (inout Thread) -> Void) {
    guard let before = read(path), var t = loadThread(path.path) else {
      error = "can't read \(path.lastPathComponent)"
      return
    }
    f(&t)
    let after = writeThread(t)
    guard after != before else { return }
    if write(after, to: path) {
      undo.append((path, before))
      redo = []
    }
    reload()
  }

  func deleteNote(_ p: Pos) {
    guard p.note >= 0 else {
      error = "only posts can be deleted"
      return
    }
    change(p.path) {
      if p.note < $0.notes.count {
        $0.notes.remove(at: p.note)
      }
    }
    let left = threads.first { $0.path == p.path }?.notes.count ?? 0
    sel = Pos(path: p.path, note: min(p.note, left - 1))
  }

  /// Restores a file to before its last saved change, or with `redoing`
  /// reapplies the last undone change.
  func undoFile(redoing: Bool = false) {
    guard let (path, text) = redoing ? redo.popLast() : undo.popLast() else {
      error = "nothing to " + (redoing ? "redo" : "undo")
      return
    }
    let current = read(path) ?? ""
    guard write(text, to: path) else { return }
    if redoing {
      undo.append((path, current))
    } else {
      redo.append((path, current))
    }
    unfolded.insert(path)
    reload()
  }

  /// Every tag with the number of posts carrying it, most used first.
  func allTags() -> [(String, Int)] {
    var counts: [String: Int] = [:]
    for t in threads {
      for text in [t.card] + t.notes.map(\.body) {
        for tag in tagsIn(text) {
          counts[tag, default: 0] += 1
        }
      }
    }
    let sorted = counts.sorted {
      $0.value > $1.value || $0.value == $1.value && $0.key < $1.key
    }
    return sorted.map { ($0.key, $0.value) }
  }

  /// Whether `text` matches the search. A "#tag" query wants that exact
  /// tag; anything else is a substring search, case-insensitive unless the
  /// query has capitals (vim's smartcase).
  func matches(_ text: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespaces)
    if q.isEmpty { return true }
    if q.hasPrefix("#"), !q.contains(" ") {
      return tagsIn(text).contains(q.lowercased())
    }
    return text.range(of: q, options: q.lowercased() == q ? .caseInsensitive : []) != nil
  }

  /// The threads to draw and, for each, the notes to show: all of them if
  /// it's unfolded, none if folded, and only the matches while searching.
  func shown() -> [(Thread, [Int])] {
    if query.trimmingCharacters(in: .whitespaces).isEmpty {
      return threads.map { ($0, unfolded.contains($0.path) ? Array($0.notes.indices) : []) }
    }
    return threads.compactMap { t in
      let hits = t.notes.indices.filter { matches(t.notes[$0].body) }
      return matches(t.title) || matches(t.card) || !hits.isEmpty ? (t, hits) : nil
    }
  }

  /// Every selectable position, in the order they're drawn.
  func items() -> [Pos] {
    shown().flatMap { t, notes in
      [Pos(path: t.path, note: -1)] + notes.map { Pos(path: t.path, note: $0) }
    }
  }

  /// Moves the selection `d` items down (or up, if negative).
  func step(_ d: Int) {
    let all = items()
    guard !all.isEmpty else { return }
    let k = sel.flatMap { all.firstIndex(of: $0) } ?? (d > 0 ? -1 : all.count)
    sel = all[max(0, min(all.count - 1, k + d))]
  }
}

/// A thread's card and, unfolded, its notes hanging from a timeline.
struct ThreadView: View {
  @Environment(Store.self) var store
  let t: Thread
  let notes: [Int]

  var body: some View {
    let p = store.p
    let card = Pos(path: t.path, note: -1)
    let open = store.unfolded.contains(t.path) || !store.query.isEmpty
    let adding = store.adding == t.path
    let c = p.onCard
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Caps(text: "\(plural(t.notes.count, "post")) · \(ago(t.mtime))", color: c.inkSoft)
          Spacer()
          Button {
            store.togglePin(t.path)
          } label: {
            if t.pinned {  // a solid badge: the accent alone vanishes on some cards
              Label("Pinned", systemImage: "pin.fill").font(face(11, .bold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .foregroundStyle(c.onButton).background(Capsule().fill(c.button))
            } else {
              Image(systemName: "pin").foregroundStyle(c.inkSoft)
            }
          }
          .buttonStyle(.plain)
          .help(t.pinned ? "Unpin (P)" : "Pin to top (P)")
          moveMenu
        }
        if store.editing == card {
          Editor(pal: c)
        } else {
          Text(t.title).font(display(18)).foregroundStyle(p.cardTitle ?? c.ink)
          if !t.card.isEmpty {
            MarkdownView(text: t.card, p: c, dir: t.path.deletingLastPathComponent()) { l in
              store.change(t.path) { $0.card = toggleTask($0.card, l) }
            }
          }
        }
        HStack(spacing: 8) {
          if !t.notes.isEmpty && store.query.isEmpty {
            Button(open ? "Fold" : "Show \(plural(t.notes.count, "post"))") {
              store.unfolded.formSymmetricDifference([t.path])
            }.buttonStyle(Pill(p: c))
          }
          if store.editing != card {
            Button("Edit") { store.edit(card) }.buttonStyle(Pill(p: c))
            Button("Post") { store.addNote(t.path) }.buttonStyle(Pill(p: c, primary: true))
          }
        }
      }
      .padding(22)
      .modifier(
        Raised(p: c, selected: store.sel == card, alpha: store.cardsClear ? store.opacity : 1)
      )
      .contentShape(Rectangle())
      .onTapGesture { store.sel = card }
      .id(card)

      ForEach(open ? notes : [], id: \.self) { j in
        NoteRow(t: t, j: j, last: j == notes.last && !adding)
      }
      if adding { NoteRow(t: t, j: nil, last: true) }
    }
  }

  var moveMenu: some View {
    Menu {
      ForEach(store.workspaces().filter { $0 != store.ws }, id: \.self) { w in
        Button(store.wsName(w)) { store.move(t.path, to: w) }
      }
      Divider()
      Button("New workspace…") { store.ask = .workspace(moving: t.path) }
    } label: {
      Image(systemName: "arrow.left.arrow.right")
    }
    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    .foregroundStyle(store.p.onCard.inkSoft)
    .tint(store.p.onCard.inkSoft)  // the borderless menu draws in the tint
    .help("Move to workspace")
  }
}

/// Note j of t on the timeline, or with j nil the new note being written.
struct NoteRow: View {
  @Environment(Store.self) var store
  let t: Thread
  let j: Int?
  let last: Bool

  var body: some View {
    let p = store.p
    let at = Pos(path: t.path, note: j ?? -2)
    let on = store.sel == at
    HStack(alignment: .top, spacing: 14) {
      ZStack(alignment: .top) {
        Rectangle().fill(p.line).frame(width: 2).frame(
          maxHeight: last ? 30 : .infinity, alignment: .top)
        Circle().fill(on ? p.red : p.amber).frame(width: on ? 15 : 11, height: on ? 15 : 11)
          .overlay(Circle().strokeBorder(p.paper, lineWidth: 2)).padding(.top, on ? 22 : 24)
      }
      .frame(width: 22)
      VStack(alignment: .leading, spacing: 10) {
        if let j {
          Caps(text: prettyTS(t.notes[j].timestamp), color: on ? p.accent : p.inkSoft)
          if store.editing == at {
            Editor()
          } else {
            MarkdownView(text: t.notes[j].body, p: p, dir: t.path.deletingLastPathComponent()) { l in
              store.change(t.path) { $0.notes[j].body = toggleTask($0.notes[j].body, l) }
            }
          }
        } else {
          Caps(text: "New post", color: p.accent)
          Editor()
        }
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      // the selected post sits on a soft accent panel
      .background(RoundedRectangle(cornerRadius: 16).fill(on ? p.accent.opacity(0.08) : .clear))
      .animation(.easeOut(duration: 0.12), value: on)
      .contentShape(Rectangle())
      .onTapGesture(count: 2) { if j != nil { store.edit(at) } }
      .onTapGesture { if j != nil { store.sel = at } }
      .contextMenu {
        if j != nil {
          Button("Edit") { store.edit(at) }
          Button("Delete Post", role: .destructive) { store.deleteNote(at) }
        }
      }
      .padding(.top, 12)
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.leading, 26).padding(.trailing, 4)
    .id(at)
  }
}

let taskRe = try! Regex(#"^(\s*)[-*+]\s+\[([ xX])\]\s+(.*)$"#)

let imageRe = try! Regex(#"^\s*!\[([^\]]*)\]\(<?([^)\s>]+)>?(?:\s+"[^"]*")?\)\s*$"#)

enum Row { case text, task, image(alt: String, src: String) }

/// Splits markdown into runs of ordinary lines, single task lines (`- [ ] x`)
/// and images on a line of their own, leaving fenced code alone, so tasks
/// and images can be drawn as in threader.
func splitRows(_ md: String) -> [(text: String, kind: Row)] {
  var out: [(text: String, kind: Row)] = []
  var run: [String] = []
  var fence = false
  func flush() {
    if !run.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      out.append((run.joined(separator: "\n"), .text))
    }
    run = []
  }
  for line in md.components(separatedBy: "\n") {
    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fence.toggle() }
    if !fence, line.wholeMatch(of: taskRe) != nil {
      flush()
      out.append((line, .task))
    } else if !fence, let m = line.wholeMatch(of: imageRe) {
      flush()
      out.append((line, .image(alt: String(m.output[1].substring!), src: String(m.output[2].substring!))))
    } else {
      run.append(line)
    }
  }
  flush()
  return out
}

/// Ends every line that has text after it with a markdown hard break, so
/// lines show as typed, one under another, as in threader.
func hardBreaks(_ md: String) -> String {
  var fence = false
  let lines = md.components(separatedBy: "\n")
  return lines.enumerated().map { i, line in
    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fence.toggle() }
    let next = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
    let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
    return fence || blank || next.isEmpty || next.hasPrefix("```") ? line : line + "  "
  }.joined(separator: "\n")
}

/// An image on its own line, as threader draws it: local paths are relative
/// to the thread's folder, corners rounded, at most 420pt tall.
struct ImageRow: View {
  let alt: String
  let src: String
  let dir: URL?
  let p: Palette

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 14)
    if src.hasPrefix("http://") || src.hasPrefix("https://"), let u = URL(string: src) {
      AsyncImage(url: u) { $0.resizable().scaledToFit().clipShape(shape) } placeholder: {
        ProgressView()
      }
      .frame(maxWidth: .infinity, maxHeight: 420, alignment: .leading)
    } else if let img = NSImage(contentsOf: resolve()) {
      Image(nsImage: img).resizable().scaledToFit().clipShape(shape)
        .frame(maxWidth: min(img.size.width, .infinity), maxHeight: 420, alignment: .leading)
    } else {
      Caps(text: "image not found · \(alt.isEmpty ? src : alt)", color: p.red)
    }
  }

  /// Finds src on disk relative to the thread's folder.
  func resolve() -> URL {
    if src.hasPrefix("file://"), let u = URL(string: src) { return u }
    let s = (src as NSString).expandingTildeInPath
    if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
    return (dir ?? URL(fileURLWithPath: NSHomeDirectory())).appendingPathComponent(s)
  }
}

/// s with the task line l, as drawn (a callout's "> " gone), ticked or unticked.
func toggleTask(_ s: String, _ l: String) -> String {
  var lines = s.components(separatedBy: "\n")
  // ponytail: the first line that matches, so of two identical tasks the first ticks
  guard
    let i = lines.firstIndex(where: {
      $0.hasSuffix(l)
        && String($0.dropLast(l.count)).range(of: #"^(\s*>\s?)*$"#, options: .regularExpression)
          != nil
    }),
    let b = lines[i].firstIndex(of: "[")
  else { return s }
  let m = lines[i].index(after: b)
  lines[i].replaceSubrange(m...m, with: lines[i][m] == " " ? "x" : " ")
  return lines.joined(separator: "\n")
}

/// A task line as threader draws it: a teal circle to tick, the text struck when done.
struct TaskRow: View {
  let line: String
  let p: Palette
  let toggle: ((String) -> Void)?

  var body: some View {
    let m = line.wholeMatch(of: taskRe)!
    let indent = m.output[1].substring?.count ?? 0
    let done = m.output[2].substring != " "
    let text = String(m.output[3].substring ?? "")
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Button {
        toggle?(line)
      } label: {
        Image(systemName: done ? "checkmark.circle.fill" : "circle").font(face())
          .foregroundStyle(p.teal)
      }
      .buttonStyle(.plain).disabled(toggle == nil)
      .pointerStyle(toggle != nil ? .link : nil)
      StructuredText(
        markdown: inlineMath(linkify(done ? "~~\(text)~~" : text)), syntaxExtensions: [.math]
      )
      .threaderMarkdown(p)
    }
    .padding(.leading, CGFloat(indent) * 6)
  }
}
