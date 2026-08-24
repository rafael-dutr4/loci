import Foundation

/// My names for the desktops, in one JSON file keyed by the space uuid.
///
/// The uuid is the whole reason this works. It survives a reboot and it
/// survives dragging the desktops around in Mission Control, so a name follows
/// the desktop it was given to instead of following the position that desktop
/// happened to be in when I typed it.
@MainActor
final class Names {
  private var names: [String: String] = [:]
  private let file = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: ".config/loci/names.json")

  init() {
    guard let data = try? Data(contentsOf: file),
      let stored = try? JSONDecoder().decode([String: String].self, from: data)
    else { return }
    names = stored
    Log.say("\(names.count) names read from \(file.path)")
  }

  func name(for uuid: String) -> String? {
    names[uuid]
  }

  /// An empty name is not a name, it is a way of asking for the number back.
  func set(_ name: String, for uuid: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      names.removeValue(forKey: uuid)
    } else {
      names[uuid] = trimmed
    }
    save()
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      try encoder.encode(names).write(to: file, options: .atomic)
    } catch {
      Log.say("could not write \(file.path): \(error.localizedDescription)")
    }
  }
}
