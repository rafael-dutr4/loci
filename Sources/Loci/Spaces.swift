import Foundation

/// The desktops, and which one I am on.
///
/// There are two ways to ask, and Loci needs both.
///
/// The window server answers live, through three private CGS functions that
/// only read. That is where the layout comes from now, because the answer has
/// to be right at the moment I switch desktops and not a moment later.
///
/// The `com.apple.spaces` preference domain has the same shape and is public,
/// and it lags: it is the window server's record being written out, so a read
/// right after a switch still describes the desktop I just left. It is the
/// fallback, for the macOS release that renames a private symbol.
@MainActor
enum Spaces {
  struct Space {
    /// Stable across reboots and across reordering the desktops in Mission
    /// Control. This is what a name is allowed to hang on.
    let uuid: String
    /// The window server's own number for it, which is what the active space
    /// is reported as.
    let id: Int
    /// Position in Mission Control, counted across every display. This is also
    /// the number in Ctrl+N, which is why it is counted this way and not per
    /// display.
    let index: Int
    /// Current on its own display. With two displays, two desktops are.
    let isCurrent: Bool
    /// The one my keyboard is on. There is only ever one.
    let isActive: Bool
    let isFullScreen: Bool
    /// Bundle identifiers of what lives there, in no particular order.
    let apps: [String]
  }

  struct Display {
    let identifier: String
    let spaces: [Space]
  }

  static func read() -> [Display] {
    if let live = managedDisplaySpaces() {
      return parse(live)
    }
    guard let root = export(),
      let configuration = root["SpacesDisplayConfiguration"] as? [String: Any],
      let management = configuration["Management Data"] as? [String: Any],
      let monitors = management["Monitors"] as? [[String: Any]]
    else {
      Log.say("neither the window server nor com.apple.spaces answered")
      return []
    }
    Log.say("read the desktops from com.apple.spaces, so what is current may lag a beat")
    return parse(monitors)
  }

  private static func parse(_ monitors: [[String: Any]]) -> [Display] {
    let active = activeSpaceID
    let windows = Windows.bySpace()
    var index = 0
    var displays: [Display] = []
    for monitor in monitors {
      // The preference domain remembers every display this machine has ever
      // seen, and the ones that are not plugged in carry no desktops. They are
      // history, not a grid.
      guard let raw = monitor["Spaces"] as? [[String: Any]], !raw.isEmpty else { continue }

      let current = (monitor["Current Space"] as? [String: Any])?["uuid"] as? String
      var spaces: [Space] = []
      for space in raw {
        guard let uuid = space["uuid"] as? String else { continue }
        index += 1
        spaces.append(
          Space(
            uuid: uuid,
            id: space["ManagedSpaceID"] as? Int ?? 0,
            index: index,
            isCurrent: uuid == current,
            isActive: space["ManagedSpaceID"] as? Int == active,
            // Type 0 is a desktop I made. Anything else is a window that went
            // full screen and got a desktop of its own, which I did not name
            // and cannot keep.
            isFullScreen: (space["type"] as? Int ?? 0) != 0,
            // The window list is the truth about what lives on a desktop.
            // What the layout carries is Stage Manager's grouping, which is
            // most of the windows missing, and it is only used when the
            // private call behind the window list is not there.
            apps: windows?[space["ManagedSpaceID"] as? Int ?? 0] ?? apps(on: space)))
      }

      displays.append(
        Display(
          identifier: monitor["Display Identifier"] as? String ?? "unknown",
          spaces: spaces))
    }
    return displays
  }

  // MARK: the window server

  private typealias ConnectionFn = @convention(c) () -> Int32
  private typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64
  private typealias DisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

  /// Each display has its own current desktop, so "the current one" is only
  /// well defined as the one the window server considers active. That is the
  /// display I am working on, which is the one the menu bar should name.
  static var activeSpaceID: Int? {
    guard let connection = connection(),
      let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSGetActiveSpace")
    else { return nil }
    return Int(unsafeBitCast(symbol, to: ActiveSpaceFn.self)(connection))
  }

  static func connection() -> Int32? {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection")
    else { return nil }
    return unsafeBitCast(symbol, to: ConnectionFn.self)()
  }

  private static func managedDisplaySpaces() -> [[String: Any]]? {
    guard let connection = connection(),
      let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSCopyManagedDisplaySpaces")
    else { return nil }
    let array = unsafeBitCast(symbol, to: DisplaySpacesFn.self)(connection)
    return array?.takeRetainedValue() as? [[String: Any]]
  }

  // MARK: the preference domain

  /// Read through `defaults` rather than off the disk. The file in
  /// ~/Library/Preferences is not the truth, `cfprefsd` is.
  private static func export() -> [String: Any]? {
    let task = Process()
    task.executableURL = URL(filePath: "/usr/bin/defaults")
    task.arguments = ["export", "com.apple.spaces", "-"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
      try task.run()
    } catch {
      Log.say("could not run defaults: \(error.localizedDescription)")
      return nil
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    let object = try? PropertyListSerialization.propertyList(from: data, format: nil)
    return object as? [String: Any]
  }

  private static func apps(on space: [String: Any]) -> [String] {
    guard let info = space["WindowManagerInfo"] as? [String: Any],
      let sets = info["windowSets"] as? [String: [String]]
    else { return [] }

    var found: [String] = []
    for window in sets.values.flatMap({ $0 }) {
      let bundle = bundleIdentifier(of: window)
      guard !bundle.isEmpty, !found.contains(bundle) else { continue }
      found.append(bundle)
    }
    return found
  }

  /// A window is recorded as its bundle identifier glued to a UUID with a dash:
  /// `com.apple.Terminal-7FF360CD-5810-4347-95F0-4809B085F713`. A bundle
  /// identifier is allowed to contain dashes and a UUID is always exactly five
  /// groups, so the only rule that always holds is to drop five groups from the
  /// end.
  private static func bundleIdentifier(of window: String) -> String {
    let parts = window.split(separator: "-")
    guard parts.count > 5 else { return window }
    return parts.dropLast(5).joined(separator: "-")
  }
}
