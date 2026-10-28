import SwiftUI
@_spi(Textual) import SwiftUIMath
import Textual

// TODO: probably need to move it to settings
//
let mathFace: MathProperties.FontName = .fira

struct MarkdownView: View {
  let text: String
  let p: Palette
  var dir: URL? = nil  // the thread's folder, for images by relative path
  var toggle: ((String) -> Void)? = nil  // ticks a task line, given as drawn

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(Array(splitCallouts(text).enumerated()), id: \.offset) { _, b in
        if b.type == "MATH" {
          ScrollView(.horizontal, showsIndicators: false) {
            StructuredText(markdown: b.body, syntaxExtensions: [.math])
              .threaderMarkdown(p)
          }
          .padding(14).frame(maxWidth: .infinity)
          .background(RoundedRectangle(cornerRadius: 14).fill(p.mathBg))
        } else if let type = b.type {
          let c = p.callout(type)
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
              Image(systemName: calloutIcon(type)).font(
                .system(size: 12 * fontScale, weight: .bold)
              )
              .foregroundStyle(c)
              Caps(text: b.head.isEmpty ? type : b.head, color: c)
            }
            MarkdownView(text: b.body, p: p, dir: dir, toggle: toggle)
          }
          .padding(.vertical, 12).padding(.leading, 18).padding(.trailing, 14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 14).fill(c.opacity(0.10)))
          .overlay(alignment: .leading) {
            Capsule().fill(c).frame(width: 4).padding(.vertical, 10).padding(
              .leading, 6)
          }
        } else {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(splitRows(b.body).enumerated()), id: \.offset) { _, s in
              switch s.kind {
              case .task: TaskRow(line: s.text, p: p, toggle: toggle)
              case .image(let alt, let src): ImageRow(alt: alt, src: src, dir: dir, p: p)
              case .text:
                StructuredText(
                  markdown: inlineMath(linkify(hardBreaks(mathHeadroom(s.text)))), baseURL: dir,
                  syntaxExtensions: [.math]
                )
                .threaderMarkdown(p)
              }
            }
          }
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
    let t = line.trimmingCharacters(in: .whitespaces)
    if !fence, t.hasPrefix("$$") || t == "```math" {
      flush()
      let close = t.hasPrefix("$$") ? "$$" : "```"
      var src = [String(t.dropFirst(close == "$$" ? 2 : 7))]
      while !src.last!.hasSuffix(close), i + 1 < lines.count {
        i += 1
        src.append(lines[i].trimmingCharacters(in: .whitespaces))
      }
      let body = src.joined(separator: " ")
      out.append(
        (
          "MATH", "",
          "$$" + (body.hasSuffix(close) ? String(body.dropLast(close.count)) : body)
            + "$$"
        ))
      i += 1
      continue
    }
    if t.hasPrefix("```") { fence.toggle() }
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

func inlineMath(_ md: String) -> String {
  var fence = false
  return md.components(separatedBy: "\n").map { line in
    if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { fence.toggle() }
    if fence || line.trimmingCharacters(in: .whitespaces).hasPrefix("```") { return line }
    return line.replacing(/(`[^`]*`|\\\$|\$\$.+?\$\$)|\$([^$\s](?:[^$]*[^$\s])?)\$/) { m in
      guard let src = m.output.2 else { return String(m.output.0) }
      let enc = expandMacros(String(src)).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
      return "![math](mathchip:\(enc))"
    }
  }.joined(separator: "\n")
}

struct MathChipLoader: AttachmentLoader {
  let ink: Color, bg: Color, size: CGFloat

  func attachment(for url: URL, text: String, environment: ColorEnvironmentValues)
    async throws -> AnyAttachment
  {
    if url.scheme == "mathchip" {
      let latex = String(url.absoluteString.dropFirst(9)).removingPercentEncoding ?? ""
      return AnyAttachment(
        MathChip(latex: latex, ink: ink, bg: bg, size: size) as any Textual.Attachment)
    }
    return try await load(.image(), url, text, environment)
  }

  private func load(
    _ loader: some AttachmentLoader, _ url: URL, _ text: String, _ env: ColorEnvironmentValues
  ) async throws -> AnyAttachment {
    AnyAttachment(
      try await loader.attachment(for: url, text: text, environment: env)
        as any Textual.Attachment)
  }
}

struct MathChip: Attachment {
  let latex: String, ink: Color, bg: Color, size: CGFloat
  static let pad = CGSize(width: 4, height: 1)

  var description: String { "$\(latex)$" }
  var selectionStyle: AttachmentSelectionStyle { .text }
  var font: Math.Font { .init(name: .init(rawValue: mathFace.rawValue), size: size) }

  // The text reserves a 1pt-tall placeholder on the baseline, so math never
  // grows its line (as in threader). Textual draws the body into it, so the
  // body is that size too and the chip hangs over it, its baseline on the
  // placeholder's bottom, free to overlap the lines around.
  var body: some View {
    let b = bounds(.unspecified)
    Color.clear.frame(width: b.size.width + 2 * Self.pad.width, height: 1)
      .overlay(alignment: .bottom) {
        Math(latex).mathFont(font).mathTypesettingStyle(.text).foregroundStyle(ink)
          .frame(width: b.size.width, height: b.size.height)
          .padding(.horizontal, Self.pad.width).padding(.vertical, Self.pad.height)
          .background(RoundedRectangle(cornerRadius: 4).fill(bg))
          .fixedSize()
          .offset(y: b.descent + Self.pad.height)
      }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize {
    CGSize(width: bounds(proposal).size.width + 2 * Self.pad.width, height: 1)
  }

  private func bounds(_ proposal: ProposedViewSize) -> Math.TypographicBounds {
    Math.typographicBounds(for: latex, fitting: proposal, font: font, style: .text)
  }
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
          .link(.foregroundColor(p.accent), .fontWeight(.semibold))
      )
      .textual.mathProperties(MathProperties(fontName: mathFace))
      .textual.imageAttachmentLoader(
        MathChipLoader(ink: p.ink, bg: p.mathBg, size: 15 * fontScale * 1.2)
      )
      .textual.headingStyle(Heading(p: p))
      .textual.unorderedListMarker(Bullet(p: p))
      .textual.orderedListMarker(Number(p: p))
      .textual.blockQuoteStyle(Quote(p: p))
      .textual.thematicBreakStyle(Rule(p: p))
      .textual.codeBlockStyle(Code(p: p))
      .textual.highlighterTheme(
        .init(
          foregroundColor: .init(p.ink), backgroundColor: .init(p.sunk),
          tokenProperties: [
            .comment: AnyTextProperty(.foregroundColor(p.inkSoft), .italic),
            .blockComment: AnyTextProperty(.foregroundColor(p.inkSoft), .italic),
            .docComment: AnyTextProperty(.foregroundColor(p.inkSoft), .italic),
            .string: AnyTextProperty(.foregroundColor(p.teal)),
            .char: AnyTextProperty(.foregroundColor(p.teal)),
            .number: AnyTextProperty(.foregroundColor(p.amber)),
            .keyword: AnyTextProperty(.foregroundColor(p.accent)),
            .boolean: AnyTextProperty(.foregroundColor(p.accent)),
            .builtin: AnyTextProperty(.foregroundColor(p.accent)),
          ]))
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
