// Draws the app icon, flat, in sw1comm's colours: a light tile, a title
// card, and a timeline with two posts hanging from it, the selected one red,
// as in the list. Writes every size into the asset catalog:
//
//	swift icon.swift
import AppKit

func color(_ hex: UInt32) -> NSColor {
  NSColor(
    srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
    blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func draw(_ px: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let ctx = NSGraphicsContext.current!.cgContext
  // drawn on a 1024 grid, top-down
  ctx.scaleBy(x: CGFloat(px) / 1024, y: -CGFloat(px) / 1024)
  ctx.translateBy(x: 0, y: -1024)

  // macOS icon grid: an 824pt rounded square centred in 1024, a plain drop shadow
  // (shadow offsets ignore the flip: negative is down)
  let tile = NSBezierPath(
    roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
  ctx.saveGState()
  ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor(white: 0, alpha: 0.25).cgColor)
  color(0xe2e2e2).setFill()
  tile.fill()
  ctx.restoreGState()
  color(0xb4b4bc).setStroke()
  tile.lineWidth = 4
  tile.stroke()

  // the timeline, behind the card
  color(0xb4b4bc).setFill()
  NSBezierPath(rect: NSRect(x: 307, y: 470, width: 18, height: 300)).fill()

  // the title card: a title line and a shorter line of text
  color(0x0000a0).setFill()
  NSBezierPath(roundedRect: NSRect(x: 230, y: 250, width: 564, height: 240), xRadius: 56, yRadius: 56)
    .fill()
  color(0xffffff).setFill()
  NSBezierPath(roundedRect: NSRect(x: 290, y: 318, width: 300, height: 40), xRadius: 20, yRadius: 20)
    .fill()
  color(0xa5c6f2).setFill()
  NSBezierPath(roundedRect: NSRect(x: 290, y: 392, width: 410, height: 30), xRadius: 15, yRadius: 15)
    .fill()

  // two posts: an older one, and the selected one in red, a bit bigger
  func dot(_ y: CGFloat, _ r: CGFloat, _ c: UInt32) {
    color(0xe2e2e2).setFill()  // the tile's colour as a ring, as in the list
    NSBezierPath(ovalIn: NSRect(x: 316 - r - 8, y: y - r - 8, width: 2 * (r + 8), height: 2 * (r + 8)))
      .fill()
    color(c).setFill()
    NSBezierPath(ovalIn: NSRect(x: 316 - r, y: y - r, width: 2 * r, height: 2 * r)).fill()
  }
  dot(590, 34, 0x0048c8)
  dot(730, 44, 0xd00000)
  // each post's text beside its dot
  color(0x5f6078).setFill()
  NSBezierPath(roundedRect: NSRect(x: 392, y: 576, width: 300, height: 28), xRadius: 14, yRadius: 14)
    .fill()
  color(0x202020).setFill()
  NSBezierPath(roundedRect: NSRect(x: 392, y: 714, width: 360, height: 32), xRadius: 16, yRadius: 16)
    .fill()

  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "ThReader/Assets.xcassets/AppIcon.appiconset")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
var images: [String] = []
for n in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let name = "icon_\(n)x\(n)\(scale == 2 ? "@2x" : "").png"
    try! draw(n * scale).write(to: dir.appendingPathComponent(name))
    images.append(
      #"{ "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(n)x\#(n)", "filename" : "\#(name)" }"#)
  }
}
// the iPhone takes the 1024 one, which is 512@2x
images.append(
  #"{ "idiom" : "universal", "platform" : "ios", "size" : "1024x1024", "filename" : "icon_512x512@2x.png" }"#)
try! """
  { "images" : [
  \(images.joined(separator: ",\n"))
  ], "info" : { "author" : "xcode", "version" : 1 } }
  """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
try! #"{ "info" : { "author" : "xcode", "version" : 1 } }"#.write(
  to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true,
  encoding: .utf8)
print("wrote \(dir.path)")
