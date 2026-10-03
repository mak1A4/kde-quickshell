# Decisions

Short notes on non-obvious KDE/Wayland choices. Evidence is in `phase0-findings.md`.

## Layer shell is allowed

`zwlr_layer_shell_v1` has a wlroots name but KWin implements it (v5). Quickshell's
`PanelWindow` depends on it and is fine. The "no wlroots-only modules" rule targets
protocols KWin lacks: foreign-toplevel, session-lock, screencopy.

## Window list comes from `org.kde.taskmanager`, imported directly

No C++ wrapper needed; the module loads from the system QML path. It ships with
plasma-workspace and has no API stability promise, so re-test after Plasma upgrades.
Quickshell's own `ToplevelManager` is not an option (KWin has no foreign-toplevel).

## Privileged protocols are granted by desktop entry, matched on executable path

`packaging/kde-quickshell.desktop` carries `X-KDE-Wayland-Interfaces`. KWin compares
`Exec=` with the client's real executable, so the grant applies to `/usr/bin/quickshell`
whatever config it runs and however it was started. Future restricted D-Bus interfaces
(`ScreenShot2`) go in the same file as `X-KDE-DBUS-Restricted-Interfaces`.

## Virtual desktops: Wayland protocol for state, D-Bus for switching

`VirtualDesktopInfo` (from `org.kde.taskmanager`) gives ids, names and the current
desktop reactively, with no grant. It has no activate call in QML, so switching runs
`busctl set-property ... current`. One-shot `busctl` calls are fine; the Phase 0
`busctl monitor` approach is gone.

## D-Bus from QML goes through `busctl`

Quickshell has no generic D-Bus client. One-shot calls use `Quickshell.execDetached`.
For state, prefer a Quickshell service or KDE QML module; if neither exists, run one
`busctl monitor` process and re-read properties with `--json=short` on change (worked in
Phase 0). Anything chatty should move to a C++ plugin.

## Icons come from the system theme via Kirigami.Icon

`widgets/Icon.qml` wraps `Kirigami.Icon` with `isMask`, so symbolic icons take the bar's
foreground colour instead of the Plasma colour scheme's. It also accepts the `QIcon`
from `TasksModel.decoration`, which plain `Image` cannot. Kirigami is a hard dependency;
on Plasma it is always present. Tray icons are pixmaps and use Quickshell's `IconImage`.

## QApplication for tray menus

`//@ pragma UseQApplication` in `shell.qml` lets `QsMenuAnchor` show tray menus as native
Breeze menus. Custom-drawn menus (`QsMenuOpener`) are a Phase 2 option.

## Quickshell service singletons are lazy

`SystemTray`, `Mpris`, `Networking`, `UPower` start their D-Bus queries on first access
and fill in asynchronously. Read them through bindings; an imperative read right after
first touch sees empty lists.

## Empty desktop vs. no window access

The taskbar keeps a second, unfiltered `TasksModel` purely for its count. Zero windows on
the current desktop shows nothing; zero windows anywhere shows the "or KWin denied" hint.

## QML naming trap

A property named `onSomething` is parsed as a signal handler. Hence `accentFg`.

## The audio mixer uses plasma-pa's models, the bar pill uses Quickshell's PipeWire

Quickshell's PipeWire service has no port availability, so it lists every node (here 4
outputs, 3 inputs). Plasma hides devices whose only port is unplugged (3 and 1).
`org.kde.plasma.private.volume` (plasma-pa) loads in Quickshell and brings the same
filter model, level meters and `plasmaparc` settings the Plasma applet uses, so
"raise maximum volume" is shared with Plasma. It is private API tied to the Plasma
version, hence behind `Guarded`. The pill stays on Quickshell's service so it keeps
working if that module ever breaks. Both use the same volume scale.

Not ported: per-device port/profile menus, the microphone test, pinning.

## Power & Battery uses PowerDevil's QML modules

`org.kde.plasma.private.batterymonitor` (`PowerProfilesControl`, `InhibitionControl`) and
`org.kde.plasma.private.battery` (`BatteryControlModel`) load in Quickshell and are what
Plasma's applet uses, so profile changes, peripheral batteries and sleep/lock blocking
behave identically. Quickshell's UPower service could do profiles and batteries but has
nothing for inhibitions, and one backend per panel is simpler. Private API, so the whole
pill is behind `Guarded`; this replaced the Phase 1 UPower battery pill.

The control objects live in the pill, not the popup: the pill shows their state. A manual
block is daemon-side state anyway (it survives the object that requested it).

`PowerProfilesControl.setProfile` takes the profile name; the type info misnames its
parameter "reason". Breeze has no `power-profile-*` icons; the applet's are
`battery-profile-{powersave,balanced,performance}-symbolic`.

Not ported: brightness, the lid-action hint, remaining-time display.

## Popups have a fixed size

Resizing a mapped `PopupWindow` at fractional scale leaves the old buffer stretched to
the new size and stale (Quickshell 0.3.1, Qt 6.11). Popups get a constant size and
scroll their content, as Plasma's applets do. Content is created only while the popup is
open (`Guarded.active`).

## `grabFocus` popups can only be opened from real input

A grabbing xdg_popup needs an input serial. Opening one from a timer or at startup fails
with "Failed to create grabbing popup". Matters for future IPC/shortcut-triggered popups.

## Quickshell only registers directories that something imports

A file loaded by URL (`Loader`) cannot see its sibling files unless a file in an already
registered directory has `import qs.<that.dir>`. Hence the otherwise unused
`import qs.modules.audio` in `modules/Audio.qml`. The importing file may itself be
URL-loaded (`modules/Power.qml` importing `qs.modules.power` works), as long as its own
directory is registered.

## Sizes are multiples of 3 logical px

At scale 1.333, 3 logical px = 4 device px. Other sizes put edges between pixels.
`screen.devicePixelRatio` reports 2 here and must not be used for this.

Centre anchors snap to whole logical pixels by default, which undoes this for odd
offsets (a 9 px dot in an 18 px ring sits at 4.5). Set `anchors.alignWhenCentered: false`
where the half-pixel offset is intended.

## Optional KDE modules are loaded through `Loader`

A failed `import` kills the whole file. Widgets that import KDE modules live in their own
file behind a `Loader`, with a visible error label on `Loader.Error`.
