import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation

enum Key: Equatable {
  case named(String)
  case text(String)
  var s: String {
    switch self {
    case .named(let n): n
    case .text(let t): t
    }
  }
}

enum Act { case stay, write, save, discard }  // after a key: nothing, :w, :wq, :q!

@Observable final class Vim {
  @ObservationIgnored var text: [Character]
  @ObservationIgnored var cur = 0
  var insert: Bool
  var count = 0
  var pending = ""  // operator (d c y) and/or prefix (g r) awaiting more keys
  var cmd: String?  // the : or / command line being typed
  var cmdKind: Character = ":"
  var msg = ""
  var visual: Character?  // "v" charwise or "V" linewise
  var prefix: String?  // the \\name, or [[ and a link, being typed in insert mode, for completion
  var compSel = 0  // the highlighted completion
  @ObservationIgnored var anchor = 0
  @ObservationIgnored var reg: [Character] = []
  @ObservationIgnored var regLine = false
  @ObservationIgnored var undo: [([Character], Int)] = []
  @ObservationIgnored var redo: [([Character], Int)] = []
  @ObservationIgnored var rec: [Key] = []
  @ObservationIgnored var last: [Key] = []
  @ObservationIgnored var recUndo = 0
  @ObservationIgnored var search = ""
  @ObservationIgnored var searchBk = false
  @ObservationIgnored var orig: String

  init(_ s: String, insert: Bool) {
    text = Array(s.replacingOccurrences(of: "\r\n", with: "\n"))
    self.insert = insert
    orig = s
    if insert { cur = text.count }
  }

  var value: String { String(text) }

  /// The index of the first character on i's line.
  func lineStart(_ i: Int) -> Int {
    var i = i
    while i > 0 && text[i - 1] != "\n" { i -= 1 }
    return i
  }

  func lineEnd(_ i: Int) -> Int {
    var i = i
    while i < text.count && text[i] != "\n" { i += 1 }
    return i
  }

  func clamp() {
    cur = max(0, min(cur, text.count))
    if !insert && cur == lineEnd(cur) && cur > lineStart(cur) { cur -= 1 }
  }

  func lineDown(_ i: Int, _ n: Int) -> Int {
    var start = lineStart(i)
    let col = i - start
    for _ in 0..<max(0, n) {
      let end = lineEnd(start)
      if end >= text.count { break }
      start = end + 1
    }
    return min(start + col, lineEnd(start))
  }

  func lineUp(_ i: Int, _ n: Int) -> Int {
    var start = lineStart(i)
    let col = i - start
    var n = n
    while n > 0 && start > 0 {
      start = lineStart(start - 1)
      n -= 1
    }
    return min(start + col, lineEnd(start))
  }

  func firstNonBlank(_ i: Int) -> Int {
    var j = lineStart(i)
    let end = lineEnd(i)
    while j < end && (text[j] == " " || text[j] == "\t") { j += 1 }
    return j
  }

  func charClass(_ i: Int) -> Int {
    if i < 0 || i >= text.count || text[i].isWhitespace { return 0 }
    let r = text[i]
    return r == "_" || r.isLetter || r.isNumber ? 1 : 2
  }

  func wordFwd(_ i: Int) -> Int {
    var i = i
    let c = charClass(i)
    if c != 0 { while i < text.count && charClass(i) == c { i += 1 } }
    while i < text.count && charClass(i) == 0 { i += 1 }
    return i
  }

  func wordEnd(_ i: Int) -> Int {
    var i = i + 1
    while i < text.count && charClass(i) == 0 { i += 1 }
    if i >= text.count { return max(0, text.count - 1) }
    let c = charClass(i)
    while i + 1 < text.count && charClass(i + 1) == c { i += 1 }
    return i
  }

  func wordBack(_ i: Int) -> Int {
    if i == 0 { return 0 }
    var i = i - 1
    while i > 0 && charClass(i) == 0 { i -= 1 }
    let c = charClass(i)
    while i > 0 && charClass(i - 1) == c { i -= 1 }
    return i
  }

