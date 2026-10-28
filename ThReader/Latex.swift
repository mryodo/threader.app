// LaTeX: preamble macros and command completion. The symbol names in
// latex_symbols.json (shared with the terminal app's latex.go) come from
// markview.nvim (https://github.com/OXY2DEV/markview.nvim).
import Foundation

struct TexTables: Decodable {
  let entries: [String: String]
  let fonts: [String: [String: String]]
}

let tex: TexTables = {
  let url = Bundle.main.url(forResource: "latex_symbols", withExtension: "json")!
  return try! JSONDecoder().decode(TexTables.self, from: Data(contentsOf: url))
}()

/// The preamble's commands: name → (argument count, body).
var texMacros: [String: (Int, String)] = [:]

/// Reads \newcommand, \renewcommand, \def and
/// \DeclareMathOperator definitions out of a preamble; anything else is ignored.
func parseMacros(_ src: String, load: (String) -> String? = { _ in nil }, seen: Set<String> = [])
  -> [String: (Int, String)]
{
  let s = Array(src)
  var out: [String: (Int, String)] = [:]
  var i = 0
  var seen = seen
  func skip() { while i < s.count, s[i].isWhitespace { i += 1 } }
  func name() -> String? {  // \foo or {\foo}
    skip()
    let braced = i < s.count && s[i] == "{"
    if braced {
      i += 1
      skip()
    }
    guard i < s.count, s[i] == "\\" else { return nil }
    i += 1
    let a = i
    while i < s.count, s[i].isLetter { i += 1 }
    let n = String(s[a..<i])
    if braced {
      skip()
      if i < s.count, s[i] == "}" { i += 1 }
    }
    return n.isEmpty ? nil : n
  }
  func group() -> String? {  // a balanced {…}, verbatim
    skip()
    guard i < s.count, s[i] == "{" else { return nil }
    var depth = 0
    let a = i + 1
    while i < s.count {
      if s[i] == "{" {
        depth += 1
      } else if s[i] == "}" {
        depth -= 1
        if depth == 0 {
          i += 1
          return String(s[a..<i - 1])
        }
      }
      i += 1
    }
    return nil
  }
  while i < s.count {
    guard s[i] == "\\" else {
      if s[i] == "%" { while i < s.count, s[i] != "\n" { i += 1 } }
      i += 1
      continue
    }
    i += 1
    let a = i
    while i < s.count, s[i].isLetter { i += 1 }
    let cmd = String(s[a..<i])
    if i < s.count, s[i] == "*" { i += 1 }
    switch cmd {
    case "newcommand", "renewcommand", "providecommand", "DeclareMathOperator":
      guard let n = name() else { continue }
      var args = 0
      skip()
      if i < s.count, s[i] == "[" {
        i += 1
        let b = i
        while i < s.count, s[i] != "]" { i += 1 }
        args = Int(String(s[b..<min(i, s.count)])) ?? 0
        i += 1
      }
      if let body = group() {
        out[n] = (args, cmd == "DeclareMathOperator" ? "\\operatorname{\(body)}" : body)
      }
    case "def":
      guard let n = name() else { continue }
      var args = 0
      while i < s.count, s[i] == "#" {
        i += 2
        args += 1
      }  // \def\f#1#2{…}
      if let body = group() { out[n] = (args, body) }
    case "usepackage", "RequirePackage", "input":
      // a package found by load (a .sty beside the preamble) adds its
      // macros; others (amsmath, …) have no TeX engine to run, so skip
      skip()
      if i < s.count, s[i] == "[" {
        while i < s.count, s[i] != "]" { i += 1 }
        i += 1
      }
      for p in (group() ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }
      ) where !seen.contains(p) {
        seen.insert(p)
        if let text = load(p) { out.merge(parseMacros(text, load: load, seen: seen)) { a, _ in a } }
      }
    default: break
    }
  }
  return out
}

/// Writes the preamble's commands out in full, for SwiftMath,
/// which reads no preamble (nor \\operatorname: \\mathrm stands in).
func expandMacros(_ s: String, depth: Int = 0) -> String {
  let src = Array(s)
  var i = 0
  var out = ""
  func rawArg() -> String {  // a {group} verbatim, or one character
    while i < src.count, src[i] == " " { i += 1 }
    guard i < src.count else { return "" }
    if src[i] != "{" {
      i += 1
      return String(src[i - 1])
    }
    let start = i + 1
    var depth = 0
    while i < src.count {
      if src[i] == "{" { depth += 1 } else if src[i] == "}" { depth -= 1 }
      if depth == 0 { break }
      i += 1
    }
    let a = String(src[start..<min(i, src.count)])
    i += 1
    return a
  }
  while i < src.count {
    guard src[i] == "\\" else {
      out.append(src[i])
      i += 1
      continue
    }
    var j = i + 1
    while j < src.count, src[j].isLetter { j += 1 }
    let name = String(src[i + 1..<j])
    if name.isEmpty { j = min(j + 1, src.count) }  // \\ \, \{ …
    guard depth < 20, let (n, body) = texMacros[name] else {
      out += name == "operatorname" ? "\\mathrm" : String(src[i..<j])
      i = j
      continue
    }
    i = j
    var b = body
    for (k, a) in (0..<n).map({ _ in rawArg() }).enumerated().reversed() {
      b = b.replacingOccurrences(of: "#\(k + 1)", with: a)
    }
    out += expandMacros(b, depth: depth + 1)
  }
  return out
}

/// A command offered while typing \\name: a preamble macro
/// (mine, previewed by its body) or a built-in symbol, with its glyph; or with link a thread
/// or post offered while typing [[name.
struct Completion: Hashable {
  let name: String
  let args: Int
  let preview: String
  let mine: Bool
  var link = false
}

/// Lists the commands starting with prefix, preamble macros
/// first, then the shortest built-in names.
func texCompletions(_ prefix: String, limit: Int = 8) -> [Completion] {
  guard !prefix.isEmpty else { return [] }
  let mine = texMacros.filter { $0.key.hasPrefix(prefix) }.sorted { $0.key < $1.key }
    .map { Completion(name: $0.key, args: $0.value.0, preview: $0.value.1, mine: true) }
  // Scans every built-in name on each keystroke; there are only a few thousand.
  let builtin = (Array(tex.entries.keys) + Array(tex.fonts.keys)).filter {
    $0.hasPrefix(prefix) && texMacros[$0] == nil
  }
  .sorted { ($0.count, $0) < ($1.count, $1) }.prefix(limit)
  .map {
    Completion(
      name: $0, args: tex.fonts[$0] != nil ? 1 : 0,
      preview: tex.entries[$0] ?? tex.fonts[$0]?["A"] ?? "", mine: false)
  }
  return Array((mine + builtin).prefix(limit))
}
