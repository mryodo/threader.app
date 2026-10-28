// The thread list, ported from threader/mac without the editor.
import SwiftUI

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

extension Store {
  func toggleTheme() {
    setTheme(Palette.themes.first { $0.name == theme }?.pair ?? "sw1comm")
  }

  /// Creates an empty thread and selects it. (Threader opens the editor here.)
  func newThread(_ title: String) {
    let s = slug(title)
    guard !s.isEmpty else { return }
    let path = dir.appendingPathComponent(s + ".md")
    if !FileManager.default.fileExists(atPath: path.path) {
      guard write("# \(title)\n", to: path) else { return }
    }
    reload()
    unfolded.insert(path)
    sel = Pos(path: path, note: -1)
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
        Text(t.title).font(display(18)).foregroundStyle(p.cardTitle ?? c.ink)
        if !t.card.isEmpty { MarkdownView(text: t.card, p: c) }
        if !t.notes.isEmpty && store.query.isEmpty {
          Button(open ? "Fold" : "Show \(plural(t.notes.count, "post"))") {
            store.unfolded.formSymmetricDifference([t.path])
          }.buttonStyle(Pill(p: c))
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
        NoteRow(t: t, j: j, last: j == notes.last)
      }
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

/// Note j of t on the timeline.
struct NoteRow: View {
  @Environment(Store.self) var store
  let t: Thread
  let j: Int
  let last: Bool

  var body: some View {
    let p = store.p
    let at = Pos(path: t.path, note: j)
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
        Caps(text: prettyTS(t.notes[j].timestamp), color: on ? p.accent : p.inkSoft)
        MarkdownView(text: t.notes[j].body, p: p)
      }
      .padding(.horizontal, 14).padding(.vertical, 10)
      // the selected post sits on a soft accent panel
      .background(RoundedRectangle(cornerRadius: 16).fill(on ? p.accent.opacity(0.08) : .clear))
      .animation(.easeOut(duration: 0.12), value: on)
      .contentShape(Rectangle())
      .onTapGesture { store.sel = at }
      .contextMenu {
        Button("Delete Post", role: .destructive) { store.deleteNote(at) }
      }
      .padding(.top, 12)
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.leading, 26).padding(.trailing, 4)
    .id(at)
  }
}