import AppKit
import SwiftUI

struct Palette {
  var paper, raised, sunk, line, ink, inkSoft, accent, amber, teal, red, purple, yellow, button,
    onButton: Color
  var card, cardInk, cardAccent: Color  // title cards
  var cardTitle: Color? = nil  // the card's title, if not cardInk

  static let themes: [(name: String, palette: Palette, light: Bool, pair: String)] = [
    ("sw1comm", .sw1comm, true, "ayugloom"), ("ayugloom", .ayugloom, false, "sw1comm"),
    ("everforest-light", .everforestLight, true, "everforest-dark"),
    ("everforest-dark", .everforestDark, false, "everforest-light"),
    ("minischeme2-light", .minischeme2Light, true, "minischeme2-dark"),
    ("minischeme2-dark", .minischeme2Dark, false, "minischeme2-light"),
  ]

  static let ayugloom = Palette(
    paper: Color(hex: 0x0f131a), raised: Color(hex: 0x1a1f29), sunk: Color(hex: 0x2d2d42),
    line: Color(hex: 0x34344b),
    ink: Color(hex: 0xb3b1ad), inkSoft: Color(hex: 0x6f7f9b), accent: Color(hex: 0x57c0fe),
    amber: Color(hex: 0xffb179),
    teal: Color(hex: 0x94e5c9), red: Color(hex: 0xff795b), purple: Color(hex: 0xd4a7fe),
    yellow: Color(hex: 0xffcb65),
    button: Color(hex: 0x57c0fe), onButton: Color(hex: 0x0f131a),
    card: Color(hex: 0x242b3f), cardInk: Color(hex: 0xb3b1ad), cardAccent: Color(hex: 0x57c0fe),
    cardTitle: Color(hex: 0xffb179))

  static let sw1comm = Palette(
    paper: Color(hex: 0xd4d4d4), raised: Color(hex: 0xe2e2e2), sunk: Color(hex: 0xc6c6c6),
    line: Color(hex: 0xb4b4bc),
    ink: Color(hex: 0x202020), inkSoft: Color(hex: 0x5f6078), accent: Color(hex: 0x0000a0),
    amber: Color(hex: 0x0048c8),
    teal: Color(hex: 0x45763c), red: Color(hex: 0xd00000), purple: Color(hex: 0x00009f),
    yellow: Color(hex: 0x00009f),
    button: Color(hex: 0x0000a0), onButton: Color(hex: 0xd4d4d4),
    card: Color(hex: 0x0000a0), cardInk: Color(hex: 0xffffff), cardAccent: Color(hex: 0xa5c6f2))

  static let everforestDark = Palette(
    paper: Color(hex: 0x2d353b), raised: Color(hex: 0x343f44), sunk: Color(hex: 0x3d484d),
    line: Color(hex: 0x4f585e),
    ink: Color(hex: 0xd3c6aa), inkSoft: Color(hex: 0x859289), accent: Color(hex: 0xa7c080),
    amber: Color(hex: 0xdbbc7f),
    teal: Color(hex: 0x83c092), red: Color(hex: 0xe67e80), purple: Color(hex: 0xd699b6),
    yellow: Color(hex: 0xdbbc7f),
    button: Color(hex: 0xa7c080), onButton: Color(hex: 0x2d353b),
    card: Color(hex: 0x425047), cardInk: Color(hex: 0xd3c6aa), cardAccent: Color(hex: 0xa7c080),
    cardTitle: Color(hex: 0xe69875))

  static let everforestLight = Palette(
    paper: Color(hex: 0xfdf6e3), raised: Color(hex: 0xfffbef), sunk: Color(hex: 0xefebd4),
    line: Color(hex: 0xe0dcc7),
    ink: Color(hex: 0x5c6a72), inkSoft: Color(hex: 0x939f91), accent: Color(hex: 0x8da101),
    amber: Color(hex: 0xdfa000),
    teal: Color(hex: 0x35a77c), red: Color(hex: 0xf85552), purple: Color(hex: 0xdf69ba),
    yellow: Color(hex: 0xdfa000),
    button: Color(hex: 0x8da101), onButton: Color(hex: 0xfdf6e3),
    card: Color(hex: 0xf0f1d2), cardInk: Color(hex: 0x5c6a72), cardAccent: Color(hex: 0x8da101),
    cardTitle: Color(hex: 0xf57d26))

  static let minischeme2Dark = Palette(
    paper: Color(hex: 0x081823), raised: Color(hex: 0x253642), sunk: Color(hex: 0x020f19),
    line: Color(hex: 0x435562),
    ink: Color(hex: 0xd5d7c0), inkSoft: Color(hex: 0x91937d), accent: Color(hex: 0xa1ddff),
    amber: Color(hex: 0xfcc9a0),
    teal: Color(hex: 0x94e6e5), red: Color(hex: 0xffc0c4), purple: Color(hex: 0xe4c7fb),
    yellow: Color(hex: 0xdfd69b),
    button: Color(hex: 0xa1ddff), onButton: Color(hex: 0x081823),
    card: Color(hex: 0x003851), cardInk: Color(hex: 0xd5d7c0), cardAccent: Color(hex: 0xa1ddff),
    cardTitle: Color(hex: 0xfcc9a0))

