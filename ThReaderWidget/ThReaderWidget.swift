// The home screen widget: the latest threads of the workspace the phone
// last showed, as the app left them in the shared group container.
import SwiftUI
import WidgetKit

struct Recent: Codable {
  var workspace = ""
  var threads: [Item] = []
  struct Item: Codable, Hashable {
    var title: String
    var name: String  // file name without .md, for the threader-link
    var posts: Int
    var date: Date
  }
}

struct Entry: TimelineEntry {
  var date = Date()
  var recent = Recent()
}

struct Provider: TimelineProvider {
  func load() -> Entry {
    let u = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: "group.com.mryodo.threader")?
      .appendingPathComponent("recent.json")
    let r = u.flatMap { try? Data(contentsOf: $0) }.flatMap {
      try? JSONDecoder().decode(Recent.self, from: $0)
    }
    return Entry(recent: r ?? Recent())
  }
  func placeholder(in context: Context) -> Entry {
    Entry(recent: Recent(workspace: "Threads", threads: [.init(title: "A thread", name: "", posts: 3, date: Date())]))
  }
  func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(load()) }
  // the app asks for a reload whenever its list changes
  func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
    completion(Timeline(entries: [load()], policy: .never))
  }
}

struct RecentView: View {
  @Environment(\.widgetFamily) var family
  let entry: Entry

  var body: some View {
    let n = family == .systemLarge ? 8 : family == .systemMedium ? 3 : 2
    VStack(alignment: .leading, spacing: 6) {
      Text(entry.recent.workspace).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      if entry.recent.threads.isEmpty {
        Text("Open ThReader to fill this in.").font(.footnote).foregroundStyle(.secondary)
      }
      ForEach(entry.recent.threads.prefix(n), id: \.self) { t in
        Link(destination: URL(string: "threader-link:" + (t.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))!) {
          VStack(alignment: .leading, spacing: 1) {
            Text(t.title).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("\(t.posts) posts · \(t.date, style: .relative)").font(.caption2).foregroundStyle(.secondary)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .containerBackground(.fill.tertiary, for: .widget)
  }
}

@main
struct ThReaderWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "recent", provider: Provider()) { RecentView(entry: $0) }
      .configurationDisplayName("Recent threads")
      .description("The latest threads in your workspace.")
      .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
