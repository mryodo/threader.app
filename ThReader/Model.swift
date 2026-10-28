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
  var sel: Pos? {
    didSet {  // remembered per workspace folder, as "file.md note"
      guard let sel else { return }
      var last = UserDefaults.standard.dictionary(forKey: "lastSel") ?? [:]
      last[dir.path] = "\(sel.path.lastPathComponent) \(sel.note)"
      UserDefaults.standard.set(last, forKey: "lastSel")
    }
  }

  var editing: Pos?  // the card or note being edited
  var adding: URL?  // the thread a new note is being written for
  var draft = ""
  var draftOrig = ""  // the draft as it was opened, so an unchanged one isn't written
  var insertStart = false  // open the editor in insert mode
  var preamble = ""  // LaTeX macros for math previews, from preambleFile
  var preambleVersion = 0

  var error: String?  // shown in the open sheet
  var help = false
  var picking = false  // the workspace picker is open...
  var pickMove: URL?  // ...to move this thread rather than to switch
  var ask: Ask?  // the name being asked for in a sheet
  enum Ask: Equatable {
    case thread
    case workspace(moving: URL?)
    case root
  }
  var showSidebar = true
  var query = ""  // the search; "#tag" lists the posts with that tag
  var theme = "sw1comm"  // a Palette.themes name

  @ObservationIgnored var undo: [(URL, String)] = []
  @ObservationIgnored var redo: [(URL, String)] = []

  // BUG: this probably should be in cache or in one json or toml file
  static let stateFile = ".threader-workspace"
  static let themeFile = ".threader-theme"
  static let pinFile = ".threader-pinned"  // per workspace: the file names pinned to the top
  static let preambleFile = ".threader-preamble.tex"

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
  var boldStyle = UserDefaults.standard.string(forKey: "boldStyle") ?? "Bold" {  // for bold text and headings
    didSet {
      UserDefaults.standard.set(boldStyle, forKey: "boldStyle")
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

  var lineSpacing = UserDefaults.standard.object(forKey: "lineSpacing") as? Double ?? 0.08 {
    didSet {
      lineGap = lineSpacing
      UserDefaults.standard.set(lineSpacing, forKey: "lineSpacing")
    }
  }

  static var askRoot: Bool {
    ProcessInfo.processInfo.environment["THREADER_DIR"] == nil
      && UserDefaults.standard.string(forKey: "root") == nil
  }
  func applyStyle() {
    regularFace = fontStyles(fontFamily).first { $0.style == fontStyle }?.face
    boldFace = fontStyles(fontFamily).first { $0.style == boldStyle }?.face
  }

  var dir: URL { ws.isEmpty ? root : root.appendingPathComponent(ws) }

  func wsName(_ w: String) -> String { w.isEmpty ? root.lastPathComponent : w }

  func workspaces() -> [String] {
    let entries =
      (try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles))
      ?? []
    let dirs = entries.filter {
      (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    return [""] + dirs.map(\.lastPathComponent).sorted()
  }

  /// The number of threads in workspace `w`.
  func count(_ w: String) -> Int {
    let d = w.isEmpty ? root : root.appendingPathComponent(w)
    let files = (try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []
    return files.filter { $0.hasSuffix(".md") }.count
  }

  func read(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }

  @discardableResult
  func write(_ text: String, to u: URL) -> Bool {
    do {
      try text.write(to: u, atomically: true, encoding: .utf8)
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }
  func switchTo(_ w: String) {
    ws = w
    reload()
    if let s = UserDefaults.standard.dictionary(forKey: "lastSel")?[dir.path] as? String,
      let space = s.lastIndex(of: " "), let note = Int(s[s.index(after: space)...]),
      let t = threads.first(where: { $0.path.lastPathComponent == s[..<space] }),
      note < t.notes.count
    {
      sel = Pos(path: t.path, note: note)
      unfolded.insert(t.path)
    } else if let first = threads.first {
      sel = Pos(path: first.path, note: -1)
      unfolded.insert(first.path)
    } else {
      sel = nil
    }
    try? (w + "\n").write(
      to: root.appendingPathComponent(Store.stateFile), atomically: true, encoding: .utf8)  // best effort
  }
  func reload() {
    let pins = pinned()
    let files =
      (try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    threads = files.filter { $0.pathExtension == "md" }.compactMap { f in
      guard var t = loadThread(f.path) else { return nil }
      t.pinned = pins.contains(f.lastPathComponent)
      return t
    }
    // pinned first, then the most recently changed
    threads.sort { $0.pinned != $1.pinned ? $0.pinned : $0.mtime > $1.mtime }
  }
  func pinned() -> Set<String> {
    let text = read(dir.appendingPathComponent(Store.pinFile)) ?? ""
    return Set(text.split(whereSeparator: \.isNewline).map(String.init))
  }

  func togglePin(_ path: URL) {
    var pins = pinned()
    let name = path.lastPathComponent
    if pins.remove(name) == nil {
      pins.insert(name)
    }
    // drop pins of threads that were deleted or moved away
    let keep = pins.filter {
      FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
    }.sorted()
    guard
      write(
        keep.joined(separator: "\n") + "\n", to: dir.appendingPathComponent(Store.pinFile))
    else { return }
    reload()
  }

  init() {
    let saved =
      ProcessInfo.processInfo.environment["THREADER_DIR"]
      ?? UserDefaults.standard.string(forKey: "root")
    root =
      saved.map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("threads")
    fontScale = fontSize / 15
    lineGap = lineSpacing
    fontName = fontFamily
    applyStyle()
    // Use the saved theme if it still exists, else the terminal app's.
    let terminalTheme = read(root.appendingPathComponent(Store.themeFile))?.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let candidates = [UserDefaults.standard.string(forKey: "theme"), terminalTheme].compactMap {
      $0
    }
    theme =
      candidates.first { name in Palette.themes.contains { $0.name == name } } ?? "ayugloom"
    open(root)
  }

  func open(_ u: URL) {
    root = u
    if !Store.askRoot {  // don't create ~/threads before the user has picked a folder
      try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    preamble = read(root.appendingPathComponent(Store.preambleFile)) ?? ""
    texMacros = parseMacros(preamble, load: loadPackage)
    preambleVersion += 1

    var last =
      read(root.appendingPathComponent(Store.stateFile))?.trimmingCharacters(
        in: .whitespacesAndNewlines) ?? ""
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(
      atPath: root.appendingPathComponent(last).path, isDirectory: &isDir)
    if last.contains("/") || !exists || !isDir.boolValue {
      last = ""
    }
    switchTo(last)
  }
  func answer(_ input: String) {
    let name = input.trimmingCharacters(in: .whitespaces)
    switch ask {
    case .thread:
      ask = nil
      newThread(name)
    case .workspace(let moving):
      guard newWorkspace(name) else { return }
      ask = nil
      if let moving {
        move(moving, to: name)
      } else {
        switchTo(name)
      }
    case .root:
      guard !name.isEmpty else { return }
      ask = nil
      setRoot(URL(fileURLWithPath: (name as NSString).expandingTildeInPath))
    case nil:
      break
    }
  }

  func newWorkspace(_ name: String) -> Bool {
    let n = name.trimmingCharacters(in: .whitespaces)
    guard !n.isEmpty, !n.hasPrefix("."), !n.contains("/"), !n.contains("\\") else {
      error = "workspace names can't be empty, start with a dot, or contain slashes"
      return false
    }
    do {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(n), withIntermediateDirectories: true)
      return true
    } catch {
      return false
    }
  }
  func move(_ path: URL, to w: String) {
    let dst = (w.isEmpty ? root : root.appendingPathComponent(w)).appendingPathComponent(
      path.lastPathComponent)
    guard dst.standardizedFileURL != path.standardizedFileURL else { return }
    guard !FileManager.default.fileExists(atPath: dst.path) else {
      error = "\(wsName(w)) already has a thread named \(dst.lastPathComponent)"
      return
    }
    do {
      try FileManager.default.moveItem(at: path, to: dst)
    } catch {
      self.error = error.localizedDescription
      return
    }
    // so undo still finds the moved file
    undo = undo.map { $0.0 == path ? (dst, $0.1) : $0 }
    redo = redo.map { $0.0 == path ? (dst, $0.1) : $0 }
    reload()
  }
  /// Picks a theme, and tells the terminal app (which knows the same names).
  func setTheme(_ name: String) {
    theme = name
    UserDefaults.standard.set(name, forKey: "theme")
    try? (name + "\n").write(
      to: root.appendingPathComponent(Store.themeFile), atomically: true, encoding: .utf8)
  }
  func setRoot(_ u: URL) {
    UserDefaults.standard.set(u.path, forKey: "root")
    commit()
    query = ""
    unfolded = []
    open(u)
  }
}
