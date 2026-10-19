import AppKit

/// The name of a display, as macOS calls it, and which one I am working on.
///
/// The window server identifies displays by UUID, which says nothing to anyone.
/// `NSScreen` knows the name on the box (Built-in Retina Display, Studio
/// Display), and the two are joined through the display ID.
@MainActor
enum Screens {
  static func name(for identifier: String) -> String? {
    // The preference domain, which is the fallback source, calls the main one
    // Main rather than giving it a UUID.
    if identifier == "Main" { return "Main display" }
    return screen(for: identifier)?.localizedName
  }

  static func screen(for identifier: String) -> NSScreen? {
    NSScreen.screens.first { self.identifier(of: $0) == identifier }
  }

  /// The display my keyboard is on, as a window server display UUID.
  ///
  /// There is no call that answers this. `CGSGetActiveSpace` sounds like it
  /// does and does not: it names the main display's desktop whichever screen I
  /// am typing on, so on a second monitor it is always one screen behind.
  ///
  /// What is true is that the focused window of the frontmost application is
  /// where the keystrokes are going, so the screen that window sits on is the
  /// screen I am on. `NSScreen.main` is the fallback, for a frontmost
  /// application with no window at all.
  static func focused() -> String? {
    guard
      let screen = focusedWindowCentre().flatMap({ point in
        NSScreen.screens.first { $0.frame.contains(point) }
      }) ?? NSScreen.main
    else { return nil }
    return identifier(of: screen)
  }

  static func identifier(of screen: NSScreen) -> String? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")
    guard let number = screen.deviceDescription[key] as? NSNumber,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
  }

  /// Accessibility measures windows from the top left of the main display and
  /// downwards; `NSScreen` measures from the bottom left and upwards. The one
  /// number that converts between them is the height of the main display, and
  /// the main display is the one whose frame starts at the origin.
  private static func focusedWindowCentre() -> CGPoint? {
    guard AXIsProcessTrusted(),
      let application = NSWorkspace.shared.frontmostApplication,
      let window = focusedWindow(of: application.processIdentifier),
      let origin: CGPoint = value(of: window, kAXPositionAttribute, .cgPoint),
      let size: CGSize = value(of: window, kAXSizeAttribute, .cgSize),
      let main = NSScreen.screens.first(where: { $0.frame.origin == .zero })
    else { return nil }
    return CGPoint(
      x: origin.x + size.width / 2,
      y: main.frame.maxY - (origin.y + size.height / 2))
  }

  private static func focusedWindow(of pid: pid_t) -> AXUIElement? {
    var window: CFTypeRef?
    let application = AXUIElementCreateApplication(pid)
    guard
      AXUIElementCopyAttributeValue(
        application, kAXFocusedWindowAttribute as CFString, &window) == .success,
      let window, CFGetTypeID(window) == AXUIElementGetTypeID()
    else { return nil }
    return (window as! AXUIElement)
  }

  private static func value<T>(
    of element: AXUIElement, _ attribute: String, _ type: AXValueType
  ) -> T? {
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
      let raw, CFGetTypeID(raw) == AXValueGetTypeID()
    else { return nil }
    let result = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { result.deallocate() }
    guard AXValueGetValue((raw as! AXValue), type, result) else { return nil }
    return result.pointee
  }
}
