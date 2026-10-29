import Foundation
import Playgrounds
import SwiftUI
#if os(macOS)
import AppKit
#endif

@main struct MyApp: App {
  @State private var store: Store

  init() {
    registerFonts()  // before Store reads the font setting
    _store = State(initialValue: Store())
  }

  #if os(iOS)
  var body: some Scene {
    WindowGroup { PhoneView().environment(store) }
  }
  #else
  var body: some Scene {
    WindowGroup {
      ContentView().environment(store)
    }
    .defaultSize(width: 1100, height: 760)
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
      CommandGroup(replacing: .appSettings) { SettingsButton() }
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
    // A plain Window rather than a Settings scene, so it can drop its title bar.
    Window("Settings", id: "settings") { SettingsView().environment(store) }
      .windowStyle(.hiddenTitleBar)
      .windowResizability(.contentSize)
  }
  #endif
}

#if os(macOS)

/// Makes the window see-through (clear) with the desktop behind blurred.
/// SwiftUI has no API for either; the title bar is left to .windowStyle.
struct WindowGlass: NSViewRepresentable {
  var clear: Bool
  var blur: Double
  var paper: Color
  var buttons = true  // the close, minimise and zoom buttons

  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ v: NSView, context: Context) {
    // the window isn't attached yet on the first pass
    DispatchQueue.main.async {
      guard let w = v.window else { return }
      for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
        w.standardWindowButton(b)?.isHidden = !buttons
      }
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

/// Opens the settings window (⌘,).
struct SettingsButton: View {
  @Environment(\.openWindow) var openWindow
  var body: some View { Button("Settings…") { openWindow(id: "settings") }.keyboardShortcut(",") }
}
#endif
