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
  init() {

  }
}
