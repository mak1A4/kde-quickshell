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

The frame and the exclusion surfaces use the layer-shell namespace `dock`. KWin maps the
namespace to a window type (`dock`, `desktop`, `notification`, `on-screen-display`, ...;
anything else is a normal window). As a normal window the shell was hidden by show
desktop along with everything else; as a dock it stays. The namespace is fixed when the
surface is created, so changing it needs a restart, not a reload.

If the frame ever swallows clicks: `pkill -x qs` from KRunner (Alt+Space).

## Frame and panels are one distance-field shape; motion follows Caelestia

Taken from reading Caelestia's source (`caelestia-dots/shell` at 454f46d). Noctalia was
also checked, but its current tree is a C++ rewrite, not Quickshell; only its tooltip
timing carried over.

- **Shape:** `shaders/frame.frag` draws the border and every attached panel as one
  signed-distance field, merged with a circular smooth-min. The fillet where a panel
  meets the border forms by itself as the panel slides out, so there are no hand-drawn
  corner arcs. This is a much reduced version of Caelestia's blob renderer: no spring
  deformation, no per-pair exclusions, four panel slots plus the tooltip bubble passed
  as uniforms.
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
- **Dock tooltip:** a plain bubble 9 px above the hovered icon, in its own colour
  (`Theme.tooltipBg` / `tooltipFg`, accent by default) so it reads as separate from the
  dock. The shader draws it as an independent shape (own colour and opacity, not merged),
  which gives it the shared shadow. Joining it to the dock was tried in several forms and
  rejected (2026-10-04): a triangle tail, then shader variants `neck`, `bridge`, `tab`
  and a bouncing `bead`. Those are in git history if ever wanted again.
- **One side panel:** the hint of a hovered bar button and the popout a button opens are
  the same panel (`sidePanel` in `Frame.qml`) with different content. Clicking a button
  grows its hint into the popout in place, and closing a popout with the pointer still on
  the button shrinks it back to the hint, without the hint delay. That fallback is
  decided by who closed it (`Popouts.closing(anchorItem, byOwner)`), not by hover state,
  which can read "not hovered" for a moment mid-click and made the panel slide away and
  return. 150 ms later the hint settles on whatever really is hovered. As two panels (the
  first version) one slid in while the other slid out through it. This is Caelestia's
  structure: one popout wrapper per bar whose content and size change.
  `SidePanel` animates width, height and anchor, and derives `y` from them, so the panel
  stays centred on its button through a size change. Its content is clipped to the
  background, so content laid out for the final size is uncovered as the panel grows.
- **Content inside a morphing panel:** two rules, learned from the launcher looking
  "fixed" while the dock grew around it. Content is clipped to the background rectangle
  (it is laid out at its final size at once, while the shape takes 500 ms to get there).
  And content that takes turns with other content uses `widgets/SwapFade.qml`: it fades
  out at once but waits `Theme.swapDelay` before fading in, so the two never overlap.
  The dock's icon row also stays on the dock's own strip at the bottom while the panel
  is launcher-sized.
- **Hints** wait `Theme.hintDelay` (400 ms; Noctalia uses 500) before first appearing,
  then switch immediately between items.

## Session menu

A power button at the bottom of the bar opens a popout with lock, sleep, hibernate, log
out, restart and shut down. One list, `SessionActions`, serves this menu and the
launcher's `>` actions.

- Lock and the sleep states go to logind (`loginctl lock-session`, `systemctl suspend`).
  Hibernate is listed only if logind's `CanHibernate` says yes (here: no).
- Log out, restart and shut down go to KDE's session manager (`org.kde.Shutdown`), which
  closes applications in order; `systemctl poweroff` would not.
- Confirmation: the bar menu arms an action on the first click and runs it on the second
  (within 4 s), because KDE's own confirmation screen after our popout would be a second,
  differently styled dialog. The launcher keeps KDE's screen (`org.kde.LogoutPrompt`): one
  Enter on a typed query should not be able to shut the machine down.
