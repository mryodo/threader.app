import Foundation
import Observation

func finishSection(_ current: inout [String], _ thread: inout Thread) {
  let body = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  current = []
  if thread.notes.isEmpty {
    thread.card = body
  } else {
    thread.notes[thread.notes.count - 1].body = body
  }
}

func ago(_ t: Date, _ now: Date = Date()) -> String {
  let d = now.timeIntervalSince(t)
  switch d {
  case ..<60: return "now"
  case ..<3600: return "\(Int(d / 60))m ago"
  case ..<86400: return "\(Int(d / 3600))h ago"
  case ..<(7 * 86400): return "\(Int(d / 86400))d ago"
  default:
    let f = DateFormatter()
    let sameYear = Calendar.current.isDate(t, equalTo: now, toGranularity: .year)
    f.dateFormat = sameYear ? "MMM d" : "MMM d yyyy"
    return f.string(from: t)
  }
}

func prettyTS(_ ts: String) -> String {
  let f = DateFormatter()
  f.dateFormat = stampFormat
  guard let t = f.date(from: ts) else { return ts }
  f.dateFormat = "MMM d, HH:mm"
  return f.string(from: t) + " · " + ago(t)
}

func plural(_ n: Int, _ word: String) -> String {
  n == 1 ? "1 \(word)" : "\(n) \(word)s"
}
