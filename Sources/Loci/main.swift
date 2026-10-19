import AppKit
import Carbon.HIToolbox

@MainActor
final class Loci: NSObject, NSApplicationDelegate {
  private let names = Names()
  private let panel = Panel()
  private var hotkey: Hotkey?
  private var statusItem: NSStatusItem!
  private var displays: [Spaces.Display] = []
  private let chord = Chord.configured

  func applicationDidFinishLaunching(_ notification: Notification) {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.menu = menu()

    // The layout changes when I switch desktop, and also when I add or remove
    // one, which arrives as the same notification. So the answer to both is to
    // read it again rather than to keep a model up to date.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }

    // Clicking into a window on the other monitor moves my keyboard there
    // without changing any desktop, so no space notification comes: the menu
    // bar would keep naming the desktop on the screen I just left.
    //
    // The grid is left alone here. Clicking a card counts as activating Loci,
    // and redrawing the grid between the press and the release throws the
    // click away, which is the panel refusing to switch desktops at all.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh(redrawing: false) }
    }

    // A display coming or going rearranges the desktops without any of them
    // becoming active, so the space notification never fires for it.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.refresh() }
    }

    // Asked at launch rather than on the first click, because the dialog is
    // modal and a permission prompt in the middle of switching desktops is the
    // opposite of what the panel is for.
    Switcher.requestAccessibility()
    // Said out loud because without it every click on a card does nothing, and
    // the grant is per binary, so a rebuild can quietly drop it.
    Log.say(
      AXIsProcessTrusted()
        ? "accessibility granted, so clicks and Ctrl+N will land"
        : "no accessibility: tick Loci in Privacy & Security > Accessibility")

    do {
      hotkey = try Hotkey(keyCode: chord.keyCode, modifiers: chord.modifiers) { [weak self] in
        self?.toggle()
      }
    } catch {
      Log.say("loci: \(error.localizedDescription)")
    }

    refresh()
    Log.say("\(displays.count) displays, \(displays.flatMap(\.spaces).count) desktops")
    // Worth saying out loud: this chord is now taken from every application on
    // the machine, not shared with them.
    Log.say("summoned with \(chord.label), change it with LOCI_HOTKEY")
    if CommandLine.arguments.contains("--panel") { show() }
  }

  /// Reading is cheap and the truth is one call away, so nothing is cached
  /// between summons. The only state Loci owns is the names.
  private func refresh(redrawing: Bool = true) {
    displays = Spaces.read()
    let name = current.map { title(for: $0) } ?? "Loci"
    if statusItem.button?.title != name { Log.say("now on \(name)") }
    statusItem.button?.title = name
    statusItem.menu = menu()
    if redrawing, panel.isVisible { show() }
  }

  /// Each display has its own current desktop, so there is no single current
  /// one. The one that counts is the one on the display my keyboard is on, and
  /// that is the one the menu bar names. The first display is only the
  /// fallback, for when the focused display cannot be worked out at all.
  private var current: Spaces.Space? {
    let spaces = displays.flatMap(\.spaces)
    return spaces.first(where: \.isActive) ?? displays.first?.spaces.first(where: \.isCurrent)
  }

  private func title(for space: Spaces.Space) -> String {
    names.name(for: space.uuid) ?? (space.isFullScreen ? "Full screen" : "Desktop \(space.index)")
  }

  /// The same chord opens and closes it. A hotkey that only opens leaves me
  /// pressing Escape to undo something I did with one key.
  private func toggle() {
    panel.isVisible ? panel.hide() : show()
  }

  private func show() {
    displays = Spaces.read()
    panel.show(
      Panel.Content(
        displays: displays,
        name: { [weak self] space in self?.title(for: space) ?? "" },
        hint: hint,
        onPick: { space in Switcher.go(to: space.index) },
        onRename: { [weak self] space in self?.rename(space) }))
  }

  /// The desktops a click would do nothing on. The shortcuts are written once,
  /// for the desktops that existed at the time, so adding a seventh desktop
  /// later leaves a card with no Ctrl+7 behind it. Anything past nine is out of
  /// reach for good and is not counted here.
  private var unreachable: [Spaces.Space] {
    displays.flatMap(\.spaces).filter { $0.index <= 9 && !Switcher.canSwitch(to: $0.index) }
  }

  /// Only shown when a click would do nothing. Ctrl+N ships disabled, and a
  /// grid that silently ignores half of my clicks is worse than no grid.
  private var hint: String? {
    let reachable = displays.flatMap(\.spaces).filter { $0.index <= 9 }
    guard !reachable.isEmpty else { return nil }
    if !AXIsProcessTrusted() {
      return "Switching needs Loci ticked in Privacy & Security > Accessibility."
    }
    let missing = unreachable
    guard !missing.isEmpty else { return nil }
    if missing.count == reachable.count {
      return "Switching needs Mission Control's Ctrl+number shortcuts turned on."
    }
    // Naming them, because the rest of the grid works and the broken ones are
    // the ones I just made.
    let numbers = missing.map { "\($0.index)" }.joined(separator: ", ")
    let plural = missing.count == 1 ? "Desktop \(numbers) has" : "Desktops \(numbers) have"
    return "\(plural) no Ctrl+number shortcut yet: turn it on from the Loci menu."
  }

  private func rename(_ space: Spaces.Space) {
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Name desktop \(space.index)"
    alert.informativeText = "An empty name gives the number back."
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
    field.stringValue = names.name(for: space.uuid) ?? ""
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    alert.window.initialFirstResponder = field

    if alert.runModal() == .alertFirstButtonReturn {
      names.set(field.stringValue, for: space.uuid)
      refresh()
    }
  }

  private func menu() -> NSMenu {
    let menu = NSMenu()
    menu.addItem(
      withTitle: "Show desktops (\(chord.label))", action: #selector(showFromMenu),
      keyEquivalent: ""
    ).target = self
    if current != nil {
      menu.addItem(
        withTitle: "Rename this desktop...", action: #selector(renameCurrent),
        keyEquivalent: ""
      ).target = self
    }
    menu.addItem(.separator())
    // Only offered while it would change something, which includes the case of
    // desktops added after the shortcuts were written. Once every desktop has
    // one, the honest place to edit them is System Settings.
    if !unreachable.isEmpty {
      menu.addItem(
        withTitle: "Turn on Ctrl+number switching", action: #selector(turnOnSwitching),
        keyEquivalent: ""
      ).target = self
    }
    menu.addItem(
      withTitle: "Desktop shortcuts...", action: #selector(openShortcuts), keyEquivalent: ""
    ).target = self
    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    return menu
  }

  @objc private func showFromMenu() { show() }

  @objc private func renameCurrent() {
    guard let space = current else { return }
    rename(space)
  }

  @objc private func turnOnSwitching() {
    Shortcuts.enableDesktopSwitching(upTo: displays.flatMap(\.spaces).count)
    refresh()
  }

  @objc private func openShortcuts() { Switcher.openShortcutSettings() }
}

let app = NSApplication.shared
let delegate = Loci()
app.delegate = delegate
// No dock icon. The menu bar and the panel are the whole interface.
app.setActivationPolicy(.accessory)
app.run()
