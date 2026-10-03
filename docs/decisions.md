# Decisions

Short notes on non-obvious KDE/Wayland choices. Evidence is in `phase0-findings.md`.

## Layout: one full-screen frame surface (Caelestia-style)

`Frame.qml` is a single transparent layer surface covering the screen. It draws the
border with rounded inner corners, the vertical bar as the border's thick right side, and
every panel that grows out of them (dock, popouts). Panels are plain items in that one
surface, which is what makes the concave joins and the animations possible; separate
windows could not blend into the border.

- **Input:** the surface's input region is only the border ring plus open panels
  (`mask: Region`, Xor against the window). Verified in the protocol trace: four
  rectangles when idle. Everything else passes through to the windows underneath.
- **Reserved space:** a layer surface reserves on one edge only, and this one touches all
  four, so `Exclusions.qml` adds four invisible, input-less 1 px surfaces with the
  exclusive zones. Maximized windows end up exactly inside the border.
- **True fullscreen** windows cover the frame (KWin stacks them above the top layer).
  Accepted: the stated use is maximized windows.
- **Popouts** (audio, power) are opened by a bar button via the `Popouts` singleton,
  which carries the content `Component` so each module keeps its own backend objects.
  While one is open the click-through hole closes, so a click anywhere outside reaches
  the frame and dismisses it. No compositor grab is involved.
- **Dock:** hidden; the bottom border strip is the hover sensor (it is always in the
  input region), and the panel keeps itself open while hovered, with a 300 ms grace.
- **Hints:** anything hoverable exposes `hintTitle` / `hintLines` and reports hover to
  `Popouts.hover()`. The frame shows the hint as a small panel sliding out of the bar, or
  as a bubble above the dock for window icons. Hints are outside the input region and
  give way to an open popout. They are also how a compact `Guarded` error icon says what
  failed.
- **Tray menus** are still real popups (`MenuPopup`), opening to the left of the bar.

The frame's inner corners are only slightly rounded (`Theme.frameRounding: 7.5`, was 24):
the frame is drawn above windows, so its rounding covers the corners of every maximized
window. Panels keep their own, larger rounding (`Theme.panelRounding`).

If the frame ever swallows clicks: `pkill -x qs` from KRunner (Alt+Space).

## Frame and panels are one distance-field shape; motion follows Caelestia

Taken from reading Caelestia's source (`caelestia-dots/shell` at 454f46d). Noctalia was
also checked, but its current tree is a C++ rewrite, not Quickshell; only its tooltip
timing carried over.

- **Shape:** `shaders/frame.frag` draws the border and every attached panel as one
  signed-distance field, merged with a circular smooth-min. The fillet where a panel
  meets the border forms by itself as the panel slides out, so there are no hand-drawn
  corner arcs. This is a much reduced version of Caelestia's blob renderer: no spring
  deformation, no per-pair exclusions, four panel slots passed as uniforms.
  Rebuild after editing: `/usr/lib/qt6/bin/qsb --qt6 -o frame.frag.qsb frame.frag`
  (needs `qt6-shadertools`). The compiled `.qsb` is committed.
- **Slide, not grow:** panels keep their full size and slide out from behind the border
  (`offset` 1 to 0), clipped at the border, as Caelestia's `offsetScale` does. A hidden
  panel is dropped from the shader, otherwise it would bulge the border from behind.
- **Curves** (Material 3 expressive, Caelestia's defaults): movement and resizing use
  `[0.38, 1.21, 0.22, 1]` over 500 ms, which overshoots slightly and settles; opacity and
  colour use `[0.34, 0.8, 0.34, 1]` over 200 ms. One place: `Theme` + `widgets/Anim.qml`.
- **Shadow:** the whole shape casts one soft shadow (`MultiEffect`, blur 15) on the
  windows below. Caelestia uses 0.7 opacity; here 0.5 (`Theme.shadowOpacity`).
- **Hints** wait `Theme.hintDelay` (400 ms; Noctalia uses 500) before first appearing,
  then switch immediately between items.

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

## Tray menus are drawn by the shell

`widgets/MenuPopup.qml` reads a tray item's menu through `QsMenuOpener` and draws it in
the bar's style; submenus are further `MenuPopup`s beside their entry. This replaced
`QsMenuAnchor` (native Breeze `QMenu`) and with it the `UseQApplication` pragma, which
nothing else needed.

- Each tray item keeps its opener attached, so entries are loaded before the menu is
  mapped and the popup never resizes while visible (see "Popups have a fixed size").
  Submenus are created on first use and map only once their entries have arrived.
- `Qt.labs.platform` tray icons do not export submenus over DBusMenu. Test with a QWidget
  `QSystemTrayIcon` (PyQt) instead.
- Entry icons arrive as pixmaps rendered by the app for its own palette, so a dark-on-light
  icon stays dark on our dark menu. Not recoloured: they may be full-colour.
- Mouse only; no keyboard navigation yet.

## Quickshell service singletons are lazy

`SystemTray`, `Mpris`, `Networking`, `UPower` start their D-Bus queries on first access
and fill in asynchronously. Read them through bindings; an imperative read right after
first touch sees empty lists.

## Empty desktop vs. no window access

The taskbar keeps a second, unfiltered `TasksModel` purely for its count. Zero windows on
the current desktop shows nothing; zero windows anywhere shows the "or KWin denied" hint.

## QML naming trap

A property named `onSomething` is parsed as a signal handler. Hence `accentFg`.

## The audio mixer uses plasma-pa's models, the bar button uses Quickshell's PipeWire

Quickshell's PipeWire service has no port availability, so it lists every node (here 4
outputs, 3 inputs). Plasma hides devices whose only port is unplugged (3 and 1).
`org.kde.plasma.private.volume` (plasma-pa) loads in Quickshell and brings the same
filter model, level meters and `plasmaparc` settings the Plasma applet uses, so
"raise maximum volume" is shared with Plasma. It is private API tied to the Plasma
version, hence behind `Guarded`. The bar button stays on Quickshell's service so it keeps
working if that module ever breaks. Both use the same volume scale.

Not ported: per-device port/profile menus, the microphone test, pinning.

## Power & Battery uses PowerDevil's QML modules

`org.kde.plasma.private.batterymonitor` (`PowerProfilesControl`, `InhibitionControl`) and
`org.kde.plasma.private.battery` (`BatteryControlModel`) load in Quickshell and are what
Plasma's applet uses, so profile changes, peripheral batteries and sleep/lock blocking
behave identically. Quickshell's UPower service could do profiles and batteries but has
nothing for inhibitions, and one backend per panel is simpler. Private API, so the whole
bar button is behind `Guarded`; this replaced the Phase 1 UPower battery pill.

The control objects live in the bar button, not the panel: the button shows their state. A manual
block is daemon-side state anyway (it survives the object that requested it).

`PowerProfilesControl.setProfile` takes the profile name; the type info misnames its
parameter "reason". Breeze has no `power-profile-*` icons; the applet's are
`battery-profile-{powersave,balanced,performance}-symbolic`.

Not ported: brightness, the lid-action hint, remaining-time display.

## Real popups never resize while mapped

Resizing a mapped `PopupWindow` at fractional scale leaves the old buffer stretched to
the new size and stale (Quickshell 0.3.1, Qt 6.11). This now only concerns `MenuPopup`,
which maps once its entries have arrived. Popouts and the dock are items inside the frame
surface and resize freely.

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
