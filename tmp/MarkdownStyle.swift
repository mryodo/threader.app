import SwiftUI
import Textual

struct MarkdownView: View {
  let text: String
  let p: Palette

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(splitCallouts(text).enumerated()), id: \.offset) { _, b in
        if let type = b.type {
          let c = p.callout(type)
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
              Image(systemName: calloutIcon(type)).font(
                .system(size: 12 * fontScale, weight: .bold)
              )
              .foregroundStyle(c)
              Caps(text: b.head.isEmpty ? type : b.head, color: c)
            }
            MarkdownView(text: b.body, p: p)
          }
          .padding(.vertical, 12).padding(.leading, 18).padding(.trailing, 14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 14).fill(c.opacity(0.10)))
          .overlay(alignment: .leading) {
            Capsule().fill(c).frame(width: 4).padding(.vertical, 10).padding(
              .leading, 6)
          }
        } else {
          StructuredText(markdown: b.body).threaderMarkdown(p)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

func splitCallouts(_ md: String) -> [(type: String?, head: String, body: String)] {
  var out: [(type: String?, head: String, body: String)] = []
  var text: [String] = []
  var fence = false
  func flush() {
    if !text.joined().trimmingCharacters(in: .whitespaces).isEmpty {
      out.append((nil, "", text.joined(separator: "\n")))
    }
    text = []
  }
  let lines = md.components(separatedBy: "\n")
  var i = 0
  while i < lines.count {
    let line = lines[i]
    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fence.toggle() }
    if !fence, let m = line.wholeMatch(of: /\s*>\s*\[!(\w+)\][+-]?\s*(.*)/) {
      flush()
      var body: [String] = []
      while i + 1 < lines.count,
        lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">")
      {
        i += 1
        var b = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
        if b.hasPrefix(" ") { b = b.dropFirst() }
        body.append(String(b))
      }
      out.append(
        (
          m.1.uppercased(), m.2.trimmingCharacters(in: .whitespaces),
          body.joined(separator: "\n")
        ))
    } else {
      text.append(line)
    }
    i += 1
  }
  flush()
  return out
}

func calloutIcon(_ type: String) -> String {
  switch type {
  case "NOTE", "INFO": "info.circle"
  case "ABSTRACT", "SUMMARY", "TLDR": "doc.text"
  case "TODO": "circle.dashed"
  case "TIP", "HINT": "lightbulb"
  case "IMPORTANT": "exclamationmark.circle"
  case "SUCCESS", "CHECK", "DONE": "checkmark.circle"
  case "QUESTION", "HELP", "FAQ": "questionmark.circle"
  case "WARNING", "ATTENTION": "exclamationmark.triangle"
  case "CAUTION": "exclamationmark.octagon"
  case "FAILURE", "FAIL", "MISSING": "xmark.circle"
  case "DANGER", "ERROR": "bolt"
  case "BUG": "ladybug"
  case "EXAMPLE": "list.bullet"
  case "QUOTE", "CITE": "quote.opening"
  default: "bookmark"
  }
}

extension View {
  func threaderMarkdown(_ p: Palette) -> some View {
    self
      .font(face()).foregroundStyle(p.ink)
      .textual.inlineStyle(
        InlineStyle()
          .code(.font(face(14)), .backgroundColor(p.sunk))
          .strong(.font(face(15, .bold)))
          .link(.foregroundColor(p.accent), .underlineStyle(.single))
      )
      .textual.headingStyle(Heading(p: p))
      .textual.unorderedListMarker(Bullet(p: p))
      .textual.orderedListMarker(Number(p: p))
      .textual.blockQuoteStyle(Quote(p: p))
      .textual.thematicBreakStyle(Rule(p: p))
      .textual.codeBlockStyle(Code(p: p))
      .textual.highlighterTheme(
        .init(foregroundColor: .init(p.ink), backgroundColor: .init(p.sunk)))
  }
}

struct Heading: StructuredText.HeadingStyle {
  let p: Palette
  func makeBody(configuration: Configuration) -> some View {
    let n = min(configuration.headingLevel, 6)
    let c = [p.accent, p.teal, p.amber, p.red, p.purple, p.yellow][n - 1]
    let size = [20, 18, 17, 16, 15, 15][n - 1] as CGFloat
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "\(n).square.fill").font(face(size))
      configuration.label.font(display(size))
    }
    .foregroundStyle(c).padding(.vertical, 5).padding(.horizontal, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.12))).padding(.top, 4)
  }
}

struct Bullet: StructuredText.UnorderedListMarker {
  let p: Palette
  func makeBody(configuration: Configuration) -> some View {
    Circle().fill(p.amber).frame(width: 6, height: 6)
      .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
  }
}

struct Number: StructuredText.OrderedListMarker {
  let p: Palette
  func makeBody(configuration: Configuration) -> some View {
    Text("\(configuration.ordinal)").font(face(15, .bold)).foregroundStyle(p.amber)
      .monospacedDigit()
  }
}

struct Quote: StructuredText.BlockQuoteStyle {
  let p: Palette
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 10) {
      Capsule().fill(p.inkSoft).frame(width: 3)
      configuration.label.italic().foregroundStyle(p.inkSoft)
    }.fixedSize(horizontal: false, vertical: true)
  }
}

struct Rule: StructuredText.ThematicBreakStyle {
  let p: Palette
  func makeBody(configuration: Configuration) -> some View {
    Rectangle().fill(p.line).frame(height: 1).padding(.vertical, 6)
  }
}

struct Code: StructuredText.CodeBlockStyle {
  let p: Palette
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let lang = configuration.languageHint, !lang.isEmpty {
        Caps(text: lang, color: p.inkSoft)
      }
      ScrollView(.horizontal, showsIndicators: false) { configuration.label.font(face(14)) }
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14).fill(p.sunk))
  }
}
