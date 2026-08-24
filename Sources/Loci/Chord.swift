import Carbon.HIToolbox
import Foundation

/// The key combination that summons the grid, read from `LOCI_HOTKEY`.
///
/// It is configurable because a global hotkey is taken from the whole machine,
/// not shared with it: Carbon registers ahead of every application menu, so
/// while Loci runs, its chord stops reaching whatever used to answer it. The
/// default is Cmd+E, and Cmd+E means Eject in the Finder and Use Selection for
/// Find in half the editors. Being able to move it by exporting a variable is
/// cheaper than finding out mid rebuild.
struct Chord {
  let keyCode: UInt32
  let modifiers: UInt32
  let label: String

  static var configured: Chord {
    let text = ProcessInfo.processInfo.environment["LOCI_HOTKEY"] ?? "cmd+e"
    guard let chord = parse(text) else {
      Log.say("LOCI_HOTKEY=\(text) is not a chord I understand, using cmd E")
      return parse("cmd+e")!
    }
    return chord
  }

  /// `cmd+e`, `ctrl+opt+space`, `shift+cmd+1`. Modifiers first, one key last.
  static func parse(_ text: String) -> Chord? {
    let parts = text.lowercased().split(separator: "+").map(String.init)
    guard let key = parts.last, let code = keys[key] else { return nil }

    var modifiers: UInt32 = 0
    var names: [String] = []
    for part in parts.dropLast() {
      switch part {
      case "cmd", "command": modifiers |= UInt32(cmdKey); names.append("cmd")
      case "ctrl", "control": modifiers |= UInt32(controlKey); names.append("ctrl")
      case "opt", "option", "alt": modifiers |= UInt32(optionKey); names.append("option")
      case "shift": modifiers |= UInt32(shiftKey); names.append("shift")
      default: return nil
      }
    }
    // A chord with no modifier would take a plain key away from every
    // application on the machine, which is not a thing I want to be one typo
    // away from.
    guard modifiers != 0 else { return nil }

    return Chord(
      keyCode: code,
      modifiers: modifiers,
      label: (names + [key.count == 1 ? key.uppercased() : key]).joined(separator: " "))
  }

  private static let keys: [String: UInt32] = [
    "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
    "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
    "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
    "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
    "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
    "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
    "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
    "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
    "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
    "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2), "3": UInt32(kVK_ANSI_3),
    "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5), "6": UInt32(kVK_ANSI_6),
    "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8), "9": UInt32(kVK_ANSI_9),
    "0": UInt32(kVK_ANSI_0),
    "space": UInt32(kVK_Space), "tab": UInt32(kVK_Tab), "return": UInt32(kVK_Return),
  ]
}
