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

let stampFormat = "yyyy-MM-dd HH:mm"
