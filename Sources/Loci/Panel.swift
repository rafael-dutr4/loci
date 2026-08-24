import AppKit
import SwiftUI

/// The grid, floating over whatever I am doing.
///
/// This is the whole point of Loci. Mission Control already draws a row of
/// desktops and refuses to let me label them, so Loci draws its own row and the
/// labels are the only reason it exists.
///
/// It is an `NSPanel` and not a window for two reasons. It joins every space,
/// so summoning it on desktop 4 shows the same grid it shows on desktop 1. And
/// it is non activating, so the application I was working in keeps its focus
/// while the grid is up, which matters because switching desktops with the
/// grid open should land me back in that application.
@MainActor
final class Panel {
  private var window: OverlayPanel?
  private var keys: Any?

  var isVisible: Bool { window?.isVisible ?? false }

  func toggle(_ content: Content) {
    isVisible ? hide() : show(content)
  }

  struct Content {
    let displays: [Spaces.Display]
    let name: (Spaces.Space) -> String
    let hint: String?
    let onPick: (Spaces.Space) -> Void
    let onRename: (Spaces.Space) -> Void
  }

  func show(_ content: Content) {
    hide()

    let view = Grid(
      displays: content.displays,
      name: content.name,
      hint: content.hint,
      onPick: { [weak self] space in
        self?.hide()
        content.onPick(space)
      },
      onRename: { [weak self] space in
        self?.hide()
        content.onRename(space)
      })

    let hosting = FirstMouseHostingView(rootView: view)
    hosting.frame.size = hosting.fittingSize

    let panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false)
    panel.contentView = hosting
    panel.isFloatingPanel = true
    // Above the menu bar and above a full screen window, because the grid is
    // useless if the thing I want to leave can cover it.
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    // The grid is drawn over another application, which keeps its focus. The
    // mouse has to be tracked anyway, or the cards cannot light up under the
    // pointer.
    panel.acceptsMouseMovedEvents = true
    panel.ignoresMouseEvents = false
    panel.setFrame(frame(for: hosting.fittingSize), display: true)
    panel.makeKeyAndOrderFront(nil)
    window = panel

    // A number goes to that desktop and Escape gives up. The panel is key, so
    // these arrive here and not in the application underneath, which is why
    // they are swallowed rather than passed on.
    keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.isVisible else { return event }
      if event.keyCode == 53 {
        self.hide()
        return nil
      }
      if let digit = Int(event.charactersIgnoringModifiers ?? ""), digit >= 1 {
        let spaces = content.displays.flatMap(\.spaces)
        if let space = spaces.first(where: { $0.index == digit }) {
          self.hide()
          content.onPick(space)
          return nil
        }
      }
      return event
    }
  }

  func hide() {
    if let keys { NSEvent.removeMonitor(keys) }
    keys = nil
    window?.orderOut(nil)
    window = nil
  }

  /// On the screen the mouse is on, a little above centre. Not on the main
  /// screen: the grid should appear where I am looking, and where the pointer
  /// is is the only cheap guess at that.
  private func frame(for size: NSSize) -> NSRect {
    let mouse = NSEvent.mouseLocation
    let screen =
      NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    let area = screen.visibleFrame
    return NSRect(
      x: area.midX - size.width / 2,
      y: area.midY - size.height / 2 + area.height * 0.08,
      width: size.width,
      height: size.height)
  }
}

/// A borderless panel refuses to become key by default, and then the number
/// keys go to whatever is behind it.
final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

private struct Grid: View {
  let displays: [Spaces.Display]
  let name: (Spaces.Space) -> String
  let hint: String?
  let onPick: (Spaces.Space) -> Void
  let onRename: (Spaces.Space) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
        VStack(alignment: .leading, spacing: 10) {
          if displays.count > 1 {
            Text(label(for: display))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          HStack(spacing: 14) {
            ForEach(display.spaces, id: \.uuid) { space in
              Card(space: space, name: name(space), onPick: { onPick(space) })
                .contextMenu {
                  Button("Rename...") { onRename(space) }
                }
            }
          }
        }
      }

      if let hint {
        Text(hint)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(22)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(.ultraThinMaterial))
  }

  /// The identifier of a display is a UUID, which says nothing to me. The main
  /// one calls itself Main, and the others are told apart by position on the
  /// screen, so the first few characters are enough to see they are different.
  private func label(for display: Spaces.Display) -> String {
    display.identifier == "Main" ? "Main display" : "Display \(display.identifier.prefix(8))"
  }
}

private struct Card: View {
  let space: Spaces.Space
  let name: String
  let onPick: () -> Void

  @State private var hovering = false

  var body: some View {
    VStack(spacing: 8) {
      ZStack {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.black.opacity(hovering ? 0.14 : 0.28))

        if space.apps.isEmpty {
          Text("empty")
            .font(.caption)
            .foregroundStyle(.tertiary)
        } else {
          HStack(spacing: 6) {
            ForEach(space.apps.prefix(5), id: \.self) { bundle in
              if let icon = Icons.icon(for: bundle) {
                Image(nsImage: icon)
                  .resizable()
                  .frame(width: 30, height: 30)
              }
            }
          }
        }
      }
      .frame(width: 168, height: 104)
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(border, lineWidth: space.isCurrent ? 3 : 1))

      HStack(spacing: 6) {
        Text("\(space.index)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        Text(name)
          .font(.system(size: 13, weight: space.isCurrent ? .semibold : .regular))
          .lineLimit(1)
      }
      .frame(width: 168)
    }
    // The whole card, icons and label together, is the target. Anything less
    // means aiming at a thumbnail.
    .contentShape(Rectangle())
    .scaleEffect(hovering ? 1.03 : 1)
    .animation(.easeOut(duration: 0.12), value: hovering)
    .onHover { hovering = $0 }
    // A plain gesture and not a Button, because a Button in a panel that never
    // takes focus draws itself pressed and answers on the second click.
    .onTapGesture(perform: onPick)
  }

  /// The current desktop keeps its outline whatever the pointer is doing. It
  /// answers a different question (where am I) from the hover (where would this
  /// click take me), so one is not allowed to hide the other.
  private var border: Color {
    if space.isCurrent { return .accentColor }
    return hovering ? Color.white.opacity(0.55) : Color.white.opacity(0.18)
  }
}

/// A window that is not key swallows the click that makes it key, so the first
/// click on a card would only wake the panel and the second would pick the
/// desktop. Loci is summoned by a hotkey over an application that keeps its
/// focus, so that first click is the only click there is.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  required init(rootView: Content) {
    super.init(rootView: rootView)
  }

  @MainActor required dynamic init?(coder: NSCoder) {
    fatalError("Loci builds its views in code")
  }
}

/// Icons come from the bundle identifier, so an application that is not running
/// still has a face. Cached because the grid is redrawn on every summon and
/// looking an application up on disk is a file system walk.
@MainActor
enum Icons {
  private static var cache: [String: NSImage] = [:]

  static func icon(for bundle: String) -> NSImage? {
    if let hit = cache[bundle] { return hit }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: url.path)
    cache[bundle] = icon
    return icon
  }
}
