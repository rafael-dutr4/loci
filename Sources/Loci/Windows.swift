import AppKit

/// What is actually on each desktop.
///
/// The layout carries a `WindowManagerInfo` that looks like the answer and is
/// not. It is Stage Manager's grouping, so it holds the windows that happen to
/// be in a set and nothing else: it called a desktop empty while Chrome, the
/// calendar and a virtual machine were sitting on it.
///
/// The real answer is the window list, which includes windows on desktops that
/// are not being drawn, plus one private call that says which desktop each
/// window is on. Only metadata is read, never an image and never a title, so
/// none of this asks for Screen Recording.
@MainActor
enum Windows {
  private typealias SpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

  /// Bundle identifiers per space, biggest window first, so the icon that shows
  /// up on a card is the application taking up the desktop rather than whatever
  /// happened to be enumerated first.
  static func bySpace() -> [Int: [String]]? {
    guard let connection = Spaces.connection(),
      let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSCopySpacesForWindows")
    else { return nil }
    let spacesForWindows = unsafeBitCast(symbol, to: SpacesForWindowsFn.self)

    let list =
      CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] ?? []

    var apps: [pid_t: String?] = [:]
    var area: [Int: [String: Double]] = [:]

    for window in list {
      guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
        let number = window[kCGWindowNumber as String] as? Int,
        let pid = window[kCGWindowOwnerPID as String] as? pid_t
      else { continue }

      // Anything that is allowed a user interface. Requiring a dock icon was
      // the first rule and it was too strict: it dropped a virtual machine
      // sitting in a full sized window because the application it belongs to
      // lives in the menu bar. The services and helpers that this lets in are
      // dropped by the space test below, because they own windows that are on
      // no desktop at all.
      let bundle = apps[pid] ?? {
        let running = NSRunningApplication(processIdentifier: pid)
        let identifier = running?.activationPolicy != .prohibited ? running?.bundleIdentifier : nil
        apps[pid] = identifier
        return identifier
      }()
      guard let bundle else { continue }

      // Stage Manager is drawing other people's windows, so its own windows
      // would put its icon on every card.
      guard bundle != "com.apple.WindowManager" else { continue }

      let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
      let width = bounds["Width"] ?? 0
      let height = bounds["Height"] ?? 0
      // The menu bar and its extras are windows too, one per screen, and they
      // are the shape of a ruler.
      guard height > 50 else { continue }

      // A window with no space is not on a desktop at all: an offscreen helper,
      // a panel that has never been shown, something being torn down. A window
      // on many is on all of them, and says nothing about any one.
      guard let ids = spacesForWindows(connection, 7, [number] as CFArray)?.takeRetainedValue()
        as? [Int], ids.count == 1, let space = ids.first
      else { continue }

      area[space, default: [:]][bundle] = max(area[space]?[bundle] ?? 0, width * height)
    }

    return area.mapValues { sizes in
      sizes.sorted { $0.value > $1.value }.map(\.key)
    }
  }
}