  static let minischeme2Light = Palette(
    paper: Color(hex: 0xf9f0db), raised: Color(hex: 0xfff7e3), sunk: Color(hex: 0xd8cfbb),
    line: Color(hex: 0xb7af9b),
    ink: Color(hex: 0x34394a), inkSoft: Color(hex: 0x6c7285), accent: Color(hex: 0x006699),
    amber: Color(hex: 0x835200),
    teal: Color(hex: 0x008064), red: Color(hex: 0x870600), purple: Color(hex: 0x71468e),
    yellow: Color(hex: 0x6c5c00),
    button: Color(hex: 0x006699), onButton: Color(hex: 0xf9f0db),
    card: Color(hex: 0xc6e8ff), cardInk: Color(hex: 0x34394a), cardAccent: Color(hex: 0x006699),
    cardTitle: Color(hex: 0x835200))

  var onCard: Palette {
    var c = self
    c.raised = card
    c.ink = cardInk
    c.inkSoft = cardInk.opacity(0.7)
    c.sunk = .white.opacity(0.13)
    c.line = .white.opacity(0.18)
    c.accent = cardAccent
    c.amber = cardAccent
    c.button = cardInk
    c.onButton = card
    return c
  }

  var mathBg: Color {
    Color(NSColor(sunk).blended(withFraction: 0.15, of: NSColor(accent)) ?? NSColor(sunk))
  }

  func callout(_ type: String) -> Color {
    switch type {
    case "TIP", "HINT", "SUCCESS", "CHECK", "DONE": teal
    case "WARNING", "ATTENTION", "IMPORTANT", "EXAMPLE", "QUESTION", "HELP", "FAQ": amber
    case "CAUTION", "DANGER", "ERROR", "BUG", "FAIL", "FAILURE", "MISSING": red
    case "QUOTE", "CITE": inkSoft
    default: accent
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255,
      blue: Double(hex & 0xff) / 255)
  }
}

func display(_ size: CGFloat) -> Font { font(fontName, size, .bold) }
func face(_ size: CGFloat = 15, _ w: Font.Weight = .regular) -> Font { font(fontName, size, w) }

func registerFonts() {
  let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
  CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
}

let installed = Set(NSFontManager.shared.availableFontFamilies)

var fontScale: CGFloat = 1
var lineGap: CGFloat = 0.08  // extra space between lines, in ems
var fontName = "Maple Mono"
var regularFace: String?
var boldFace: String?  // the face for .bold, from settings

func fontStyles(_ family: String) -> [(style: String, face: String)] {
  (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { m in
    guard m.count >= 4, let face = m[0] as? String, let style = m[1] as? String,
      let traits = m[3] as? Int,
      traits & Int(NSFontTraitMask.italicFontMask.rawValue) == 0
    else { return nil }
    return (style, face)
  }
}

func nsFont() -> NSFont {
  regularFace.flatMap { NSFont(name: $0, size: 15 * fontScale) }
    ?? NSFontManager.shared.font(
      withFamily: fontName, traits: [], weight: 5, size: 15 * fontScale)
    ?? .monospacedSystemFont(ofSize: 15 * fontScale, weight: .regular)
}

/// The editor's paragraph style, with the line spacing from settings.
func linePara() -> NSParagraphStyle {
  let ps = NSMutableParagraphStyle()
  ps.lineSpacing = lineGap * 15 * fontScale
  return ps
}

func font(_ family: String, _ size: CGFloat, _ w: Font.Weight) -> Font {
  let size = size * fontScale
  if w == .regular, family == fontName, let face = regularFace {
    return .custom(face, size: size)
  }
  if w == .bold, family == fontName, let face = boldFace {
    return .custom(face, size: size)
  }
  return installed.contains(family)
    ? .custom(family, size: size).weight(w)
    : .system(size: size, weight: w, design: .monospaced)
}

struct Caps: View {
  let text: String
  var color: Color
  var body: some View {
    Text(text.uppercased()).font(face(11, .semibold)).tracking(1.5).foregroundStyle(color)
  }
}

struct Pill: ButtonStyle {
  let p: Palette
  var primary = false
  func makeBody(configuration c: Configuration) -> some View {
    Label(c: c, p: p, primary: primary)
  }

  struct Label: View {
    let c: Configuration
    let p: Palette
    let primary: Bool
    @Environment(\.isEnabled) var enabled
    var body: some View {
      c.label.font(face(13, .semibold))
        .padding(.horizontal, 14).padding(.vertical, 6)
        .foregroundStyle(primary ? p.onButton : p.ink)
        .background(Capsule().fill(primary ? p.button : p.sunk))
        .opacity(!enabled ? 0.4 : c.isPressed ? 0.7 : 1)
    }
  }
}

struct Raised: ViewModifier {
  let p: Palette
  var selected = false
  var radius: CGFloat = 24
  var alpha = 1.0
  func body(content: Content) -> some View {
    content
      .background(RoundedRectangle(cornerRadius: radius).fill(p.raised.opacity(alpha)))
      .overlay(
        RoundedRectangle(cornerRadius: radius).strokeBorder(
          selected ? p.accent : p.line, lineWidth: selected ? 2 : 1)
      )
      .shadow(color: .black.opacity(alpha < 1 ? 0 : 0.10), radius: 14, y: 8)
  }
}

extension Store {
  var p: Palette { Palette.themes.first { $0.name == theme }?.palette ?? .sw1comm }
  var light: Bool { Palette.themes.first { $0.name == theme }?.light ?? true }
}
