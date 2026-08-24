import Foundation

/// Turning on the shortcuts Loci presses.
///
/// A fresh Mac has no Ctrl+number at all. Not disabled entries, no entries: the
/// domain is empty until something writes it, which is why a click on a card
/// did nothing and why nothing complained. Loci posted Ctrl+3 and the system
/// had no Ctrl+3 to answer.
///
/// This writes them, and it is a menu item and never something that happens at
/// launch. It is a system wide keyboard setting, and an application that
/// rebinds Ctrl+1 on my machine because it felt like it is an application I
/// would delete.
enum Shortcuts {
  private static let domain = "com.apple.symbolichotkeys"
  private static let key = "AppleSymbolicHotKeys"

  /// The Mission Control entries start at 118 for Desktop 1 and run one per
  /// desktop. The value is what the settings pane itself writes: the character,
  /// its key code, and the modifier mask (262144 is Control).
  static func enableDesktopSwitching(upTo count: Int) {
    guard let defaults = UserDefaults(suiteName: domain) else { return }
    var all = defaults.dictionary(forKey: key) ?? [:]

    let codes = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    for index in 1...min(count, codes.count) {
      let ascii = 48 + index  // '1' is 49
      all["\(117 + index)"] = [
        "enabled": true,
        "value": [
          "type": "standard",
          "parameters": [ascii, codes[index - 1], 262144],
        ],
      ]
    }

    defaults.set(all, forKey: key)
    defaults.synchronize()
    activate()
    Log.say("wrote Ctrl+1 to Ctrl+\(min(count, codes.count)) into \(domain)")
  }

  /// Written preferences are not live preferences. The window server reads the
  /// shortcuts once, so without this the change only arrives at the next login.
  private static func activate() {
    let tool = URL(
      filePath: "/System/Library/PrivateFrameworks/SystemAdministration.framework"
        + "/Resources/activateSettings")
    guard FileManager.default.isExecutableFile(atPath: tool.path) else {
      Log.say("no activateSettings on this system, the shortcuts arrive at the next login")
      return
    }
    let task = Process()
    task.executableURL = tool
    task.arguments = ["-u"]
    try? task.run()
    task.waitUntilExit()
  }
}
