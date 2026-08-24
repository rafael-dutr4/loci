import AppKit

/// The name of a display, as macOS calls it.
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
    for screen in NSScreen.screens {
      let key = NSDeviceDescriptionKey("NSScreenNumber")
      guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
      guard let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
      else { continue }
      if CFUUIDCreateString(nil, uuid) as String == identifier {
        return screen
      }
    }
    return nil
  }
}
