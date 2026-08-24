import Carbon.HIToolbox
import Foundation

enum LociError: LocalizedError {
  case hotkeyFailed(OSStatus)
  case hotkeyTaken(OSStatus)

  var errorDescription: String? {
    switch self {
    case .hotkeyFailed(let status):
      return "the hotkey handler could not be installed (\(status))"
    case .hotkeyTaken(let status):
      return "the hotkey is already registered by something else (\(status))"
    }
  }
}

/// One system wide hotkey.
///
/// The old Carbon API, deprecated, and still the only way to ask the system for
/// one key combination. The alternative is an event tap, which means watching
/// every keystroke on the machine in order to notice a single chord. Same trade
/// as in Cadmus, same answer: the smaller permission wins.
final class Hotkey {
  private var ref: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: () -> Void

  /// Carbon calls back into C, which carries no context, so the instance is
  /// parked here for the callback to find. Unchecked because the handler is
  /// installed on the application event target, so it is only ever touched by
  /// the run loop that owns it.
  nonisolated(unsafe) private static var current: Hotkey?

  init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) throws {
    self.action = action
    Hotkey.current = self

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let installed = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        Hotkey.current?.action()
        return noErr
      },
      1,
      &spec,
      nil,
      &handler
    )
    guard installed == noErr else { throw LociError.hotkeyFailed(installed) }

    let id = EventHotKeyID(signature: OSType(0x4C4F_4349), id: 1)  // 'LOCI'
    let registered = RegisterEventHotKey(
      keyCode,
      modifiers,
      id,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    guard registered == noErr else { throw LociError.hotkeyTaken(registered) }
  }

  deinit {
    if let ref { UnregisterEventHotKey(ref) }
    if let handler { RemoveEventHandler(handler) }
  }
}
