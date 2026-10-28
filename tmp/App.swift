import Foundation
import Playgrounds
import AppKit
import SwiftUI

@main struct MyApp: App {
  @State private var store = Store()

  var body: some Scene {
    WindowGroup {
      ContentView().environment(store)
    }
    .windowStyle(.hiddenTitleBar)
    .windowBackgroundDragBehavior(.enabled)
    .commands {
      CommandGroup(replacing: .sidebar) {
        Button("Toggle Sidebar") { store.showSidebar.toggle() }.keyboardShortcut(
          "s", modifiers: [.command, .control])
        Divider()
        Button("Bigger Text") { store.fontSize += 1 }.keyboardShortcut("=")
        Button("Smaller Text") { store.fontSize -= 1 }.keyboardShortcut("-")
        Button("Default Text Size") { store.fontSize = 15 }.keyboardShortcut("0")
      }
      CommandGroup(replacing: .help) {
        Button("Keys") { store.help = true }.keyboardShortcut("/", modifiers: [.command, .shift])
      }
      CommandMenu("Threads") {
        Button("New Thread…") { store.ask = .thread }.keyboardShortcut("n")
        Button("New Workspace…") { store.ask = .workspace(moving: nil) }.keyboardShortcut(
          "n", modifiers: [.command, .shift])
        Button("Switch Workspace…") {
          store.pickMove = nil
          store.picking = true
        }.keyboardShortcut("o")
        Button("Move Thread to Workspace…") {
          guard let s = store.sel else {
            store.error = "no thread selected to move"
            return
          }
          store.pickMove = s.path
          store.picking = true
        }.keyboardShortcut("m", modifiers: [.command, .shift])
        Divider()
        Button("Undo Saved Change") { store.undoFile() }
        Button("Redo Saved Change") { store.undoFile(redoing: true) }
        Button("Reload") { store.reload() }.keyboardShortcut("r")
        Divider()
        Button("Toggle Light / Dark") { store.toggleTheme() }.keyboardShortcut(
          "b", modifiers: [.command, .shift])
      }
    }
    Settings { SettingsView().environment(store) }
  }
}

/// Makes the window see-through (clear) with the desktop behind blurred.
/// SwiftUI has no API for either; the title bar is left to .windowStyle.
struct WindowGlass: NSViewRepresentable {
  var clear: Bool
  var blur: Double
  var paper: Color

  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ v: NSView, context: Context) {
    // the window isn't attached yet on the first pass
    DispatchQueue.main.async {
      guard let w = v.window else { return }
      w.isOpaque = !clear
      w.backgroundColor = clear ? .clear : NSColor(paper)
      setBlur(w, clear ? blur : 0)
    }
  }
}

/// Blurs the desktop behind the window. There's no public API for this, so
/// like Ghostty, iTerm2 and Alacritty we call the window server's private
/// CGSSetWindowBackgroundBlurRadius. It's looked up at run time, so if a
/// future macOS drops it we just get no blur.
func setBlur(_ w: NSWindow, _ radius: Double) {
  typealias MainConnectionID = @convention(c) () -> UInt32
  typealias SetBlurRadius = @convention(c) (UInt32, UInt32, UInt32) -> Int32
  let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
  guard w.windowNumber > 0,
    let connSym = dlsym(rtldDefault, "CGSMainConnectionID"),
    let blurSym = dlsym(rtldDefault, "CGSSetWindowBackgroundBlurRadius")
  else { return }
  let conn = unsafeBitCast(connSym, to: MainConnectionID.self)()
  let setBlurRadius = unsafeBitCast(blurSym, to: SetBlurRadius.self)
  _ = setBlurRadius(conn, UInt32(w.windowNumber), UInt32(max(0, radius)))
}
