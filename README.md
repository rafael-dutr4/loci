# Loci

macOS calls them Desktop 1 to Desktop 5. Loci lets you call them what they are.

It is a menu bar app that draws its own row of desktops over whatever you are
doing, with your names on them, and jumps to the one you click.

## What it does not do

It does not rename anything in Mission Control. That label is drawn by the Dock,
there is no public API for spaces, and the old trick of injecting a bundle into
the Dock died with SIP and library validation. Loci owns the name and draws its
own grid instead. Mission Control goes on saying Desktop 4 forever.

There are no thumbnails either. macOS only composites the desktop you are
looking at, so the windows on the others are not being drawn and no API can
photograph them. The cards show the icons of the applications living on each
desktop, which comes for free and answers the same question.

## What it touches

Worth knowing before you run something that talks to undocumented parts of the
system:

- **It reads through three private CGS functions**, found with `dlsym`:
  `_CGSDefaultConnection`, `CGSGetActiveSpace` and `CGSCopyManagedDisplaySpaces`.
  They only read. Nothing here needs SIP disabled. If a macOS release renames
  one, the lookup returns nil and Loci falls back to the public
  `com.apple.spaces` preference domain, which has the same shape and lags a beat.
- **It can write one system setting, and only when you ask it to.** macOS ships
  with no Ctrl+number shortcuts for switching desktops, so clicking a card would
  do nothing. The menu item "Turn on Ctrl+number switching" writes those entries
  into `com.apple.symbolichotkeys` and asks the system to reload them. It never
  happens at launch. Undo it in System Settings > Keyboard > Keyboard Shortcuts
  > Mission Control.
- **It asks for accessibility permission**, because switching desktops means
  posting a Ctrl+N keystroke and macOS does not let an application do that
  otherwise.
- **It registers one global hotkey**, which is taken from the machine and not
  shared with it: while Loci runs, its chord stops reaching every other
  application. The default is Cmd+E, which is Eject in the Finder. See below.
- **Nothing leaves the machine.** No network, no telemetry, no analytics. The
  only thing Loci writes is your names, in `~/.config/loci/names.json`.

## Using it

```bash
make run       # foreground, with the log
make start     # detached
make install   # at login
make stop
```

- **Cmd+E** shows the grid, **Esc** dismisses it, **1** to **9** jump.
- Click a card to go there. Right click one to name it.
- The menu bar shows the name of the desktop you are on.

The names are kept by space uuid, so they survive a reboot and survive dragging
the desktops around in Mission Control.

To move the hotkey, modifiers first and one key last:

```bash
LOCI_HOTKEY=ctrl+opt+space make start
```

It takes `cmd`, `ctrl`, `opt` and `shift`, plus a letter, a digit, `space`,
`tab` or `return`. A chord with no modifier is refused, because that would take
a plain key away from the whole machine.

## Limits

- Nine desktops. Ctrl+N does not go further, and that is the only public way to
  switch.
- The desktops are numbered across all displays, which is how Ctrl+N counts them.

## Requirements

macOS 26, Swift 6.2.
