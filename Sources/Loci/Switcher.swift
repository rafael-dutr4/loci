import AppKit
import Carbon.HIToolbox

/// Going to a desktop.
///
/// There is no public call for this, and the private ones (the CGS space
/// functions that yabai uses) want SIP turned off, which I am not doing for a
/// panel. What is left is the shortcut macOS already has: Ctrl+N selects the
/// Nth desktop, so Loci presses it.
///
/// The catch is that those shortcuts ship disabled. Loci checks instead of
/// guessing, because a click that silently does nothing is the worst possible
/// answer.
enum Switcher {
  /// Ctrl+1 through Ctrl+9. The number row is not contiguous in the keyboard
  /// map, which is why this is a table and not arithmetic.
  private static let digits: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]

  static func go(to index: Int) {
    guard index >= 1, index <= digits.count else {
      Log.say("desktop \(index) is out of reach: Ctrl+N only goes to nine")
      return
    }
    guard AXIsProcessTrusted() else {
      Log.say("no accessibility permission, so the keystroke would go nowhere")
      return
    }

    let key = digits[index - 1]
    let source = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    down?.flags = .maskControl
    up?.flags = .maskControl
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }

  /// Whether macOS will answer that keystroke.
  ///
  /// The Mission Control shortcuts live in `com.apple.symbolichotkeys`, one
  /// entry per desktop starting at 118. Absent means never touched, and never
  /// touched means off: a fresh Mac does not switch desktops by number.
  static func canSwitch(to index: Int) -> Bool {
    guard index >= 1, index <= digits.count else { return false }
    guard
      let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
        .persistentDomain(forName: "com.apple.symbolichotkeys")?["AppleSymbolicHotKeys"]
        as? [String: Any],
      let entry = hotkeys["\(117 + index)"] as? [String: Any]
    else { return false }
    return entry["enabled"] as? Bool ?? false
  }

  /// Loci does not write that preference itself. It is a system setting, it
  /// needs a restart of the window server bits to take effect, and a program
  /// that quietly rebinds Ctrl+1 on my machine is a program I would not trust.
  /// So it opens the panel and I tick the boxes.
  static func openShortcutSettings() {
    let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!
    NSWorkspace.shared.open(url)
  }

  static func requestAccessibility() {
    guard !AXIsProcessTrusted() else { return }
    // The constant for this key is a global var in C, which Swift 6 will not
    // let me touch across threads. Its value is the string, and the string is
    // never going to change.
    let options = ["AXTrustedCheckOptionPrompt": true]
    _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
  }
}