- None of the actions were run in testing, only the calls checked against the D-Bus
  introspection.

Popouts may now be narrower than `Theme.popupWidth`; the frame takes the content's width.

## App launcher

Opened from the first button in the dock, or with `qs ipc -p <config> call launcher
toggle` (also `open`, `close`). The dock panel itself grows into the launcher, so it is
the same blob changing size, not a second panel. Inspiration: Caelestia's launcher (short
result list over a search field, `>` for actions, calculator) and Noctalia's usage
tracking.

- **Apps:** Quickshell's `DesktopEntries`. Started with `kstart --application <id>`, so
  each app gets its own systemd unit and KDE's startup handling instead of being a child
  of the shell. `kstart` never returns for an id it cannot resolve, so it runs under
  `timeout 5`; on failure the entry is started by Quickshell directly.
- **Ranking:** own scorer in `launcher/search.js` (exact, prefix, word start, initials,
  substring, letters in order; name counts most, then generic name, keywords, id,
  comment). With no query the list is ordered by use: launch count halved per two weeks
  since the last launch, stored in Quickshell's state dir (`launcher-usage.json`).
- **Calculator:** `=` prefix, or plain arithmetic. `launcher/calc.js` is a hand-written
  parser, not `eval`. Enter copies the result with `wl-copy`; `Quickshell.clipboardText`
  did not reach the clipboard when tested.
- **Actions (`>`):** the session actions (see "Session menu") plus reloading the shell.
  Not exercised in testing.
- **Keyboard:** while open the frame asks for exclusive keyboard focus (confirmed in the
  protocol trace: KWin sends `wl_keyboard.enter`), and the hole in the input region
  closes so a click outside dismisses it, as for popouts.
- **IPC naming:** functions must not be called `show`; `qs ipc` has a `show` subcommand
  and lists the function instead of calling it.

To open it with a key: System Settings > Keyboard > Shortcuts > Add New > Command, with
`qs ipc -p /path/to/shell call launcher toggle`. The Meta key alone is wired by KWin to
Plasma's own launcher and was left as it is.

## Command palette (KRunner's search, own panel)

`qs ipc -p <config> call palette toggle` (also `open`, `close`, `search <text>`) slides a
panel down from the top frame edge: search field on top, results below. It is the third
panel in the frame shader (`panel2`), so it joins the border like the dock does. State and
logic are in the `CommandPalette` singleton (`Palette` is a QtQuick type; a singleton by
that name is silently shadowed and reads as `undefined`).

- **Search is KRunner's.** `org.kde.milou` exports `ResultsModel`, the model Plasma's own
  KRunner window uses. It loads in Quickshell and runs the runner plugins in this process,
  with the selection and order from System Settings > Search > KRunner (`krunnerrc`). So
  apps, windows, settings modules, web shortcuts, browser tabs and history, calculator,
  unit converter and so on come from KDE, and running a result is KDE's code too
  (`model.run`). Only the window is replaced. Results arrive about 100 ms after a key.
  `palette/Runner.qml` wraps it, behind a `Loader` because the import is optional, created
  on first use and kept so the plugins load once.
- **Plain objects.** The wrapper copies the model's rows into `matches` on every change,
  and the view gets a new list each time, as in the launcher. This is what lets the
  palette mix in rows KRunner does not know: the shell's own actions (`>`, the
  launcher's list). With nothing typed the list is empty; a list of recent searches was
  there at first and removed (2026-10-04, not wanted). A selection made by hand is found again in the new list by `key`
  (id + title + subtitle; the id alone is not enough, the unit converter uses one id for
  whatever it currently answers).
  A `ScriptModel` keyed on `key` was tried first, so that rows which stay are not rebuilt.
  Dropped: when it inserts rows above the first visible one, `ListView` keeps the view on
  the old rows and moves its origin instead, and the new top results sit above the
  viewport (seen as a list of blank rows after scrolling down and changing the query).
