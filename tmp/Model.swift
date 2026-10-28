import Foundation
import Observation

struct Note: Hashable {
  var timestamp: String
  var body: String
}

struct Thread: Identifiable {
  var path: URL
  var title = ""
  var card = ""
  var notes: [Note] = []
  var mtime = Date.distantPast
  var pinned = false
  var id: URL { path }
}

struct Pos: Hashable {
  var path: URL
  var note: Int
}

let stampFormat = "yyyy-MM-dd HH:mm"

func loadThread(_ path: String) -> Thread? {
  let url = URL(fileURLWithPath: path)
  guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
  var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
  while lines.last == "", lines.count > 1 { lines.removeLast() }
  var thread = Thread(
    path: url, title: lines[0].drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))
  thread.mtime =
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    ?? .distantPast
  var current: [String] = []

  for line in lines.dropFirst() {
    if line.hasPrefix("<!-- note "), line.hasSuffix(" -->") {
      finishSection(&current, &thread)
      thread.notes.append(Note(timestamp: String(line.dropFirst(10).dropLast(4)), body: ""))
    } else {
      current.append(line)
    }
  }
  finishSection(&current, &thread)
  return thread
}

func writeThread(_ t: Thread) -> String {
  var s = "# \(t.title)\n"
  if !t.card.isEmpty {
    s += "\n\(t.card)\n"
  }
  for n in t.notes {
    s += "\n<!-- note \(n.timestamp) -->\n"
    if !n.body.isEmpty {
      s += "\n\(n.body)\n"
    }
  }
  return s
}

@Observable final class Store {
  var root: URL  // the threads folder
  var ws = ""  // the open workspace; "" is the threads folder itself
  var threads: [Thread] = []
  var unfolded: Set<URL> = []
  var sel: Pos?

  var showSidebar = true
  var theme = "sw1comm"  // a Palette.themes name

  // BUG: this probably should be in cache or in one json or toml file
  static let stateFile = ".threader-workspace"
  static let themeFile = ".threader-theme"
  static let pinFile = ".threader-pinned"  // per workspace: the file names pinned to the top

  var opacity = UserDefaults.standard.object(forKey: "opacity") as? Double ?? 1 {
    didSet { UserDefaults.standard.set(opacity, forKey: "opacity") }
  }
  var cardsClear = UserDefaults.standard.object(forKey: "cardsClear") as? Bool ?? true {  // title cards follow opacity
    didSet { UserDefaults.standard.set(cardsClear, forKey: "cardsClear") }
  }
  var blur = UserDefaults.standard.object(forKey: "blur") as? Double ?? 10 {  // blur radius behind a see-through window
    didSet { UserDefaults.standard.set(blur, forKey: "blur") }
  }
  var fontFamily = UserDefaults.standard.string(forKey: "fontFamily") ?? "Maple Mono" {
    didSet {
      fontName = fontFamily
      UserDefaults.standard.set(fontFamily, forKey: "fontFamily")
      applyStyle()
    }
  }
  var fontStyle = UserDefaults.standard.string(forKey: "fontStyle") ?? "Light" {  // Thin, Light, ...
    didSet {
      UserDefaults.standard.set(fontStyle, forKey: "fontStyle")
      applyStyle()
    }
  }
  var fontSize = UserDefaults.standard.object(forKey: "fontSize") as? Double ?? 15 {
    didSet {
      let clamped = min(24, max(11, fontSize))
      if fontSize != clamped {
        fontSize = clamped
        return
      }
      fontScale = fontSize / 15
      UserDefaults.standard.set(fontSize, forKey: "fontSize")
    }
  }

  func applyStyle() {
    regularFace = fontStyles(fontFamily).first { $0.style == fontStyle }?.face
  }

  init() {

  }
}