  func save() {
    undo.append((text, cur))
    redo = []
  }
  func put(_ i: Int, _ rs: [Character]) { text.insert(contentsOf: rs, at: i) }
  @discardableResult func del(_ a: Int, _ b: Int) -> [Character] {
    let out = Array(text[a..<b])
    text.removeSubrange(a..<b)
    return out
  }

  func matches() -> [(Int, Int)] {
    guard !search.isEmpty, let re = compileSearch(search) else { return [] }
    let s = String(text)
    return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
      guard m.range.length > 0, let r = Range(m.range, in: s) else { return nil }
      let a = s.distance(from: s.startIndex, to: r.lowerBound)  // O(n) per match, fine at post length
      return (a, a + s[r].count)
    }
  }

  func find(_ back: Bool, _ n: Int) -> (Int, Bool) {
    let ms = matches()
    if ms.isEmpty {
      if !search.isEmpty { msg = "pattern not found: " + search }
      return (cur, false)
    }
    var pos = cur
    for _ in 0..<n {
      if back {
        if let m = ms.last(where: { $0.0 < pos }) {
          pos = m.0
        } else {
          pos = ms.last!.0
          msg = "search hit TOP, continuing at BOTTOM"
        }
      } else {
        if let m = ms.first(where: { $0.0 > pos }) {
          pos = m.0
        } else {
          pos = ms[0].0
          msg = "search hit BOTTOM, continuing at TOP"
        }
      }
    }
    return (pos, true)
  }

  static let brackets: [String: (Character, Character)] = [
    "(": ("(", ")"), ")": ("(", ")"), "b": ("(", ")"), "[": ("[", "]"), "]": ("[", "]"),
    "{": ("{", "}"), "}": ("{", "}"), "B": ("{", "}"), "<": ("<", ">"), ">": ("<", ">"),
  ]

  func object(_ k: String, _ around: Bool) -> (Int, Int, Bool)? {
    if text.isEmpty { return nil }
    var cur = min(self.cur, text.count - 1)
    let ls = lineStart(cur)
    let le = lineEnd(cur)
    switch k {
    case "w":
      if ls == le { return nil }
      cur = min(cur, le - 1)
      let c = charClass(cur)
      func same(_ i: Int) -> Bool { i >= ls && i < le && charClass(i) == c }
      var a = cur
      var b = cur + 1
      while same(a - 1) { a -= 1 }
      while same(b) { b += 1 }
      if around {
        var j = b
        while j < le && charClass(j) == 0 { j += 1 }
        if j > b { b = j } else { while a > ls && charClass(a - 1) == 0 { a -= 1 } }
      }
      return (a, b, false)
    case "\"", "'", "`":
      let q = Character(k)
      let qs = (ls..<le).filter { text[$0] == q && ($0 == ls || text[$0 - 1] != "\\") }
      var j = 0
      while j + 1 < qs.count {
        if cur <= qs[j + 1] {
          return around ? (qs[j], qs[j + 1] + 1, false) : (qs[j] + 1, qs[j + 1], false)
        }
        j += 2
      }
      return nil
    case "p":
      func blank(_ i: Int) -> Bool {
        String(text[self.lineStart(i)..<self.lineEnd(i)]).trimmingCharacters(
          in: .whitespaces
        )
        .isEmpty
      }
      let isBlank = blank(cur)
      var first = ls
      var last = ls
      while first > 0 && blank(first - 1) == isBlank { first = self.lineStart(first - 1) }
      while self.lineEnd(last) < text.count && blank(self.lineEnd(last) + 1) == isBlank {
        last = self.lineEnd(last) + 1
      }
      if around && !isBlank {
        while self.lineEnd(last) < text.count && blank(self.lineEnd(last) + 1) {
          last = self.lineEnd(last) + 1
        }
      }
      return (first, last, true)
    default: break
    }
    guard let (open, close) = Vim.brackets[k] else { return nil }
    var o = -1
    if text[cur] == open {
      o = cur
    } else {
      var i = text[cur] == close ? cur - 1 : cur
      var depth = 0
      while i >= 0 && o < 0 {
        if text[i] == close {
          depth += 1
        } else if text[i] == open {
          if depth == 0 { o = i }
          depth -= 1
        }
        i -= 1
      }
    }
    if o < 0 { return nil }
    var c = -1
    var depth = 0
    var i = o + 1
    while i < text.count && c < 0 {
      if text[i] == open {
        depth += 1
      } else if text[i] == close {
        if depth == 0 { c = i }
        depth -= 1
      }
      i += 1
    }
    if c < 0 { return nil }
    if around { return (o, c + 1, false) }
    var a = o + 1
    var b = c
    if a < b && text[a] == "\n" {  // multi-line block: keep the bracket lines
      a += 1
      if String(text[self.lineStart(c)..<c]).trimmingCharacters(in: .whitespaces).isEmpty {
        b = max(a, self.lineStart(c))
      }
    }
    return (a, b, false)
  }

  func motion(_ k: String, _ n: Int, _ counted: Bool, _ op: String) -> (Int, Bool, Bool)? {
    func rep(_ f: (Int) -> Int) -> Int {
      var i = cur
      for _ in 0..<n { i = f(i) }
      return i
    }
    switch k {
    case "h", "left", "backspace": return (max(lineStart(cur), cur - n), false, false)
    case "l", "right", " ": return (min(lineEnd(cur), cur + n), false, false)
    case "j", "down": return (lineDown(cur, n), true, false)
    case "k", "up": return (lineUp(cur, n), true, false)
    case "0", "home": return (lineStart(cur), false, false)
    case "^": return (firstNonBlank(cur), false, false)
    case "$", "end": return (lineEnd(lineDown(cur, n - 1)), false, false)
    case "w":
      if op == "c" && charClass(cur) != 0 {  // cw changes to the end of this word, like ce
        var end = cur
        let c = charClass(end)
        while end + 1 < text.count && charClass(end + 1) == c { end += 1 }
        for _ in 0..<(n - 1) { end = wordEnd(end) }
        return (end, false, true)
      }
      var to = rep(wordFwd)
      if !op.isEmpty && to > lineEnd(cur) { to = lineEnd(cur) }
      return (to, false, false)
    case "e": return (rep(wordEnd), false, true)
    case "b": return (rep(wordBack), false, false)
    case "n", "N": return (find(searchBk != (k == "N"), n).0, false, false)
    case "*", "#":
      if let (a, b, _) = object("w", false), charClass(a) == 1 {
        search =
          "\\b" + NSRegularExpression.escapedPattern(for: String(text[a..<b])) + "\\b"
        searchBk = k == "#"
        return (find(searchBk, n).0, false, false)
      }
      return (cur, false, false)
    case "gg", "G":
      var to = lineStart(text.count)
      if counted || k == "gg" { to = lineDown(0, n - 1) }
      return (firstNonBlank(to), true, false)
    default: return nil
    }
  }

  func apply(_ op: String, _ from: Int, _ to: Int, _ linewise: Bool, _ inclusive: Bool) {
    var a = min(from, to)
    var b = max(from, to)
    if linewise {
      a = lineStart(a)
      b = lineEnd(b)
      if op != "c" { if b < text.count { b += 1 } else if a > 0 { a -= 1 } }
    } else if inclusive {
      b = min(b + 1, text.count)
    }
    reg = Array(text[a..<b])
    regLine = linewise
    if linewise {
      reg = Array(String(reg).trimmingCharacters(in: CharacterSet(charactersIn: "\n")))
    }
    if op == "y" {
      // yanks also go to the system clipboard; deletes stay in vim's register
      #if os(macOS)
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(String(reg) + (linewise ? "\n" : ""), forType: .string)
      #else
      UIPasteboard.general.string = String(reg) + (linewise ? "\n" : "")
      #endif
      cur = a
      clamp()
      return
    }
    save()
    del(a, b)
    cur = a
    if op == "c" {
      insert = true
      return
    }
    if linewise { cur = firstNonBlank(min(a, text.count)) }
    clamp()
  }

  func paste(_ after: Bool, _ n: Int) {
    if reg.isEmpty { return }
    save()
    if regLine {
      let block = Array(String(repeating: "\n" + String(reg), count: n))
      if after {
        let i = lineEnd(cur)
        put(i, block)
        cur = i + 1
      } else {
        let i = lineStart(cur)
        put(i, Array(block.dropFirst()) + ["\n"])
        cur = i
      }
      return
    }
    let rs = Array(String(repeating: String(reg), count: n))
    var i = cur
    if after && cur < lineEnd(cur) { i += 1 }
    put(i, rs)
    cur = i + rs.count - 1
    clamp()
  }

  func pasteText(_ s: String) {
    let rs = Array(s.replacingOccurrences(of: "\r\n", with: "\n"))
    save()
    put(cur, rs)
    cur += rs.count
    clamp()
  }

  func startInsert() {
    save()
    insert = true
  }

  func texPrefix() -> String? {
    guard insert else { return nil }
    var i = cur
    while i > 0, text[i - 1].isLetter { i -= 1 }
    guard i > 0, text[i - 1] == "\\", i < 2 || text[i - 2] != "\\" else { return nil }
    return String(text[i..<cur])
  }

  func linkPrefix() -> String? {
    guard insert else { return nil }
    var i = cur
    while i > 0, text[i - 1] != "\n", text[i - 1] != "]" {
      if i > 1, text[i - 1] == "[", text[i - 2] == "[" { return String(text[i..<cur]) }
      i -= 1
    }
    return nil
  }

  /// complete replaces the typed \\prefix with c, adding {} per argument
  /// and leaving the cursor in the first; a link is closed with ]] and the
  /// cursor put after it.
  func complete(_ c: Completion) {
    if c.link, let p = linkPrefix() {
      let at = cur - p.count
      let closed = cur + 1 < text.count && text[cur] == "]" && text[cur + 1] == "]"
      del(at, cur)
      put(at, Array(c.name + (closed ? "" : "]]")))
      cur = at + c.name.count + 2
      return
    }
    guard let p = texPrefix() else { return }
    let at = cur - p.count
    del(at, cur)
    put(at, Array(c.name + String(repeating: "{}", count: c.args)))
    cur = at + c.name.count + (c.args > 0 ? 1 : 0)
  }

  func insertKey(_ k: Key) {
    switch k {
    case .named("esc"):
      insert = false
      if cur > lineStart(cur) { cur -= 1 }
    case .named("enter"):
      put(cur, ["\n"])
      cur += 1
    case .named("tab"):
      put(cur, [" ", " "])
      cur += 2
    case .named("backspace"):
      if cur > 0 {
        del(cur - 1, cur)
        cur -= 1
      }
    case .named("delete"): if cur < text.count { del(cur, cur + 1) }
    case .named("ctrl+w"):
      let a = wordBack(cur)
      del(a, cur)
      cur = a
    case .named("ctrl+u"):
      let a = lineStart(cur)
      del(a, cur)
      cur = a
    case .named("left"): cur = max(0, cur - 1)
    case .named("right"): cur = min(text.count, cur + 1)
    case .named("up"): cur = lineUp(cur, 1)
    case .named("down"): cur = lineDown(cur, 1)
    case .named("home"), .named("ctrl+a"): cur = lineStart(cur)
    case .named("end"), .named("ctrl+e"): cur = lineEnd(cur)
    case .text(let t):
      let rs = Array(
        t.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
          of: "\r", with: "\n"))
      put(cur, rs)
      cur += rs.count
    default: break
    }
  }

  func command(_ k: Key) -> Act {
    switch k {
    case .named("esc"):
      cmd = nil
      pending = ""
      count = 0
    case .named("backspace"): if cmd!.isEmpty { cmd = nil } else { cmd!.removeLast() }
    case .named("enter"):
      let c = cmd!
      cmd = nil
      if cmdKind != ":" {
        if !c.isEmpty { search = c }
        searchBk = cmdKind == "?"
        let (to, ok) = find(searchBk, 1)
        if !pending.isEmpty {  // d/pat, c?pat ...
          let op = pending
          pending = ""
          count = 0
          if ok { apply(op, cur, to, false, false) }
        } else if ok {
          cur = to
          clamp()
        }
        return .stay
      }
      switch c {
      case "w":
        orig = value
        return .write
      case "wq", "x": return .save
      case "q!": return .discard
      case "q":
        if value == orig { return .discard }
        msg = "unsaved changes (:q! discards, :w saves)"
      case "noh", "nohlsearch": break
      default: msg = "not a command: " + c
      }
    case .text(let t): cmd! += t
    default: break
    }
    return .stay
  }

  var idle: Bool { !insert && cmd == nil && pending.isEmpty && count == 0 && visual == nil }

  func key(_ k: Key) -> Act {
    if idle {
      rec = []
      recUndo = undo.count
    }
    rec.append(k)
    let act = step(k)
    if idle && undo.count > recUndo {
      let first = rec.first { !($0.s.count == 1 && $0.s.first!.isNumber) }?.s ?? ""
      if first != "u" && first != "ctrl+r" && first != "." { last = rec }
    }
    return act
  }

  func step(_ k: Key) -> Act {
    msg = ""
    if cmd != nil { return command(k) }
    if insert {
      insertKey(k)
      return .stay
    }
    var s = k.s
    if pending == "r" {
      pending = ""
      count = 0
      if case .text(let t) = k, t.count == 1, cur < lineEnd(cur) {
        save()
        text[cur] = t.first!
      }
      return .stay
    }
    if let lastP = pending.last, lastP == "i" || lastP == "a" {
      let op = String(pending.dropLast())
      let r = object(s, lastP == "a")
      pending = ""
      count = 0
      if let (a, b, lw) = r {
        if visual != nil {
          anchor = a
          cur = max(a, b - 1)
          if lw {
            visual = "V"
            cur = b
          }
        } else {
          apply(op, a, b, lw, false)
        }
      }
      return .stay
    }
    if case .text = k, s.count == 1, let d = s.first!.wholeNumberValue, s.first!.isASCII,
      d > 0 || count > 0
    {
      count = count * 10 + d
      return .stay
    }
    let op = pending.hasSuffix("g") ? String(pending.dropLast()) : pending
    if pending.hasSuffix("g") {
      s = "g" + s
    } else if s == "g" {
      pending += "g"
      return .stay
    }
    let n = max(1, count)
    let counted = count > 0
    func reset() {
      count = 0
      pending = ""
    }

    if let v = visual {
      switch s {
      case "esc": visual = nil
      case "v", "V": visual = Character(s) == v ? nil : Character(s)
      case "o": (anchor, cur) = (cur, anchor)
      case "i", "a":
        pending = s
        return .stay
      case "/", "?", ":":
        cmd = ""
        cmdKind = Character(s)
        return .stay
      case "d", "x", "y", "c", "s":
        let o = ["x": "d", "s": "c"][s] ?? s
        let lw = v == "V"
        visual = nil
        apply(o, anchor, cur, lw, !lw)
      default:
        if let (to, _, _) = motion(s, n, counted, "") {
          cur = to
          clamp()
        }
      }
      reset()
      return .stay
    }

    if !op.isEmpty && op == pending && (s == "i" || s == "a") {
      pending = op + s
      return .stay
    }  // diw, ca", yi( ...
    if !op.isEmpty && op == pending && (s == "/" || s == "?") {
      cmd = ""
      cmdKind = Character(s)
      return .stay
    }
    if !op.isEmpty && s == op {
      apply(op, cur, lineDown(cur, n - 1), true, false)
      reset()
      return .stay
    }  // dd cc yy
    if let (to, lw, inc) = motion(s, n, counted, op) {
      if op.isEmpty {
        cur = to
        clamp()
      } else {
        apply(op, cur, to, lw, inc)
      }
      reset()
      return .stay
    }
    if !op.isEmpty {
      reset()
      return .stay
    }
    switch s {
    case "esc": if count == 0 && pending.isEmpty { return .save }
    case "d", "c", "y", "r":
      pending = s
      return .stay
    case "v", "V":
      visual = Character(s)
      anchor = cur
    case ".": for k in last { _ = step(k) }
    case ":", "/", "?":
      cmd = ""
      cmdKind = Character(s)
    case "i": startInsert()
    case "a":
      if cur < lineEnd(cur) { cur += 1 }
      startInsert()
    case "I":
      cur = firstNonBlank(cur)
      startInsert()
    case "A":
      cur = lineEnd(cur)
      startInsert()
    case "o":
      startInsert()
      cur = lineEnd(cur)
      put(cur, ["\n"])
      cur += 1
    case "O":
      startInsert()
      cur = lineStart(cur)
      put(cur, ["\n"])
    case "x":
      if cur < lineEnd(cur) { apply("d", cur, min(cur + n, lineEnd(cur)), false, false) }
    case "X":
      if cur > lineStart(cur) { apply("d", max(lineStart(cur), cur - n), cur, false, false) }
    case "D", "C": apply(s.lowercased(), cur, lineEnd(lineDown(cur, n - 1)), false, false)
    case "s": apply("c", cur, min(cur + n, lineEnd(cur)), false, false)
    case "S": apply("c", cur, lineDown(cur, n - 1), true, false)
    case "p", "P": paste(s == "p", n)
    case "J":
      save()
      for _ in 0..<max(1, n - 1) {
        let end = lineEnd(cur)
        if end >= text.count { break }
        var next = end + 1
        while next < text.count && (text[next] == " " || text[next] == "\t") { next += 1 }
        del(end, next)
        if end > lineStart(end) && end < lineEnd(end) { put(end, [" "]) }
        cur = end
      }
    case "u", "ctrl+r":
      for _ in 0..<n {
        if s == "u" {
          guard let l = undo.popLast() else { break }
          redo.append((text, cur))
          (text, cur) = l
        } else {
          guard let l = redo.popLast() else { break }
          undo.append((text, cur))
          (text, cur) = l
        }
      }
      clamp()
    default: break
    }
    reset()
    return .stay
  }

  var mode: String {
    if cmd != nil { return cmdKind == ":" ? "COMMAND" : "SEARCH" }
    if insert { return "INSERT" }
    if visual == "v" { return "VISUAL" }
    if visual == "V" { return "V-LINE" }
    return "NORMAL"
  }

  var status: String {
    if let c = cmd { return String(cmdKind) + c + "▏" }
    if !msg.isEmpty { return msg }
    if insert { return "esc normal mode · ctrl+w delete word" }
    if visual != nil { return "d c y act · i a text object · o other end · esc leave" }
    let p = (count > 0 ? String(count) : "") + pending
    return p.isEmpty ? ":w write · esc close · :q! discard · u undo" : p
  }
}

func compileSearch(_ p: String) -> NSRegularExpression? {
  let opts: NSRegularExpression.Options = p.lowercased() == p ? .caseInsensitive : []
  return (try? NSRegularExpression(pattern: p, options: opts))
    ?? (try? NSRegularExpression(
      pattern: NSRegularExpression.escapedPattern(for: p), options: opts))
}