- **No collapsing while typing.** KRunner has nothing for a moment after each key. The
  previous results stay up until the first new ones arrive (`fresh`); Enter in that gap is
  remembered and runs the first result once it is there, as KRunner does.
- **Windows first, then answers.** KRunner orders categories by use. Open windows (KWin's
  runner, ids `windows_...`) are always moved to the top: switching to what is already
  running comes before starting or searching anything. Calculator and unit converter
  results follow; KRunner had put "14" below three browser history entries containing
  "2+3*4". Because of the reordering a row is found again by its id before it is run.
- **Copying** an answer uses `wl-copy`, as in the launcher. The runners' own copy goes
  through this process's Qt clipboard; run headless it returned false and left the
  clipboard alone.
- **Actions:** a result's extra actions (KRunner's: copy, incognito window, ...) are
  buttons on the selected row. Shift+Enter runs the first; Tab walks through them and on
  to the next row, as in KRunner.
- **Shared list:** `widgets/PickList.qml` is the launcher's list with its selection
  movement, moved out unchanged so both use it.

- **Icons:** a runner gives an icon name or a `QIcon`, and the `QIcon` may be empty
  (browser tabs and history without a favicon). Script cannot tell an empty one from a
  real one, so the row shows a stand-in whenever Kirigami reports the icon as not `valid`.
  A real `QIcon` is drawn as it comes, so a dark icon from a light icon theme stays dark
  on the panel (as for tray menu entries).

Not ported: KRunner's single-runner modes and its own history; drag and drop of results;
multi-line results (they are cut to one line).

## Notifications: the shell is the service while it runs, Plasma otherwise

While the shell runs it is the notification service, with KDE's own engine
(`org.kde.notificationmanager`, the library Plasma's applet uses) in its process:
`shell/notifications/Service.qml`. That keeps what Plasma has: the rules of System
Settings > Notifications, do not disturb, the history, job tracking (file copies,
downloads), sandboxed applications through the portal. The shell draws the popups
(`notifications/Popups.qml`, `Card.qml`): a panel hanging from the top edge against the
bar, the frame's fourth panel slot. When the shell is not running, Plasma is the service
again, as if nothing had been installed.

- **The service cannot be taken from outside.** plasmashell claims its bus names with
  "replace the existing owner, do not allow replacement" (it is the "D-Bus master" in
  libnotificationmanager's `server_p.cpp`), and only the owner of a name can release it.
  Nor does it release them when its notification applet is removed at runtime. Restarting
  plasmashell on every start and stop of the shell would have worked and was not
  considered smooth.
- **So plasmashell lets go itself.** `plasma/handover` is a Plasma widget for the system
  tray that never shows anything (status hidden). It watches the bus for a name the shell
  owns while it runs, `io.github.mak1a4.kde-quickshell.notifications`. While that name is
  there, it has plasmashell release four names: `org.freedesktop.Notifications`,
  `org.freedesktop.impl.portal.desktop.plasmanotify` (the portal, for sandboxed
  applications), `org.kde.JobViewServer` and `org.kde.kuiserver` (jobs). When the name is
  gone, it has plasmashell request them again. plasmashell's service objects are never
  touched, only unreachable meanwhile, so it resumes exactly as it was. Measured: the
  shell is the service within the second it starts; killed with `kill -9`, Plasma has the
  names back after about 50 ms.
- **No keeper, no stored state.** The announcement is a bus name, and the bus drops it
  when the process ends, however it ends. Nothing is written anywhere that a crash or a
  logout could leave behind.
- **Both sides speak D-Bus from QML** with `org.kde.plasma.workspace.dbus` (Plasma's own
  module: method calls, service and signal watchers). It loads in Quickshell too, so the
  shell requests its name with it. (This could replace the `busctl` plumbing elsewhere.)
- **Installing the helper** is done by the shell (`Notifications.qml`, with
  `kpackagetool6`) when it is missing or differs from the repository's. The system tray
  loads a newly installed one by itself. A changed one is only used after plasmashell has
  been restarted, QML being cached in the running process.
- **plasmashell started while the shell runs** takes the names at its own pace, some of
  them seconds after start. The helper therefore also lets go of any of the names
  plasmashell acquires later (the bus's `NameAcquired` signal). The portal's name
  plasmashell does not even get in that case (it does not replace an owner for that
  one); it is requested together with the notification name when the shell goes.
  On the shell's side the models are destroyed when the names are lost and made again
  when they are free; what was showing then is gone.
- **Without the helper** (not installed, or no system tray in Plasma) nothing changes:
  plasmashell keeps the service, the shell's models are never created.
- **Traps found:**
  - Reading a `list<string>` property in QML gives a live view of it, not a copy.
    "Remember the released names, then clear the property" cleared the remembered ones
    too, and Plasma never took the names back. `property var` copies.
  - The D-Bus module hands replies and signal arguments over as wrapped values:
    `reply.value === 1` is never true, and `names.includes(name)` never matches. Convert
    with `Number()` and `String()`. Arguments must be typed (`new DBus.string(...)`) and
    given without a `signature`.
  - A `SignalWatcher` receives every signal of its interface and logs each one it has no
    `dbus<Signal>` function for.
  - The logic is in `Handover.qml`, apart from the plasmoid, so that it can be run in a
    Quickshell process standing in for plasmashell, with test names. Every change to it
    was tested there first; a bug in it inside plasmashell leaves the desktop without
    notifications until plasmashell is restarted.
- **Quiet by default (2026-10-05).** Only critical notifications pop up. Everything else
  goes straight into a list behind a bell in the bar (`modules/Bell.qml`,
  `notifications/NotificationList.qml`): a dot on the bell, with a ring spreading from it
  every two seconds, says some have arrived since the list was last open. Left click (or
  `qs ipc call notifications toggle`, or the "Show notifications" shortcut) opens the
  list as a popout: the same cards, do not disturb, clear, System Settings. Middle click
  on the bell switches do not disturb.
  - **Not expired, only not shown.** KDE's engine has "expire" for a popup that has had
    its time, and the first version expired everything at once. But expiring tells the
    application its notification is closed and removes its actions: nothing in the list
    could be answered or opened any more. So quiet notifications stay open towards their
    applications until closed in the list. A transient one (it asks not to be kept: a
    track change) is closed at once, since no popup means nothing is left of it.
  - **The list ignores System Settings' history rules.** Those assume a popup was seen:
    by default KDE keeps low priority notifications and everything from programs
    without a desktop entry (`notify-send` from a script) out of the history. Without
    popups those would never be seen at all.
  - **Unread and the list's size are counted here**, from the model's row signals. KDE's
    own unread count only covers expired notifications, and its `count` property did not
    announce the first row.
  - **Do not disturb:** the dot stays but stops calling; critical ones pop up if System
    Settings allows it. The popup model needs `showAddedDuringInhibition: false` and
    `ignoreBlacklistDuringInhibition: false`: with the defaults, anything arriving
    during do not disturb bypasses the urgency filter and pops up.
  - Jobs (file copies) are in the list, with their progress, not popped up.
- **Popups** (critical only): up to 4, newest first. A card stays until closed, not
  expiring. They step aside while the palette is open, and show on the first screen
  only.
- **The card is Caelestia's in outline** (its `modules/notifications/Notification.qml`,
  read 2026-10-05):
  - **Icons: an application's own, in colour; a Tabler glyph where the system speaks.**
    The icon a notification names (else its application's) is drawn from the icon theme,
    in colour and as large as the space (42 px), unless it is one of the standard names
    for a state or a device (`battery-caution`, `network-wireless`, `dialog-information`,
    ...): those, and a notification with no icon at all, get a glyph from the Tabler set
    on a disc. `notifications/glyphs.js` is the table; the glyphs (53, outline, MIT) are
    in `shell/icons/tabler`, fetched by `tools/tabler.sh`, drawn tinted through
    Kirigami's icon as a mask. A glyph whose file is missing shows as Kirigami's
    "unknown" icon, a filled sheet of paper. Editing `glyphs.js` does not reload the
    running shell (only QML files do): restart it to see a changed table.
    Urgency: on a disc its colour (red for critical, muted for low priority); on a colour
    icon a red dot on its corner, or the icon dimmed.
    How it got there: a red stripe at the card's edge (not liked), an "Urgent" badge,
    then Caelestia's way, a one-colour glyph on a disc coloured by urgency, with the icon
    theme's symbolic icons for glyphs. Those are drawn for 16 px with wide margins and
    sat small and crude in the disc. Icons in colour without a disc looked much better. A
    page with twelve variants and real icons from several sets followed
    (https://claude.ai/artifact/8AqNFeG7vMXmpBHQvswpTr); Tabler was liked. But Tabler is
    a set of interface glyphs: of 131 applications installed here five have a brand icon
    in it, so with Tabler alone nearly every application would be a bell. Hence the
    split. Other shells: Caelestia tints the application's icon to one colour, end-4
    puts it in colour on a disc and guesses a glyph from the title otherwise,
    DankMaterialShell shows the application's icon or its initial.
  - A notification's own picture is shown round in the icon's place, with the icon small
    on its corner.
  - Cards start collapsed: title with its age ("now", "5m"), one line of the body. The
    arrow (only there if something is cut off) or a click expands to the application's
    name and the whole text. Unlike Caelestia the action buttons and a job's progress
    and controls show collapsed too: an incoming call must not need expanding to answer.
  - A click runs the default action if there is one, else expands or collapses. The
    cross (on hover), a middle click, or dragging the card more than 35 % of its width
    to either side closes it for good; a shorter drag snaps back.
  - Left out: the copy button and the progress ring around the icon.
- A reload of the shell empties what is showing and the history: the models are views on
  one store that goes when the last view goes.

Not built yet: inline reply, grouping by application.

Tested: the handover with a test process and with the real shell (stop, start, kill,
start; plasmashell restarted while the shell runs), ownership of all four names each
time, and that `notify-send` succeeds on either side. Popups by screenshot: several at
once, timeout, a critical one staying, closing over D-Bus, a job's progress bar (a
pretend copy reported to the job tracker). With the virtual pointer: hover showing the
cross, the cross, middle click, expand by arrow, collapse by click, dragging a card
away, a short drag snapping back, an action button (the sending `notify-send` reported
the action). The quiet mode: nothing but critical ones popping up, the dot and its count,
the list opening, an action clicked in the list reaching its sender, clear, do not
disturb by middle click (KDE's setting written and removed, the bell's look, only the
critical one popping up during it), a transient notification dropped. Not tested: the
default action, a link in the body, a job's Pause and Cancel, the do-not-disturb switch
inside the list (only the middle click), a real sandboxed application, real file copies.

## Clipboard history in the palette

Meta+V (an override of Klipper's "Show Clipboard Items at Mouse Position", see "Global
shortcuts") or `qs ipc call palette clipboard` opens the palette in a second mode that
lists Klipper's history: text entries by their first line, images as thumbnails. Typing
filters, Enter puts the entry back on the clipboard, Backspace in the empty field returns
to normal search. It is a mode of its own and not mixed into the search results, so
nothing copied shows up while looking for an app.

- **Klipper stays the owner.** It runs inside plasmashell and records and stores the
  history; the shell only reads its store (`shell/clipboard.sh`): `history3.sqlite` in
  `~/.local/share/klipper/`, one row per entry and one per MIME type, and the bytes of
  each type in `data/<uuid>/<data_uuid>` (images as PNG). Opened read-only with the
  `sqlite3` command. Private to Klipper and tied to its version (Plasma 6.7), so re-test
  after Plasma upgrades.
- **Why not the other two ways.** Klipper's D-Bus interface gives text only (229 of 500
  entries here are images). Its QML model (`org.kde.plasma.private.clipboard`) would run
  a second clipboard tracker in the shell's process next to the one in plasmashell, both
  writing the same store.
- **Search** runs in SQL over the whole text of every entry (14 ms for 500 entries), once
  per change of the query; only a 300 character preview of each entry is handed to QML.
  "image" finds the images.
- **Copying** an entry back is `wl-copy` with the stored bytes (PNG, or the plain text).
  Klipper recognises the content: the entry moves to the top, no duplicate appears.
  Rich text comes back as plain text. It cannot paste into the window underneath: that
  would need injected keys.
- No removing or starring entries: Klipper offers neither over D-Bus, and its store is
  not written to from here.

## Global shortcuts: the shell's own actions in KDE's shortcut service

`shell/Hotkeys.qml` registers the shell's actions ("Toggle command palette", "Toggle app
launcher", "Show clipboard history") with KGlobalAccel under one component, `kde-quickshell` ("Quickshell"), as a
KDE application does, and listens for the service's `globalShortcutPressed` signal. KDE
stores the keys (`[kde-quickshell]` in `kglobalshortcutsrc`) and lists the actions in
System Settings > Keyboard > Shortcuts. A key press starts nothing and nothing depends on
where the shell's files are.

- **Over D-Bus with busctl**, for lack of a D-Bus client in Quickshell; the calls are in
  `shell/hotkeys.sh`. At startup, per action, `doRegister`, `setShortcutKeys` with flag 8
  (this is the default key) and again with flag 2 (present; loads the stored key, or
  takes the given one if KDE sees the action for the first time, so a key the user
  cleared stays cleared). One `busctl --user monitor --json=short --match ...` runs for
  the signal on `/component/kde_quickshell`. KGlobalAccel does not track the registering
  connection, so the short-lived busctl calls are enough.
- **Default:** Ctrl+Space for the palette, none for the others.
- **The keys are KDE's only while the shell runs.** KGlobalAccel does not notice a client
  going away, so a detached keeper process (one per shell process) waits for the shell's
  process to end, by quit, kill or crash (`tail --pid`), and then marks the component's
  actions inactive (`setInactive`), which gives the keys back and keeps the stored ones.
  A reload does not touch them. Releasing from QML on destruction was not an option: on a
  reload the old generation is destroyed after the new one has registered, and would
  switch them off. A restarted shell could have the same problem with the previous
  shell's keeper; a lock held for a keeper's whole life makes the new one wait for the
  old one to finish and register after it.
- **Overrides: a key that another program has** (KRunner's Meta+Space) is not taken away
  from it. The owner keeps the key in KDE's settings; while the shell runs, the owner's
  action is switched off (`setInactive`) and ours holds the same key, and when the shell
  is gone the keeper switches the owner on again (`setShortcutKeys` with flag 2 and no
  keys: present, stored keys loaded). So KRunner answers its key whenever the shell is
  not running. Inactive is not stored anywhere, so a crash or a logout that leaves the
  keeper no time costs nothing: KDE starts every session with the owner active. Found by
  trying: KGlobalAccel lets an action take a key whose other holder is inactive, and
  lists both for the key afterwards. What is overridden is kept in
  `~/.config/kde-quickshell/shortcut-overrides.tsv` (action, key, owner), applied by the
  keeper at every start and written by the settings.
  Of the ways to switch the owner on again only that one worked; `doRegister` and setting
  its keys again did not.- **Replaced (2026-10-04):** a desktop entry per action whose command was
  `qs ipc -p <shell path> call <target> toggle`, with KDE attaching the key to the entry.
  It worked, but every key press started a process, the entries had to be written into
  `~/.local/share/applications/`, and `qs ipc -p` only finds a shell by the exact path it
  was started with (a symlinked path to the same directory finds nothing).
  Also: `qs ipc call` exits 0 even for "Target not found".

## Settings: an ordinary KDE window, a program of its own

`settings/` is a second Quickshell config: `qs -p settings`, or "Shell settings" among the
`>` actions of the launcher and the palette. It is deliberately not part of the frame and
not in the shell's style (decided 2026-10-04): it is settings for the shell, not something
that comes out of it, so it looks like any KDE settings page. A `FloatingWindow` with
KWin's normal title bar, `Kirigami.FormLayout`, Breeze controls.

- **Own process** because Breeze's widget style needs a `QApplication`
  (`//@ pragma UseQApplication`), which the shell itself dropped. A crash or a dialog in
  the settings also cannot touch the frame. Plain `qml` would not do: QML alone cannot
  start `busctl`; Quickshell's `Process` can.
- **Shortcut fields** are KDE's `KeySequenceItem` (`org.kde.kquickcontrols`), the button
  used everywhere in KDE. It records with global shortcuts held off, so a combination
  that is in use (KRunner's Meta+Space) can be pressed too.
- **Conflicts, one click.** The button's own conflict check (a modal dialog) is off.
  Instead the pressed key is looked up in KGlobalAccel (`getGlobalShortcutsByKey`); if
  another action has it, nothing is changed and the window shows "Meta+Space is already
  the shortcut for KRunner" with one button. For another program's key that button sets
  up an override (see "Global shortcuts"): the program keeps its key and has it whenever
  the shell is not running. Between the shell's own two actions it moves the key. Giving
  an action a different key afterwards ends its override, and the owner has its key back
  at once. Nothing is specific to KRunner.
- **What it lists** is whatever the shell has registered with KGlobalAccel (see "Global
  shortcuts"): `allShortcutInfos` of the component, one field per action, labelled with
  the action's name. The list of actions exists only in `shell/Hotkeys.qml`.
- **Setting** goes through KGlobalAccel's D-Bus interface with `busctl`
  (`setForeignShortcutKeys`, the call System Settings uses). D-Bus wants
  Qt key numbers, QML only sees the text of a key sequence ("Meta+Space": a non-literal
  string converts to and from `QKeySequence`, a literal in a binding does not compile),
  hence the tables in `settings/keys.js`. A combination they do not cover is refused with
  a pointer to System Settings.
- **Dead ends:** a frameless window in the shell's style works
  (`Window.window.flags = Qt.Window | Qt.FramelessWindowHint` from an item inside a
  `FloatingWindow`) and was the first plan. An own key recorder also works if global
  shortcuts are blocked meanwhile (`blockGlobalShortcuts` on KGlobalAccel's D-Bus
  interface); KDE's button made it unnecessary. A line showing KRunner's current key and
  a note on how to take it were removed in favour of the conflict message.

Tested: the settings' shortcut code on its own (set, read back, refuse a chord, detect a
conflict, move a key between the shell's actions, override KRunner's key and end the
override), each step followed by real presses of the keys to see what answers (palette,
launcher or KRunner); Meta+Space with the shell running, stopped, started, reloaded and
restarted at once; the key tables; opening the window with Enter on "Shell settings";
and, in the first version of the window, recording Meta+Space, which showed the conflict
with KRunner. Not tested: a click on the button in the window (only its function,
headless), the message's close button, and the message's current wording on screen.

## Testing the pointer: a virtual pointing device

`tools/pointer.py` is the counterpart of `tools/keys.py` for the mouse: an absolute
pointing device through uinput, with positions in logical pixels (the screen is 1920 x
1080 logical at scale 1.333, 2560 x 1440 in screenshots). It moves the user's real
cursor. So: find what is to be clicked in a screenshot taken just before (the cards were
found by scanning for their colour), stop if it is not where expected, and put the cursor
back where it was (KWin's `workspace.cursorPos`, read with a script like the active
window). The first test moved the cursor onto the user's browser, because the
notifications it was meant for had been closed meanwhile; nothing was clicked only because
that step was a hover.

## Testing keys: a virtual keyboard

`tools/keys.py` presses keys through uinput (python-evdev; `/dev/uinput` is writable for
the logged-in user here). They arrive like a real keyboard's, through KWin, so global
shortcuts, the layer surface's keyboard focus and Qt's auto-repeat for a held key are all
part of what is tested. The IPC handlers answer `isOpen` and `query`
(`qs ipc call palette query`), so a script can check what a key did; where the effect
is only visible (which row is highlighted), take a screenshot (`spectacle -b -n -f -o`).

The keys go to whatever has the focus, and on a desktop someone is using that changes
under the test. The palette and the launcher take the keyboard outright, so there it is
enough to confirm it once: type a letter and read it back. For an ordinary window (the
settings) ask KWin for the active window before every batch of keys and stop if it is not
the expected one: a KWin script with `print(workspace.activeWindow.caption)`, loaded and
run over D-Bus (`org.kde.KWin /Scripting loadScript`), its output read from
`journalctl --user`. Harmless things to press Enter on: a calculation (copies
the answer), a small app that is then closed again.

This found two bugs the screenshots had not: the selected action staying armed when
another result took the row's place (in the since removed list of recent searches, Enter
after "Forget" forgot the next entry too), and the blank list described above.

## Workspace indicator and show desktop

A column of dots, one colour per desktop by position (`Theme.desktopColors`). The current
desktop is a taller capsule in its colour, after Caelestia's indicator: its two ends
animate separately (the trailing end 1.5x slower), so it stretches while it travels.
Desktops with windows are solid dots, empty ones small and faint. Numbers were tried
first and dropped (2026-10-04). Occupancy comes from an unfiltered `TasksModel`
(`VirtualDesktops` role), so it needs the window-management grant; windows on all
desktops are ignored.

Clicking the current desktop toggles show desktop through
`org.kde.kwindowsystem` (`KWindowSystem.showingDesktop`, readable, writable and
notifying). KWin restores the windows exactly, and also ends the mode by itself when a
window is activated. The capsule is hollow while it is active. Scrolling does not switch desktops (decided 2026-10-04).

The ring after the last dot (in the colour the next desktop will get) appends a desktop (KWin D-Bus `createDesktop`, empty name so KWin picks
"Desktop N") and enters it. Right click removes a desktop (`removeDesktop`) and leaves
the windows to KWin's standard rule: they keep their position in the list, so they land
on the desktop that followed, or on the new last one when the last desktop is removed.
The last remaining desktop cannot be removed.

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

## KDE Connect uses the daemon's QML module

`org.kde.kdeconnect` (shipped with kdeconnect, used by Plasma's applet) loads in
Quickshell: `DevicesModel` filtered to paired and reachable devices, as in the applet,
plus per-device battery, connectivity (mobile signal) and plugin interfaces created
through the `*DbusInterfaceFactory` singletons. `PluginChecker` says whether a device has
a plugin loaded; an action is only offered when it has. Behind `Guarded`.

Actions: ring and browse call the plugin interfaces; SMS starts `kdeconnect-sms`; share
runs `kdialog` for the file choice and `kdeconnect-cli --share` per file, because a QML
`FileDialog` would have to be parented to the frame's layer surface.

The per-device state (battery, signal, plugin checks) lives in the bar module for as
long as a device is connected, not in the panel. Plugin checks answer asynchronously; a
panel that asked on opening would open small, then grow and shift once they arrived.
General rule for popouts: everything that decides the content's size must be known
before `Popouts.toggle()`.

Not ported: pairing requests, the phone's notifications, remote commands, clipboard
push, virtual monitor.

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
