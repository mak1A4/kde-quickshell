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
- **The bar's icons are in the theme's colours** (2026-10-07), not all in the text's:
  the theme's own red, green, yellow, blue, magenta and cyan, which are its terminal's
  (`Theme.hues`). Each module has one (`Theme.moduleHues`: session red, volume green,
  power yellow, network blue, media magenta, KDE Connect cyan), and a one-colour icon
  in the tray has one by its item's name, always the same. What an icon's colour said
  before it still says: the network's is red or yellow when something is wrong, which
  is why its own is blue; power's is the accent while sleep is blocked, which is why
  its own is yellow, the accent of no theme; KDE Connect's is dim with no device. A
  terminal's colours are made for text on the terminal's background, and several are
  faint as an 18 px icon on the frame (Everforest Light's yellow on cream): each is
  taken towards the text's colour, a tenth at a time and at most half, until it stands
  out three to one. The hidden-icons arrow, the clock and the dock are as they were.
- **The pointer** is the pointing hand over anything a click does something on, as in a
  web page (2026-10-07): every `MouseArea` with an `onClicked` has
  `cursorShape: Qt.PointingHandCursor`. Not the ones that only stop clicks from going
  through, and not sliders. The clock has only this: no background under the pointer
  and none while its calendar is open (`BarButton.hoverEffect`).
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

**The keyboard goes back to the window that had it.** The frame is one surface that
asks for the keyboard while something in it is typed into (the launcher, the palette,
the notification list: exclusively; a popout: once clicked). KWin makes it the active
window then, and leaves it that when it stops asking; a surface that was unmapped
instead would not have this. Seen with the frame's `Window.active` and KWin's
`workspace.activeWindow`: after Escape in the palette nothing could be typed into any
window until one was clicked. So `LastWindow.qml` reads the task model's active window
just before the frame asks, and the frame activates it again 60 ms after it has stopped
asking, if it is still the active one itself. Running something that may open a window
(an application, a KRunner result, a shell action) says so first, and the frame waits
2 s for it: activating the old window at once took the new one's right to the focus
(KCalc started from the palette opened behind the terminal). Something run that opens
nothing gets the keyboard back to the old window after those 2 s. With nothing
remembered (the shell reloaded while it had the keyboard, as "Reload shell" does) the
topmost window of the desktop is activated instead, by the task model's stacking order.
Tested for the palette, the launcher and the list closed by IPC and by Escape, for an
application started from the palette, and for a reload under the open launcher. Not
tested: a popout that was clicked into, a second screen.

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
- **No tooltip on the dock's application icons** since 2026-10-05 (asked for: "want it
  more minimal"). The bubble described next is now only the launcher button's.
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
- **The active window in the dock** has a rounded square behind its icon, tinted with
  the current desktop's colour (`Theme.desktopColors`, as its dot in the bar), so the
  dock says which window and which desktop. Tried and dropped on 2026-10-05: a small
  accent bar under the icon (with a grey square), and the icon lifted with a pool of
  accent-coloured light under it and no square. Also tried that day and taken back: the
  active window's cell (square, icon and dot) standing 3 px above the row.
- **Hints** wait `Theme.hintDelay` (400 ms; Noctalia uses 500) before first appearing,
  then switch immediately between items.

## Clock: a binary clock, and a calendar

The clock in the bar is a binary clock (2026-10-07, `modules/clock/BinaryTime.qml`):
two columns of dots (since 2026-10-08), the hour of 24 on the left and the minutes on
the right, each one binary number: the lowest dot worth 1, then 2, 4, 8, 16 and 32, lit
where the number has that bit. A column is only as high as its number can need (five
dots for the hour, six for the minutes). Dots are 9 px with 3 between, the columns 6
apart: 24 wide and 69 high, in a cell as wide as any other. The hour's dots are lit in
the text's colour, the minutes' in the accent; an unlit dot is smaller and faint. The
time in figures is the first line of the hint.

- **Before, four columns**, one for each digit of `HH mm` (2, 4, 3 and 4 dots of 6 px,
  36 wide in a cell made 42 wide for it): in a bar of 48 the dots had to be small. Two
  columns leave room for dots half as large again, and the bar has the height. The
  price is the reading: a column is a number up to 59 to add up, not a digit up to 9.

- **Flat dots** (2026-10-08, to be looked at; the user was not sure of the liquid ones
  any more): drawn as the workspace switcher draws its dots (`modules/clock/Dots.qml`),
  a lit one solid at 9 px, an unlit one 6 px and faint in its column's colour. What
  moves: a dot coming on swells past its size and settles, and a wave goes up a column
  (each dot in turn swells to 1.3 and settles, 45 ms after the one below) when its
  number changes, so the minutes' once a minute, and up both when the pointer comes
  onto the clock, which has no background to light. Nothing runs between these. Not
  seen in motion: pictures taken around a minute's change were all of the minute
  before. `BinaryTime.liquid: true` brings the shader's
  dots back, which are described next; while it is false the shader is not loaded and
  its clock does not run.

The liquid dots are one drawing, by a shader (`shaders/binary.frag`): lit dots are a liquid
shape, made with the smooth minimum the frame is drawn with, so two that are lit next
to each other (in a column, or in a pair's row) join with a thin neck, and the dots
stay to be seen as its bulges. They breathe, each a little out of step, the necks
swell and ebb, there is a faint glow around them, and a dot coming on swells past its
size, settles, and sends out one ring. QML gives the shader two `vector4d` for each
column (a vector has room for four dots), how far each of its dots is lit, animated with a `PropertyAnimation` (which
can move a vector; `NumberAnimation` cannot), and a time that a `Timer` counts up 20
times a second: slow movement needs no more, and each step draws the whole frame's
surface again. The time runs at 0.4 of the clock's (`BinaryTime.speed`): a breath
takes ten seconds. At the shader's own pace, four seconds, it was restless. The count wraps at 2000 π, where every wave in the shader is at a
whole turn. Tried before it and taken out again the same
night: the time on a slant, `01 / 04`, hour above left, minutes below right, a slash
between.

A click opens the calendar as a popout (`modules/clock/CalendarPanel.qml`):

- **Top:** the time in figures, large, with the day, the date and the week.
- **The month** is the shell's own grid, in JavaScript: six weeks, week numbers (ISO),
  today as a disc in the accent, the picked day as a grey one, days of the months
  before and after faint, weekends dim. Arrows, the wheel, a click on the month's name
  or "Today" (there only while somewhere else) turn it; it slides in from the side it
  came from. A click on a faint day goes to its month.
- **Below:** the picked day and what is on it, with how far away it is.
- **Names and order** are the system's date format (`LC_TIME`): German names of days
  and months and Monday first here, next to the shell's English words. Plasma's own
  calendar mixes the same way.
- **Holidays and events** come from Plasma's calendar plugins, through the backend its
  own calendar uses (`org.kde.plasma.workspace.calendar`: `Calendar`, `DaysModel`,
  `EventPluginsManager` with `holidaysevents` and `pimevents`). `Events.qml` holds
  that and is loaded with a `Loader`: without the module the calendar is a calendar
  without them. The grid does not use Plasma's `MonthView`, which is Plasma's look. A
  day with a holiday has its number in red, one with an event a dot. What counts as a
  holiday is the plugin's word (`eventType`, which is a translated word: "Holidays" in
  English; in another language holidays would be listed as events), and which of them
  is a day off is KDE's data: for Austria it marks 10 October as one.
- **Which country's holidays.** The plugin, left alone, takes the country of the
  language: the United States' for English spoken in Austria. `setup.sh` writes the
  region once, into Plasma's own `~/.config/plasma_calendar_holiday_regions`, from the
  country the dates are formatted for (`de_AT` gives `at_de`), if nothing is chosen
  there. Which regions exist only KDE's holiday library can say, and it can only be
  asked from a program: `holiday-regions.qml`, a few lines run once with `qs -p`,
  prints them. It waits 400 ms before ending: Quickshell writes its log from another
  thread, and a program that ends at once loses lines (it did, once in eight).
- `qs ipc call clock toggle` opens and closes it; while open, `calendar pick
  2026-12-25` goes to a day and `calendar events` says what is on it.
- **A trap:** an inline component cannot be declared inside another one ("Nested
  inline components are not supported"). The shell had been restarted to pick up the
  new directory, and a restart with a file that does not load leaves no shell at all,
  where a reload would have kept the old one: reload first.

Tested on this machine, from pictures of the clock and of the popout alone: the clock
in the bar (01:18 as dots, before the shader); the shader's clock five times enlarged
in a hidden compositor, with a stand-in for `Theme` (13:57, 13:59, 20:48, 07:07: the
right dots lit and joined, and two pictures a moment apart not the same), since the
screen was locked by then; the two columns from a picture of the bar (12:47: 4 and 8 lit on the left;
1, 2, 4, 8 and 32 on the right, the four joined); the popout on today's month, on December (week 53 and then 1, which is
right for 2026) and on a picked day; the Austrian holidays after `setup.sh` had chosen
the region (Nationalfeiertag, Maria Empfängnis; none on 4 July), the American ones
before; `setup.sh` for `de_AT`, `en_US`, `fr_CH`, a made-up country and `C` against
scratch directories. Not tested: a click or the wheel (the month was turned through
IPC, which runs the same functions), a dot changing and the slide of the month in
motion, the popout's top since the time there is in plain figures, midnight, an event from a PIM calendar (none is installed), the
calendar without Plasma's module.

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
the same blob changing size, not a second panel. It began after Caelestia's launcher (a
short result list over a search field) and has since 2026-10-07 what KDE's own menu
has, in the shell's own layout; `>` for actions, the calculator and Noctalia's usage
tracking are as they were.

- **Layout** (`launcher/LauncherPanel.qml`, 570 by 501, a fixed size: it no longer
  grows and shrinks as one types). On the left a rail of icons, as the bar is one on
  the right: favourites, all applications, each category, the places, the session.
  Beside it the name of the chosen one with how many are in it, and its list, eight
  rows with a description under each name. Below both the search field, where the dock
  was. Typing replaces rail and list by the results. The session's actions are rows
  like any others, and "Shell settings" is among the `>` actions.
- **First laid out as KDE's menu is** (the user and the search on top, the categories
  as a list of names, a row of tabs and session buttons at the bottom, thin lines
  between): everything worked and it was KDE's menu in other colours. Taken back the
  same day; what it could do was kept.
- **Categories** are worked out here, from the categories a desktop entry names
  (Quickshell gives them): freedesktop's main categories under the names KDE's menu
  has for them (`Network` is Internet, `AudioVideo` Multimedia, `Utility` Utilities,
  `Settings` goes with System, `Science` with Education). An application is in every
  one it names; what names none is in "Other"; a category with nothing in it is not
  listed. Not KDE's menu itself (its private `kicker` models), which would bring the
  menu editor's changes too: those models want a Plasma applet around them, and a
  crash in them would be the shell's.
- **Favourites** are the launcher's own list, `~/.config/kde-quickshell/launcher.json`,
  desktop entries by name. Without the file it starts out as the favourites of KDE's
  menu, in their order (`launcher.sh favorites`: KDE keeps them in a database, but
  their order is in `kactivitymanagerd-statsrc`; `preferred://browser` is the default
  browser), or, where KDE has none, as what is pinned to the dock. From then on it is
  the launcher's, changed from an application's menu or with Ctrl+D.
- **An application's menu** (right click, the Menu key or Shift+F10): Open, the
  actions the application offers itself (a new window, a private one, System
  Settings' pages), favourite or not, pinned to the dock or not. It is drawn in the
  launcher's own panel, over the lists, and not a popup window as the dock's menus
  are: the launcher holds the keyboard exclusively, and a window of its own would have
  to take it and give it back. Up, Down and Enter are the menu's while it is open,
  Escape closes it and leaves the launcher, a click elsewhere closes it and does
  nothing else. Before it there was a star at the end of a row: on the chosen row it
  went along with the arrow keys, there and gone at each step; on the pointer's row
  alone it was still one more thing in every list.
- **Places** are those of KDE's file manager, read from the file it keeps them in
  (`user-places.xbel`), opened with `xdg-open`. Of KDE's "History" and "Frequently
  Used" there is nothing: a list of the files last opened, shown each time the menu
  opens, is not everyone's wish.
- **Keys:** the search field always has them. Up and Down move in the list, or, after
  Left or Tab, in the rail, where each move shows that category; Right or Tab goes
  back. Left and Right mean that only while nothing is typed. With the pointer, an
  icon of the rail is clicked: pointing at it showed its list at first, as KDE's menu
  does, and the list changed with every icon the pointer crossed.
- **The session's rows** go through KDE's own confirmation screen where they end the
  session, as the `>` actions do.

- **The content stands still while the panel grows.** The panel is centred on the screen
  and its width is animated, overshooting a little before it settles; the content is
  placed in it with `x: (panel.width - width) / 2`, which undoes the panel's movement
  exactly. With `anchors.horizontalCenter` it did not: a centre anchor uses whole or
  half pixels depending on whether the parent's width, cut to an integer, is odd
  (`alignWhenCentered` on the content does not change how the parent's centre is
  taken). Logged per frame, the content jumped within one pixel while the panel grew and
  slid 0.4 px to the right as the width settled, seen as the icons shifting once the
  animation was over. Now every frame has the same position.
- **Apps:** Quickshell's `DesktopEntries`. Started with `kstart --application <id>`, so
  each app gets its own systemd unit and KDE's startup handling instead of being a child
  of the shell. `kstart` never returns for an id it cannot resolve, so it runs under
  `timeout 5`; on failure the entry is started by Quickshell directly.
- **Ranking:** own scorer in `launcher/search.js` (exact, prefix, word start, initials,
  substring, letters in order; name counts most, then generic name, keywords, id,
  comment), with a little added for applications in regular use: launch count halved
  per two weeks since the last launch, stored in Quickshell's state dir
  (`launcher-usage.json`). (Before the menu, the list with no query was ordered by
  that use alone.)
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

Tested for the menu (2026-10-07), on this machine, from pictures of the panel alone:
the favourites (the eleven of KDE's menu, in its order), a category, the session;
"dolph" typed with the test keyboard and its results; a favourite added and taken out
again through IPC, the file as before afterwards; and, in the first layout, whose key
handling this one has: Left and three times Down, which chose Education, then Right
and Down, which chose its application; the menu of the second favourite opened with
Shift+F10, two steps down in it, Escape, after which the launcher was still open. Not
tested: any click (a row, the right button, an entry of the menu, an icon of the
rail), Ctrl+D, opening a place, a session row, pinning from the menu.

To open it with a key: System Settings > Keyboard > Shortcuts > Add New > Command, with
`qs ipc -p /path/to/shell call launcher toggle`. The Meta key alone is wired by KWin to
Plasma's own launcher and was left as it is.

- **Pointer and wheel in the list** (`widgets/PickList.qml`, 2026-10-06). The highlight
  follows the pointer in `Theme.followDuration` (70 ms), not in the 200 ms a key press
  takes: the pointer is already on the row, and a highlight still on its way there read
  as lag. The wheel moves the list by whole rows, one a notch, animated by the list
  itself: ListView's own wheel handling is a flick of about 72 px with the turning's
  speed added, and on 54 px rows with snapping that was now one row, now two, with a
  tug at the end. A touchpad's pixels move the list directly and it settles on a row
  when they stop. Tested: the arithmetic, headless, with made-up wheel events (single
  and quick notches, the ends, small turns adding up, pixels, a key afterwards). Not
  tested: a real wheel.
- **After a key, the pointer must travel 6 px before it selects again** (2026-10-06).
  The selection jumped back to the row under the pointer during keyboard navigation.
  Any movement of a pixel counted as the pointer moving, and a mouse beside a keyboard
  that is typed on moves that much (taken to be the cause; not observed). Tested
  headless with made-up reports: shakes of up to 4 px after a key change nothing, a
  real move selects, and from then on every move does again.

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
- **The list survives a reload of the configuration** (it did not: a Teams message was
  missed on a morning of editing the shell, every saved file emptied the list and put
  out the light). The notifications are KDE's engine's, in the process, and the engine
  keeps them for as long as one model on them exists. Quickshell builds the new
  configuration before it drops the old one (`EngineGeneration::onReload`), so there is
  a moment with both. Three things were needed:
  - The new models are made at once, in that moment (`wanted` starts out as "this
    process is the service"). They used to wait for the announcement on the bus, which
    is asked for anew on every load and answered after the old models had gone, and the
    engine's notifications with them.
  - A model of KDE's, newly made, shows nothing of what the engine already holds, only
    what arrives from then on, until one of its filters is set, even to what it was
    (found by trying: 17 notifications were there after as many reloads, and the list
    empty; setting `showDismissed` or `urgencies` brought them, the sort order did
    not). So each model has `showDismissed` set once when made.
  - The count of unread ones was the service's own and went with it; a
    `PersistentProperties` carried it over, until the history took over what is unread
    (below).
  A notification that arrives during a reload is kept too, the engine never being
  without a model. Tested: count and unread over six reloads in a row, the first reload
  after a start of the shell, and reading the list before a reload.
- **A history on disk, so that nothing is missed over a restart** (asked for after the
  above: "a proper notification history"). The engine and its notifications end with
  the process: a restart of the shell, a crash, a logout. So everything in the list is
  also written to `notifications.json` in the shell's state directory, within 100 ms of
  arriving, and what is in the file but no longer in the list is shown under it as
  "Earlier" until it is closed or the list is cleared. Plasma has nothing like it: its history is gone
  with plasmashell.
  - An earlier one is a record: text, time, icons, urgency. Its application no longer
    knows it, so it has no actions and a click only expands it. A notification's own
    picture is not kept.
  - The file follows the list (`Notifications.reconcile()`, from `Service.listed()`):
    what is in the list is in the file; what the user or its application closes goes
    from the file too. Jobs and transient notifications are not written.
  - Which entries are this run's is told by a `session`: boot id, process id and the
    process's start time from `/proc`. It is the same over a reload and never the same
    after a restart; the process id alone can repeat from one boot to the next.
  - If the list comes back from a reload without something the file has for this run,
    the engine lost it (as it did before the fix above), and the entry is kept as a
    record instead of being taken for closed.
  - **What its application takes back stays as a record.** Reported: the light came on
    for a Teams message and went out after a few seconds. An application can close its
    own notification, the engine then drops it, and the list and the light had nothing
    left (shown with `notify-send -p` and `CloseNotification`). Now a notification that
    goes from the list is kept as a record unless the user closed it, answered it or
    cleared the list (`Notifications.dismiss()`, called by the card). The price: one
    that the application takes back because it was read elsewhere stays too, until it
    is closed here.
  - Whether an entry is unread is in the entry (it arrived while the list was closed,
    and the list has not been opened since); the light follows these. The service no
    longer counts, and nothing needs carrying over a reload.
  - At most 200 earlier ones are kept. The file holds the text of notifications
    (messages, mail subjects) in the clear, readable like the rest of the home
    directory.
  - Tested: two notifications over two reloads, then a restart of the shell (they come
    back as "Earlier", unread), a third after it, more reloads; the list on screen.
    Later: a notification taken back by its sender staying as an unread record, the
    list opened (all read), another taken back, two reloads, and clearing over IPC
    (`qs ipc call notifications clear`, the clear button's function). Not tested:
    closing a single card (live or earlier) by a click, a crash.
- **Grouped by application** (asked for after "a bunch of Teams notifications"). The
  list shows the history's entries, no longer KDE's model with the records under it:
  one application with several notifications is a group, a header with its name and
  how many, the newest card, and the rest when the header is clicked; the cross on the
  header closes them all. An application with one notification is just its card, as
  before, and there is no "Earlier" section any more: live notifications and records
  of one application are one group, newest first, and most of what Teams sends is a
  record within seconds.
  - A card still takes a row of KDE's model where the engine has the notification
    (picture, actions): an `Instantiator` over the model holds a row each, by id, and a
    group's card takes it from there; otherwise the entry dressed as a row.
  - KDE's own grouping (`groupMode`) stays off: it would group the live ones only.
  - Jobs are not in the history; while there are some they are on top of the list.
  - The groups and their cards are `ScriptModel`s over names and keys, so that a card
    stays (expanded or not) while others come and go.
  - Tested with notifications sent for it: four from one application, three taken back
    by the sender, and one from another; the list collapsed and expanded on screen;
    closing the group (through a temporary IPC hook); records and live ones over two
    reloads. Not tested: clicks on the header, its cross and chevron, and a job.
- **Actions only while they work.** KDE's engine marks a notification expired by itself
  about three minutes after it arrived if nothing else did (one minute after its
  timeout, the default counted as two) and tells its application that it is closed; the
  list's first design ("left open towards its application") did not reckon with that.
  Decided: nothing is done against it; an expired card shows no action buttons and a
  click on it does not run the default action. Not tested on screen (it needs a
  notification with actions and three minutes).
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
  goes straight into a list (`notifications/NotificationList.qml`) that lives in the
  frame's bottom left corner:
  - While there are notifications, that corner is rounded much further than the
    others (radius 54, or 72 while some are unread, against 7.5): one even curve from the
    left border to the bottom one. The frame shader gives the hole's bottom left corner
    a radius of its own for this. In the space that fills sits a light. While some
    notifications have not been looked at, it calls: the dot breathes, ripples spread
    from it over the corner, its colour drifts between the accent and mauve
    (`shaders/orb.frag`, on a canvas larger than the corner; it takes no input). Read,
    the light is a dim, still dot; so too in do not disturb.
    First the corner swelled into a small rounded tab instead (a panel in the shader,
    merged with the border): with a fillet on either side it read as a bulge, and one
    curve was wanted.
  - A click there and the list grows out of the corner (`widgets/CornerPanel.qml`, a
    fifth panel in the shader), as the dock grows into the launcher.
    Escape or a click elsewhere closes it (it has the keyboard while open, like the
    launcher). Middle click switches do not disturb. With no
    notifications the corner is like the others; the corner of the border itself (45 px
    of each side) opens the empty list. Also `qs ipc call notifications toggle` and the "Show
    notifications" shortcut.
  - First came a bell in the bar with a dot and a ring on it, the list as a popout
    beside it. It worked; something less like a taskbar icon was wanted.
  - A rebuilt `.qsb` is only used after the shell has been restarted: the running
    process keeps the shader it loaded, across reloads.
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
  - A notification's own picture is shown in the icon's place, filling it, with rounded
    corners and nothing behind it (it was round on a disc; Kirigami drew the picture at
    32 px in the 42 and the disc showed as a ring around it), with the icon small
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
the action). The quiet mode: nothing but critical ones popping up, the count of unread
ones, an action clicked in the list reaching its sender, clear, do not disturb (KDE's
setting written and removed, only the critical one popping up during it), a transient
notification dropped. The corner: the tab and the light by screenshot, and with the
pointer and keys a click opening the list, Escape and a click elsewhere closing it,
middle click for do not disturb, the border's corner opening the empty list. Not tested: the
default action, a link in the body, a job's Pause and Cancel, the do-not-disturb switch
inside the list (only the middle click), a real sandboxed application, real file copies.

## Plasma's panels are parked while the shell runs

While the shell runs, plasmashell's panels are moved 10000 px down, off the screen, by a
KWin script (`kwin/park-panels.js`), and moved back when the shell is gone
(`kwin/unpark-panels.js`). A keeper process (`shell/panels.sh`, started by
`PlasmaPanels.qml`) loads the script over KWin's scripting D-Bus interface and outlives
the shell to undo it, with the same two locks as the shortcuts' keeper. Nothing in Plasma
is changed: the panel, its widgets (the tray with Klipper and the notification helper
among them) and its settings stay as they are and keep running.

- **Why at all:** an auto-hidden Plasma panel comes up when the pointer pushes against
  its edge, here the bottom one, where the shell's dock lives.
- **Why KWin and not Plasma:** a panel has no hidden mode, only always visible,
  auto-hide, dodge windows and windows go below. Its window (`PanelView`) can be hidden
  from QML inside plasmashell, but nothing gives a widget that window unless the widget
  is shown in the panel: a hidden tray widget has no parent item and no window, the
  shell's corona offers no way to its panel views, and a widget shown in the tray of an
  auto-hidden panel is only created once the panel has been drawn. Plasma's scripting
  can only shrink or move a panel, which changes its saved settings.
- **What KWin offers:** a script can set a layer-shell window's `frameGeometry`. KWin
  lays a panel out again whenever Plasma changes something about it, so the script parks
  it again on every geometry change, and parks panels that appear later (plasmashell
  restarted).
- **Off screen, the edge is gone too:** pushed against the bottom edge with a relative
  pointer, the panel stays hidden with the shell running, and comes up as ever with the
  shell stopped.
- **Limit:** a panel that is always visible reserves its strip of the screen through
  the layer-shell protocol, and moving its window does not give that back. Not handled;
  the one panel here auto-hides. Desktop widgets are not touched either.

Tested: where KWin has the panel with the shell running, stopped, started, killed,
restarted at once, and after restarting plasmashell; the edge push in both states; the
panel's settings in Plasma unchanged afterwards.

### The desktop's icons too, and the keepers out of the shell's unit

- **No icons on the desktop while the shell runs** (2026-10-06, at the user's wish: one
  folder lay there, for things to be out of the way). Plasma's desktop is one of two
  layouts, "Folder View" with icons and "Desktop" without, and only its own dialog
  switches them: the type is read-only for scripts and nothing on D-Bus sets it. But
  Folder View has a file filter, and Plasma's scripting can write it: "hide what
  matches `*`", with the list of file types `all/all` (without that list nothing
  matches), is an empty desktop at once. The same keeper as for the panels
  (`panels.sh`) sets it and puts back what was there when the shell is gone; what was
  there is in `~/.local/state/kde-quickshell/desktop-icons-before` meanwhile. No file
  is moved. `panels.sh show-icons` and `hide-icons` do it by hand.
- **The keepers were ended with the shell.** Since the shell is started at login as a
  systemd unit, the keepers (this one and the shortcuts') were processes of that unit,
  and systemd ends a unit's processes with it: nothing was undone, the panels stayed
  parked. They are started in a scope of their own now (`systemd-run --user --scope`).

Tested: the filter written and Plasma's desktop photographed (`grabContainmentImage`
of `org.kde.PlasmaShell`, which shows it without the windows in front): the icon gone,
back, gone; the note not overwritten by a second hiding; the shell's unit stopped: icon
back and the note removed; started: gone. Before the scope: stopped, and nothing came
back. Then the panels and the shortcuts as well, with the unit stopped and started: the
panel where KWin has it (a KWin script printing its geometry: y 11024 parked, 1024
with the shell stopped, 11024 again), and a real Meta+Space, which opens the palette
while the shell runs and KRunner while it does not.

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

## Dock: pinned applications, and icons dragged into place

Asked for: reorder the dock's icons by drag and drop, and pin icons so that they stay
when the application is closed. Both are KDE's task list's own (`TasksModel`), as in
Plasma's task manager; the shell adds the gestures and keeps the list.

- **Pinned applications are KDE's "launchers".** `launcherList` on the dock's
  `TasksModel`, with `separateLaunchers: false` and `launchInPlace: true`: a pinned
  application is in the row without a window too, a click starts it, and its window
  takes the launcher's place. The list is kept in `~/.config/kde-quickshell/dock.json`
  (`shell/Pins.qml`, addresses as KDE writes them, `applications:org.kde.dolphin.desktop`)
  and read again when the file changes.
- **Pinning is in a menu**, on a right click: "Pin to the Dock" or "Unpin from the
  Dock", and for a window "New Window" and "Close". `widgets/ActionMenu.qml`, a popup
  above the icon in the look of the tray's menus, for a plain list of actions (the
  tray's `MenuPopup` is built around an application's menu). Considered: right click
  pins at once, with the hint saying so. One stray click would have removed an icon.
- **A pinned application that is not running is dimmed** (half opacity); a window has
  its icon as it is. First a window had a dot under its icon and the pinned one none;
  the dot was taken out again the same day in favour of this. A minimized window used
  to be dimmed and no longer is: it would look like an application that is not running.
- **The order of the icons is the shell's own**, by application: `order` in the same
  file, pinned or not, running or not. The task list's rows go through a
  `DelegateModel` and are put in that order whenever rows come or go
  (`Taskbar.arrange()`); an application not in it yet goes to the end. So an icon is
  where it was put, also after its application was closed and started again and after
  a restart of the shell. The last 30 applications that are neither here nor pinned are
  remembered, no more.
  - First the order was the task list's (`SortManual`, `launchInPlace`, `move()` and
    `syncLaunchers()`, as Plasma's task manager does it). Reported the same day: a
    pinned application was closed and its icon went to another place. The task list has
    two rows for a pinned application, the launcher (hidden while a window is there)
    and the window, each with its own place in its manual order. They are only together
    if the window opened after the launcher was there. Pin an application that is
    running, or reload the shell while it runs, and the window is at one place and the
    launcher at another, where the icon turns up when the window closes. Reproduced
    with the calculator: pinned while running at the end of the row, closed, and its
    icon was in the middle. Setting the launcher list also re-sorted the whole row.
  - With the order by application the launcher and the window have one key (the
    launcher's address) and so one place.
- **Dragging:** an icon follows the pointer along the row, the others move aside to
  show where it would go (a transform on each, nothing changes meanwhile), and the
  order is changed once when it is let go (`Taskbar.dropped()`): the application goes
  before or after the one it was dropped on.
- **The dock stays out** while an icon is dragged or a menu is open, though the pointer
  has left it: the taskbar names itself in `Pins.holder`, and the dock that contains it
  counts that as wanted.
- **The file is not written before it has been read** (`Pins.ready`). Arranging the
  icons writes the order; at the start that came before the pins had been read, and
  wrote an empty list of pins over the user's four.
- Tested with the virtual pointer: the dots; an icon dragged two places to the left; the
  menu on a right click; "Pin to the Dock" writing the file; a pinned application that
  was not running (through the file) shown in front without a dot; the file removed and
  the pins gone. Headless, the task list has no rows, so the moves could only be tried
  on screen. Not tested: starting a pinned application by a click, unpinning from the
  menu, the pinned order after dragging and a restart, two windows of one application.
- Tested after the change to the shell's own order: the calculator pinned while running
  and closed again stays where it was, dimmed; `dropped()` to the left and to the
  right through a test hook over IPC, the file after it and after a reload. Not on
  screen with the new order: a drag.
- A drag meant for the dock went into the user's Teams window: the dock had not come up
  (the user was using the pointer). No more pointer tests while the user is working;
  logic goes through a temporary IPC hook instead.
- A click meant for the menu went into the user's window: the menu had closed while
  screenshots were taken to make sure it was open. A popup that grabs the focus does
  not outlast other programs; open it and click in one run of `pointer.py`.

## Themes: a file of colours, chosen by name

The shell's colours were constants in `Theme.qml`; they now come from a theme (2026-10-05,
a first experiment). A theme is colours and, if it likes, a background (below). Sizes,
rounding and motion are still fixed.

- **Themes are existing ones**, not made here (2026-10-06): Catppuccin (four), Tokyo
  Night, Gruvbox, Nord, Everforest (two), Kanagawa, Rosé Pine (two), Solarized (two),
  Dracula, Breeze (two). First there were themes generated from each wallpaper's
  colours; the user did not want invented themes, and an existing one has its colours
  for every program already. `tools/theme-from-picture.py` is gone.
- **A theme is `<name>.json`**, `{ "colors": { ... }, "apps": { "nvim": "..." } }`. The
  shell is drawn with `bg`, `surface`, `surfaceHover`, `surfaceActive`, `fg`, `fgDim`,
  `accent`, `accentFg`, `warning`, `error` and `desktops` (a list, one per virtual
  desktop; optionally `tooltipBg`, `tooltipFg`). For what is outside the shell there are
  `view` (the background of what an application shows, where `bg` is its window's) and
  the terminal's: `terminal` (its sixteen colours), `terminalBackground`,
  `terminalForeground`, `terminalCursor`, `terminalSelection`. The terminal's are taken
  as Ghostty ships each theme (`/usr/share/ghostty/themes`), the others from the theme's
  published palette. `apps` names the theme where a program has it under a name of its
  own. In `shell/themes` (the shell's) and in `~/.config/kde-quickshell/themes` (the
  user's; a file there replaces the shell's of the same name, whole). The name shown is
  made from the file's name ("tokyo-night": "Tokyo Night"), so listing the themes reads
  no file.
- **Catppuccin Mocha is in `Theme.qml` itself**, not a file: the shell has its colours
  with no file at all, and a theme may leave colours out. A value that is not `#rgb`,
  `#rrggbb` or `#aarrggbb` is left out too, with a warning in the log.
- **The choice** is `{ "theme": "<name>", "backgrounds": { "<theme>": "<file>" } }` in
  `~/.config/kde-quickshell/theme.json`, written by `Themes.set()` and
  `Themes.setBackground()`: the ">" actions "Theme: ..." and "Background: ..." of the
  launcher and the palette, or `qs ipc call theme set <name>` (also `get`, `list`,
  `backgrounds`, `setBackground`). The file is watched, so writing it by hand changes
  the theme as well.
- **Read before the first frame.** The choice and the chosen theme's file are read
  blocking when `Themes` is made, so the shell never starts in one theme and changes to
  another. Only the list of themes (`FolderListModel`) arrives later.
- **Saving the chosen theme's file recolours the shell**, for working on a theme. A file
  that cannot be parsed changes nothing until it can.
- **A change fades** over `Theme.fadeDuration`. One number, `Theme.blend`, runs from 0
  to 1 and every colour is `Qt.tint(from, Qt.alpha(to, blend))`: one animation for all
  of them, and the list of desktop colours fades too, which a `Behavior` per colour
  could not do.
- **What is watched and what is not.** Quickshell's `FileView` does not notice a file
  that appears where there was none. Hence: the user's theme directory is made at the
  start; a change in it reloads the chosen theme's file; and the choice is read again
  after it has been written.
### A theme's background: one picture or video for desktop, lock screen and login

A theme's backgrounds are the pictures and videos in
`~/.config/kde-quickshell/themes/backgrounds/<theme>/`: to give a theme a background, a
file is put there. The desktop, the lock screen and the login screen show the one chosen
for the theme (the first, until another is chosen); with a theme that has none they show
what they are set to in Plasma. First a theme named one file (`"background": ...`); with
existing themes a theme has several, and which goes with which is the user's to say by
moving a file.

- **The directory is listed by `ls`**, at a change of theme and when something in it
  changes, and the list is kept together with the theme it is of. With a
  `FolderListModel` bound to the theme's directory, a change of theme had the new theme
  and the old theme's files for a moment, and the desktop was given a background that
  does not exist.
- **Each background has a name of its own** for `background.sh` (`<theme>-<file>`): by a
  new name the wallpaper knows a new file.

- **One Plasma wallpaper for all three** (`plasma/background`,
  `io.github.mak1a4.kde-quickshell.background`): the desktop is still plasmashell's, the
  lock screen is KDE's (`kscreenlocker`; KWin has no `ext_session_lock_v1`, so the shell
  cannot lock), and the login screen is Plasma Login Manager's, whose interface is
  compiled in and takes nothing but a wallpaper. A wallpaper plugin is the one thing all
  three load.
- **It has no settings; it shows the one file in a directory.** So a change of theme
  writes no Plasma configuration, it replaces a file (`shell/background.sh`):
  `~/.local/share/kde-quickshell/background` holds a link, and
  `/var/lib/kde-quickshell/background` a copy, because the login screen runs as its own
  user and cannot read a home directory (mode 700 here). The file is named after the
  theme, so that a new theme is a new name and the wallpaper loads it; the wallpaper
  watches both directories and takes the user's first. A video loops, without sound.
- **Taking over and giving back.** With a background, the script sets the desktop's
  wallpaper (Plasma's scripting over D-Bus) and the lock screen's (`kscreenlockerrc`) to
  this one and notes what they had (`~/.local/state/kde-quickshell/wallpaper-before`);
  with a theme without one it puts that back, so the user's own wallpaper and its
  settings are untouched. The login screen cannot be switched without root and keeps this
  wallpaper; it is given a copy of the desktop's picture then.
- **The login screen is kept in step by the shell, which asks for the password**
  (2026-10-06; first a script to be run by hand with `sudo`, which was forgotten, and
  the login screen had neither the background nor the display's scaling).
  `shell/login.sh apply`, as root: installs the wallpaper for everyone, makes the
  directory in `/var/lib`, owned by the user, sets the wallpaper in
  `/etc/plasmalogin.conf.d/kde-quickshell.conf`, and copies the user's `kxkbrc`,
  `kdeglobals`, `plasmarc`, `kcminputrc`, `kwinoutputconfig.json` and
  `fontconfig/fonts.conf` to the login screen's user: what "Apply Plasma Settings" in
  System Settings does (its helper is KAuth over D-Bus, not something a script calls, so
  the six files are copied here, read as the user and written as `plasmalogin`).
  - **Asked only when something changed.** `login.sh check` boils what would be applied
    down to one word and compares it with the one noted at the last `apply`
    (`/var/lib/kde-quickshell/applied`). Not the files as they are: `kdeglobals` changes
    with every file dialog, `kwinoutputconfig.json` with a monitor's brightness and with
    each screen cast's virtual output. Into the word go the wallpaper's files, four of
    the six files whole, the keys of `kdeglobals` for font, colours, icons and scale,
    and of each real monitor its mode, scale and turn.
  - **When:** five seconds after the shell's start (`LoginScreen.qml`), through
    `pkexec`, so the question is Plasma's own dialog. A question that was closed is not
    asked again for that state (`~/.local/state/kde-quickshell/login-declined`); the
    ">" action "Update the login screen" and `qs ipc call login apply` ask anyway. A
    change of scaling during the session is taken up at the next start, not at once.
  - **The dialog explains itself from the second time on:** `apply` installs a polkit
    action naming this script, with a sentence saying what the password is for. The
    first time it is pkexec's bare "run login.sh as the super user".
  - A change of theme needs no root: `background.sh` replaces the copy in `/var/lib`.
  - `sudo shell/login.sh undo` removes what was installed; the copied settings are
    reset in System Settings, Login Screen.
- **Backgrounds from qylock.** `tools/qylock.sh` fetches the backgrounds of
  [qylock](https://github.com/Darkkal44/qylock) that are a wallpaper on their own (30
  of them; not the ones that are a game's menu or need the screen built around them)
  into the directory of the existing theme each goes with best, by eye. About 470 MB,
  not in this repository: most are artwork of games and films.
- **Dead end:** `videoOutput: parent` in a `MediaPlayer` inside its `VideoOutput` showed
  black: a `MediaPlayer` is no `Item` and has no `parent`. It takes the output by `id`.

**Testing the lock screen without locking.** `kscreenlocker_greet --testing` shows the
lock screen as a window. Run in a compositor nobody sees, it disturbs nothing:
`dbus-run-session` around `kwin_wayland --virtual --socket wl-test --no-lockscreen`, the
greeter with `WAYLAND_DISPLAY=wl-test` and an `XDG_CONFIG_HOME` whose `kscreenlockerrc`
names the wallpaper, then `spectacle -b -n -f -o` in the same session photographs the
virtual screen. Started under `setsid`, and ended with `kill -TERM 0`: otherwise the
portals that session starts stay behind.

Tested: the wallpaper on the lock screen that way, with a picture and with a video. On
the real desktop: `forest` (video) and `material-you` (picture) chosen by IPC, the
desktop's and the lock screen's wallpaper switched, the video opened by plasmashell (3 %
of a core), and back to a theme without a background: both as before, `kscreenlockerrc`
byte for byte. Not tested: the real lock screen (only its test mode, which may differ in
what the greeter is allowed to do); the desktop itself was
behind windows and was judged by plasmashell's log, not seen; `tools/qylock.sh`
fetching (the files were already there).

Tested headless (`Theme.qml`, `Themes.qml` and the themes in a scratch config, against a
scratch `XDG_CONFIG_HOME`): start with and without a choice; `set` with a theme, with a
name that does not exist and with a path; the fade; a theme of the user's own added,
changed, broken, mended and removed while chosen; the choice written by hand before and
after the shell wrote it; a choice naming no theme. On screen, by IPC: Catppuccin Latte,
Breeze Light and Gruvbox Dark with the palette open on "Theme: ...". Not tested: Enter on
a theme in the palette or the launcher; panels other than the palette in a light theme
(notifications, mixer, session menu, dock); Breeze Dark and Tokyo Night on screen.

## Theme switcher: the looks as a row of pictures

Themes were chosen from a list of names among the ">" actions. Now there is a switcher
to look through them (2026-10-06), after Caelestia's wallpaper list in its launcher: a
row of pictures, the one in the middle large and ringed in its theme's accent, its
neighbours smaller, moved with the arrow keys, the wheel or a click.

- **A look is a theme with one of its backgrounds**, and a theme without any once, as a
  small drawing of its own colours. One row, not themes and then backgrounds: choosing
  is one step. `shell/looks.sh` lists them and makes a small picture of each background
  with ffmpeg (a video's frame two seconds in) in `~/.cache/kde-quickshell/thumbnails`;
  `Looks.qml` runs it at the shell's start, so the pictures are there when the switcher
  first opens (3 s for 30 the first time, then nothing).
- **It is a mode of the command palette** (`CommandPalette.mode: "themes"`,
  `picker/ThemePicker.qml`), as the clipboard history is: the frame's shader has five
  panels and all are taken, and the palette's panel, its keyboard and its closing were
  there to use. Opened by "Theme switcher" among the ">" actions, `qs ipc call palette
  themes`, or the shortcut "Show theme switcher" (none by default).
- **Looking is not choosing.** The look in the middle, after 120 ms of rest there,
  colours the shell (`Themes.preview`, which `Theme.chosen` is drawn from) and nothing
  else: KDE, the terminals and the desktop keep the theme in use (`Theme.applied`,
  which `ThemeExport` writes down). Enter, or a click on the middle one, chooses theme
  and background together (`Themes.choose`); Escape puts the shell's colours back. The
  preview is kept until the chosen theme's file is read, or the old theme would show
  for a moment in between.
- **The background opens out from the middle.** In the wallpaper (`plasma/background`)
  a new file is loaded into a second layer and seen through a growing disc
  (`MultiEffect` with a mask) over the one before, in 0.9 s, once it has something to
  show; the first file at the start is simply there. For that the directory is never
  empty during a change now (`background.sh` puts the new file there before it takes
  the old one away), and the wallpaper waits 150 ms for the directory to rest: an
  empty directory had it fall back to the login screen's copy for a moment.
- **Dead end:** in the wallpaper the layer's `id` was `layer`. Inside the video's own
  component that name is the `layer` every Item has, the video got no source and never
  showed. It is `pane`.

Tested on the running session, with real key presses (the palette holds the keyboard):
opened by IPC; three looks to the right, the frame in the middle look's colours,
Escape and the frame as before; Enter on a look, and theme, background, KDE's scheme
and the choice file changed; two backgrounds of one theme one after the other; in a
light and a dark theme. The wallpaper's opening in the hidden compositor, on the lock
screen's test mode: picture to video and video to picture, photographed halfway and
after. Not tested: a click or the wheel in the row, the opening on the real desktop
(behind windows; plasmashell opened the files), a theme added while the switcher is
open.

## The theme outside the shell: KDE's colours, terminals, Neovim

A change of theme changes KDE's colours, the terminals, tmux and Neovim with it
(2026-10-06), in the way [Omarchy](https://github.com/basecamp/omarchy) does: the theme
is written down as a flat list of names and values, templates are filled in with it, one
per program, each program is pointed at its file once, and the running ones are told to
read again.

- **`ThemeExport.qml`** writes `~/.local/state/kde-quickshell/theme/colors.json`: every
  colour as `#rrggbb`, as `r,g,b` (`_rgb`) and without the `#` (`_strip`), the sixteen
  terminal colours, a few mixed ones KDE's scheme has names for and a theme does not,
  `mode` (dark or light, by the brightness of `bg`), the theme's name, and the shell's
  sizes. A quarter of a second after the last change: a change of theme is its name
  first and its colours a moment later.
- **`shell/apply.sh`** fills the templates in `shell/themed` (`{{ name }}`) and puts each
  where its program reads it. A program is only told if its file changed, so the script
  runs at every start of the shell.
- **KDE: a colour scheme per theme** (`~/.local/share/color-schemes/Quickshell<Name>.colors`),
  made the current one with `plasma-apply-colorscheme`. That covers Qt and KDE
  applications and window borders, GTK applications through KDE's own settings daemon,
  and **whether the desktop counts as dark or light**: KDE works that out from the
  scheme's window colour, and it is what an application that "follows the system" is
  told (`org.freedesktop.appearance color-scheme` on the portal: 1 with a dark theme, 2
  with a light one, checked). `plasma-apply-colorscheme` refuses the scheme that is
  already current, also when its file has changed, so then Breeze is applied in between.
  What KDE had before the first theme is noted in
  `~/.local/state/kde-quickshell/colorscheme-before`.
- **KDE's selection colour is the accent, made pale** (`selectionFor` in
  `ThemeExport.qml`). Dolphin fills a selected row with a share of the selection colour
  over the view (a third; 65 % under the pointer, measured in a screenshot), puts the
  ordinary text on it, and draws an outline in the colour itself, slightly darker. Two
  things were wrong with the accent as it is. The text had a contrast of 2.2 to 3.6 in
  every theme but Breeze's (4.5 is what text wants; Rosé Pine Dawn, where the user saw
  it: 3.2). And the corners looked pixelated: Dolphin's outline is 1.25 pixels wide
  round a corner of 5, and at the user's 133 % that is drawn in steps (seen at sixteen
  times, Dolphin rendered in the hidden compositor with `--scale 1.3333`); nothing in a
  theme changes that drawing, only how dark the line is against the view. So the accent
  is taken towards the view in steps of 5 % until the text reads at 4.5 and the outline
  stands out from the view by no more than 1.7. That is 65 to 90 % of the way: a pale
  selection, which the user chose over the steps. It is also what KDE draws checked
  boxes and progress bars in. Focus rings and hover outlines keep the accent.
  - **On a light theme nothing highlighted may be lighter than the window** (the user's
    rule). The place one is in, hovered in Dolphin's side bar, was a near-white bar on
    cream. A first explanation (that KDE lightens a hovered selection by a fifth) was a
    guess from one screenshot and wrong, and the limit built on it did not help. What
    it is, found by asking the installed Breeze to paint a row in each state with the
    palette applications really get (a few lines of PyQt, `QStyle::drawPrimitive`, no
    window): in a window that is not the active one KDE uses a selection colour of
    its own, a good deal lighter (`ChangeSelectionColor` in `[ColorEffects:Inactive]`,
    on in Breeze's schemes), and Breeze makes a selected row under the pointer a tenth
    lighter again. Selected, hovered, window not active: `#fef8ff`, to the digit what
    the screenshot had. So the scheme sets `ChangeSelectionColor=false` (a selection
    looks the same in an inactive window), and the softening of the colour ends before
    the colour, a tenth lighter, would stop being darker than the window. All six
    states (hover, selected, both; window active or not) are darker than the window
    now, read back the same way.
- **The icon theme follows the mode** if it comes as a pair (`Papirus-Light`,
  `Papirus-Dark`): dark icons on a dark toolbar otherwise.
- **Terminals:** `ghostty.conf` (Ghostty reads its configuration again at `SIGUSR2`;
  checked that it catches the signal before sending one) and `wezterm.lua` (WezTerm
  watches the file). Whatever runs in a terminal and uses its sixteen colours follows by
  itself (bat, lazygit, yazi, fzf, the prompt).
- **tmux:** `tmux.conf` has the neutral tones (status line, borders), `tmux source-file`
  reloads them; the coloured parts of the status line use the terminal's named colours.
- **Neovim:** `nvim.lua` sets the background and the colour scheme the theme names in
  `apps.nvim` (the theme's own Neovim plugin), and is run again in every open Neovim
  through its server socket.
- **The lock screen's `Look.qml`** is one of the templates too; `Theme.qml` no longer
  writes it.
- **The login screen's colours do not follow a change of theme.** They are copied there
  as root (`login.sh`), and the colour scheme was taken out of what makes the shell ask
  for the password, or every change of theme would. They are those of the last time
  something else was applied, or of "Update the login screen".
- **The user's dotfiles had their own switching** (a `theme-sync` service: Solarized
  light or dark in WezTerm, tmux and Neovim by the name of KDE's global theme). It was
  removed at the user's wish, and the configurations there now include the shell's files
  where they exist, with Solarized by the system's appearance as the fallback.
- **btop:** `~/.config/btop/themes/kde-quickshell.theme` is the theme btop ships of the
  same name where it has one (`apps.btop`), else a template filled in; `btop.conf` names
  that one theme, and a running btop reads it again at `SIGUSR2`.
- **Ghostty's tab bar** is GTK's (libadwaita), which knows light and dark and no
  colour scheme: white over a cream terminal. Ghostty has its own way round that, and
  the generated file uses it (2026-10-07): `window-theme = ghostty`, with
  `window-titlebar-background` and `-foreground` set to the frame's `bg` and `fg`, which
  are also KDE's title bar's: the tab bar continues the title bar. Nothing of GTK's is
  themed for this.
- **GTK applications.** Most have the theme through KDE, which gives its colour scheme
  to its Breeze theme for GTK 3 and 4 (`~/.config/gtk-4.0/colors.css`, with Breeze's
  colour names). Not the ones made with libadwaita (here zenity and Faugus Launcher):
  they take no theme, only light or dark, and stayed neutral grey. They do take
  libadwaita's own colour names from the user's style sheet, so `apply.sh` writes
  those (`themed/gtk4.css.tpl` to `~/.config/gtk-4.0/kde-quickshell.css`: window, view,
  header bar, sidebar, card, dialog, popover, accent and the signal colours) and adds
  one `@import` to `~/.config/gtk-4.0/gtk.css`, which is KDE's file: KDE rewrites it at
  a change of colour scheme and keeps what else is in it. An application reads the
  colours when it starts.
- **VS Code:** the theme's own colour theme by the name VS Code lists it under
  (`apps.vscode`), written into `settings.json` as `workbench.colorTheme` and as both the
  preferred dark and light one: with "follow the system" on, VS Code takes one of those
  and not the first. It reads its settings again by itself. The extensions that hold the
  colour themes are installed by `setup.sh` at the shell's start, once, not at a change
  of theme: an extension is a program.
- **Browsers, Omarchy's way:** Chromium and what is made from it (Helium reads
  Chromium's directory) take `BrowserThemeColor`, the theme's `bg`, from machine policy
  (`/etc/chromium/policies/managed/kde-quickshell.json`), and a running browser takes it
  up when started once more with `--refresh-platform-policy`. Policy is root's to write.
  `login.sh` installs `shell/browser-color.sh` as
  `/usr/local/libexec/kde-quickshell-browser-color`, root's, and a polkit action that
  lets the user's active session run that one file without the password; it accepts six
  hexadecimal digits and writes nothing else, to directories it names itself. Not a
  policy file the user may write: policy can install extensions and set proxies. This
  overrides a colour chosen in the browser (Helium's was a green of the user's own).
  - **Helium with vertical tabs does not take it well.** Tried in a Helium of its own
    (scratch profile, hidden compositor) with eleven colours: the sidebar of the active
    window is the given colour made lighter (black gives `#383838`, the theme's
    `#272e33` gives `#454f57`), never as dark as the theme's frame, and the tabs are
    drawn darker than the sidebar, so a dark neutral colour comes out as a washed slate
    with dark pills. Only the hue and how grey it is can be chosen. Chromium's own
    horizontal tabs look right with the same colour. Open: which colour to give
    (the theme's `bg` as Omarchy does, or one tinted with the accent).
  - **The policy can be switched off** (`"browsers": "system"` in `theme.json`; the ">"
    action "Browsers: colour from KDE", `qs ipc call theme setBrowsers system|policy`).
    While it is there a browser locks its own theme setting ("Theme is set by your
    Organization"), and Helium has a "Use QT" there that takes KDE's colours, which are
    the theme's. With "system" the helper removes the policy file and the shell keeps
    out. Which of the two looks better in Helium is for the user to say.
  - **What "Use QT" takes from KDE**, found by giving every role of the colour scheme a
    loud colour of its own (test Helium, hidden compositor): the sidebar and the toolbar
    are `[Colors:Button] BackgroundNormal`, the "New Tab" pill is `[WM]
    inactiveBackground`, the line round the page is `[Colors:Window] BackgroundNormal`.
    Pinned tabs and other tabs get no box at all in this mode, whatever the colours:
    that is not a colour to be set. So single parts cannot be styled, only these roles
    changed, and they are every KDE application's too.
  - **A browser theme of our own was tried too** (an unpacked extension with a `theme`
    of colours, `--load-extension`, in a test Helium shielded from the machine's policy
    by `bwrap --tmpfs /etc/chromium/policies`). It sets exact colours, but few parts:
    the sidebar, the toolbar and the active tab are `toolbar`; inactive tabs, pinned
    tabs and "New Tab" are all `background_tab`; the texts and icons have their own.
    Pinned tabs have no outline of their own, only that fill, so "tabs as the sidebar,
    pinned tabs outlined" (what the user asked for) is not to be had from outside
    Helium. And a browser only reads such a theme at its start. Not built.
- **Not covered:** Konsole; Firefox.

Tested, on the running session: `everforest`, `solarized-light` and `tokyo-night` chosen
by IPC and each time KDE's scheme, the portal's answer, the icon theme, Ghostty's
configuration, tmux's status style, the colour scheme and background of a running
Neovim, and WezTerm's file read back; GTK's dark setting for one light and one dark
theme; a screenshot with `everforest`. Headless: theme changes with backgrounds in
scratch directories, the list after a change of theme, a stored choice of background, a
file added to the directory. Not tested: WezTerm on screen (it was not running; its
configuration loads), a GTK or Electron application on screen, `tools/qylock.sh`
fetching, Enter on "Background: ..." in the palette. For libadwaita (2026-10-07), in a
hidden compositor with the user's configuration: Faugus Launcher grey-white (`#fafafb`)
under a cream title bar before, the title bar's `#fdf6e3` after, and `#1a1b26` with
`tokyo-night`, chosen for the moment of the picture; `gtk.css` with both imports after
KDE had rewritten it twice; Ghostty's tab bar before and after. For btop, VS Code and the browsers:
`tokyo-night` and `everforest` chosen, and each time the policy file (written without a
question for the password), the name in VS Code's settings and btop's theme file read;
Helium's toolbar seen to lose its green; every theme's VS Code name checked against the
colour themes the installed extensions and VS Code itself declare (three were wrong).
Not seen on screen: VS Code and btop themselves.

## Lock screen: KDE's locker, the shell's interface

The session is locked by KDE (`kscreenlocker`); the shell cannot do it, KWin has no
`ext_session_lock_v1`. But the locker's whole interface is QML, and `plasma/lockscreen`
replaces it (2026-10-05): the shell's frame round the wallpaper, a clock on it, and two
panels that come out of the frame at a key or a move of the pointer and go back after
ten idle seconds or at Escape. From the top edge, where the command palette hangs, the
password: a pill as the palette's field, the user's picture or initial in it, the
palette's key hints below. From the bottom edge, where the dock is: sleep, hibernate,
switch user, as far as the session allows them.

- **The frame is the shell's own shader** (`shell/shaders/frame.frag.qsb`, copied in at
  installation), so the panels flow out of the border with the same fillets and
  overshoot. Plain Qt Quick otherwise; no Plasma components, which is what made it look
  like Plasma.
- **Colours and sizes come from the shell in a file.** The locker is another program
  and cannot read the theme. `Theme.qml` writes `~/.local/share/kde-quickshell/lock/Look.qml`
  at its start and at each change of theme, a `QtObject` of properties, and the lock
  screen loads it with a `Loader`; without the file it has `DefaultLook.qml` (Catppuccin
  Mocha). A QML file because that is what plain QML can read: reading JSON from a file
  is switched off in Qt 6.
- **How the locker is made to use it.** It takes the interface from the "shell package"
  Plasma runs with: `ShellPackage` in `plasmashellrc`, else `PLASMA_DEFAULT_SHELL`, else
  `org.kde.plasma.desktop`. Setting the first would change plasmashell as well (another
  package, another file of panels and widgets). A copy of Plasma's package in the home
  directory with the lock screen exchanged would go stale at every Plasma update. So:
  the package holds nothing but `contents/lockscreen`, and the variable is set for KWin's
  service alone (`~/.config/systemd/user/plasma-kwin_wayland.service.d/kde-quickshell-lock.conf`),
  because KWin starts the locker and plasmashell is another service. The shell does
  both at its start (`setup.sh`, see "Setup"), and takes both away again when
  `setup.json` says `"lockscreen": false`. KWin has its environment from its start, so
  it counts from the next login; a changed lock screen is copied at the shell's next
  start and shown at the next lock.
- **If it fails.** QML that does not load: the locker shows its built-in screen. QML
  that loads and cannot be used: `loginctl unlock-sessions` from a console.
- **What is not there** of Plasma's lock screen: media controls, the on-screen keyboard,
  the keyboard layout button, the battery, volume and brightness messages, the hints for
  fingerprint and smartcard (they still unlock; nothing says so).
- **Behaviour kept from Plasma's:** the password is shared between the monitors'
  screens (`PasswordSync`); a wrong one blocks the field for three seconds and clears
  it; typed text is cleared before the machine sleeps; a session unlocked without a
  password having been asked for waits for Enter. The Enter that only brought the panel
  out is not sent as an empty password.

Tested in the hidden compositor (see "Testing the lock screen without locking"), in the
locker's test mode: idle; the panels out (by changed copies of the QML: there is no
keyboard in that compositor); a password in the field; the look after a wrong password;
that the field has the keyboard focus and the window is active; the theme's colours
from `Look.qml`; the package found through `PLASMA_DEFAULT_SHELL` with the user's own
`plasmashellrc`; installing and removing it against scratch directories. Not
tested: anything in the real locker (it has the environment only after a login): typing,
unlocking, a wrong password as PAM reports it, sleep and switch user, the motion of the
panels (only stills were taken), two monitors, a user picture (this user has none).

## Setup: looked at each time the shell starts

The shell is meant to be all there is to install: start it once (`qs -p shell`) and it
puts in place what it needs outside itself, and at every later start looks whether that
is still so. `setup.sh` does the looking and the putting, `Setup.qml` runs it eight
seconds after the start (2026-10-06).

- **One line for each thing**, with one of four words. `ok`. `fixed`: was missing or
  stale and has been put right. `note`: as it is for a reason, or not the shell's to
  change. `problem`: wrong, and nothing this can put right.
- **What it puts in place:** the desktop entry that gives the shell the window list
  (`packaging/kde-quickshell.desktop`, and `kbuildsycoca6`); the autostart entry, once;
  the lock screen's package and the drop-in that names it for KWin (what
  `tools/lockscreen.sh` did by hand; that tool is gone); VS Code's extensions for the
  themes, asked for once and again when the list changes, since asking VS Code takes a
  second or two; the country whose holidays the calendar shows (see "Clock").
- **What it only says:** programs that are not installed; a package of ours in
  `~/.local/share/plasma` whose files are links (Plasma refuses those: the black
  desktop after a reboot, when a dotfiles manager had linked them); `ShellPackage` named
  in `plasmashellrc` (the locker then takes that one's interface); the login screen
  behind the session; a keeper that is not running; KDE's colour scheme not the
  theme's; a terminal, tmux or Neovim that is installed and whose configuration does
  not name the theme's file; no backgrounds.
- **Why the last ones are only said.** Those configurations are the user's, here links
  into a dotfiles repository, two of them programs (Lua). A line appended to them by a
  shell at its start is a change to someone's repository that they did not make. The
  note says which line it is.
- **Root's part stays where it was.** The login screen and the browsers' helper are
  `login.sh`'s, asked for with the password by `LoginScreen.qml`; `setup.sh` reports
  how that stands and is looked at again when it has changed. `login.sh` no longer
  takes Plasma Login Manager for granted: without it (`login.sh greeter` says `no`)
  only the helper and its polkit rule are installed, and `check` asks for no more.
- **Saying it.** Nothing when all is well. A notification for what was put right; one
  for what is wrong, when it is new (`setup-told` in the state directory holds what
  was said, so a reload a minute later is quiet). "Check the shell's setup" among the
  ">" actions looks again and says everything; each thing that is not `ok` is an action
  of its own there ("Setup: ..."), with what there is to say as its second line.
  `qs ipc call setup report` gives all lines, `setup check` looks again.
- **Switching parts off:** `~/.config/kde-quickshell/setup.json`, `{ "lockscreen":
  false, "autostart": false, "vscode": false }`, each on unless it says false.
  `"lockscreen": false` also removes what was installed.
- **A trap in QML's JavaScript:** `const [state, id, title, detail] = line.split("\t")`
  in a loop left `title` and `detail` with the values of the line before when a line
  had fewer parts, so the empty last line became a seventeenth thing. Taken apart by
  index instead.

Tested: against empty scratch directories for configuration, data and state (first run
makes the entries and the lock screen, second run changes nothing, a removed autostart
entry stays removed, one that starts something else is pointed here, `"lockscreen":
false` removes and then says so); `login.sh` with and without a greeter against a
scratch root; on this machine: all sixteen `ok`, the desktop entry taken away and put
back by `setup check` with its notification, a restart of the shell with the report
there afterwards and no question for the password. Not tested: a machine that really
has nothing of it yet, a machine without Plasma Login Manager, a failing
`code --install-extension`.

## Started at login by a KDE autostart entry

`~/.config/autostart/kde-quickshell-shell.desktop` runs
`/usr/bin/qs -n -p <this repository>/shell` (2026-10-06). KDE makes a systemd unit of it
(`app-kde\x2dquickshell\x2dshell@autostart.service`), and it shows in System Settings
under Autostart, where it can be switched off. Not in this repository: the path in it is
this machine's, and it has to be the exact path `qs ipc -p` is called with. No `-d`: the
unit should hold the process. The unit does not restart a shell that has ended.

The shell makes the entry itself the first time it runs (`setup.sh`, see "Setup"), with
the path it was started by. Once: an entry that is gone afterwards was taken away by
the user and is not put back (`~/.local/state/kde-quickshell/autostart-made` is the
note of that), and one switched off in System Settings stays off. An entry that starts
something other than this shell is pointed at it.

Tested: the generated unit started by hand, the shell up and answering IPC. Not tested:
a login.

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

An absolute device cannot push against a screen edge, which is what brings an
auto-hidden panel up. For that, a relative one: a uinput device with `REL_X`/`REL_Y`,
sending a run of movements towards the edge.

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

**Tray items in the bar's own style.** A tray icon in colour (Outlook, Teams, the
portal's "Remote Control") stood out among the one-colour icons of the bar. An item can
be drawn through `widgets/Icon.qml` instead, with an icon chosen for it; every other item
keeps the icon it brings.
- **Chosen in the settings window**, section "Icons in the Bar": one row per item in the
  tray (and per choice for an item that is not there now, to forget it). The button opens
  a list of every icon there is to choose from, with a search field: the Tabler glyphs in
  `shell/icons/tabler` and the icon theme's one-colour icons, which are its symbolic
  icons and Papirus' `panel` directories (tray icons for many applications, e.g.
  `teams-for-linux-tray`); `shell/icons.sh` lists them, about 6000 here. They are
  drawn in one colour, as the bar will. A click sets the icon at once and the bar shows
  it, so the list stays open for trying another. Below it: "Its Own Icon", and "Default"
  where the shell has one.
- **Kept in** `~/.config/kde-quickshell/bar-items.json`, written by the settings and
  read again by the shell whenever it changes (`shell/BarItems.qml`): per item key an
  `icon` (a theme name, `tabler/<name>`, or `""` for the item's own) and a `hide`
  (`"always"` or `"idle"`), either or both. An item with nothing chosen has no entry.
- **Hiding.** Each row also says when the item is in the bar: shown, hidden while idle,
  or hidden. A hidden item is not gone: while anything is hidden an arrow sits on top of
  the bar's lower group, a click on it brings the hidden items into the bar in their
  places and a second click puts them away (also `qs ipc call bar toggleHidden`). One
  hidden while idle comes back by itself while its status is "needs attention" or its
  tooltip has a count. The status "passive" is not used for this: Electron applications
  are "active" all the time, so it says nothing for the items one would hide (Teams).
- **The bar's own modules too** (media, KDE Connect, network, volume, power, session):
  the section is called "Icons in the Bar", and a list of only the tray's three was
  asked about at once. They have a row each, shown or hidden, and no icon to choose:
  a module draws its state (the volume, the kind of network, play or pause). The row
  shows the icon the module has in the bar at that moment: `widgets/Icon.qml` reports a
  module's icon to `BarItems`, and the settings ask the running shell every 3 s
  (`qs ipc call bar moduleIcons`). A fixed stand-in per module was there first and was
  asked about at once ("shouldn't this be the icon we actually use?"); it is now only
  for when the shell is not running. One of them, `battery-profile-balanced-symbolic`,
  which Papirus leaves to Breeze, came out as a filled disc at the window's 22 px (cause
  not found), so every icon in the list is now drawn as the bar draws it: in an 18 px
  square, which Kirigami rounds to the 16 px drawing, glyphs at 21 px. Which
  modules there are is a list in `symbols.js`; each calls `BarItems.tucked("<name>")`.
  Putting away is `BarButton`'s (`tucked`): the cell shrinks to nothing and is then
  invisible, so the layout gives it no spacing either; `Guarded` follows its module's
  height for the same reason. Known gap: a hidden module that shows nothing anyway (the
  media player without a player) still counts, so the arrow can be there with nothing
  behind it.
- **An item's own icon, if it is one of the theme's one-colour icons, is drawn in the
  bar's colour** (a name ending in `-symbolic`, or in the list `icons.sh` gives, which
  the shell reads once at its start). KDE's microphone indicator names
  `microphone-sensitivity-high`, a Papirus panel icon: drawn as it comes it has the
  theme's colour for text on a light panel, dark grey on the dark bar. An icon in
  colour is still drawn as it comes. Tried first: Kirigami's icon without the mask and
  with the bar's colour, in the hope that only the icon's text colour would be
  replaced; in this process it replaces nothing. Tested with tray items made for it
  (PyQt's `QSystemTrayIcon` with a theme icon): the microphone, its muted form (dim,
  as the theme draws it) and an application's icon in colour. A Python test item does
  not end on SIGTERM unless the default handler is put back; nine of them stayed in
  the user's bar for some minutes.
- **Defaults** are in `modules/tray/symbols.js`: Outlook, Teams and Remote Control have an
  icon unasked. An item is recognised by the icon it names (`krfb`) or by a word in its
  id, title or tooltip.
- **The key** a choice is filed under is the item's id (with its title, if it has one).
  Electron applications send only a pixmap and an id like `chrome_status_icon_1`, so for
  Outlook the tooltip without its count is the key.
- **The same cell for every item.** A tray item is a `BarButton` like the other modules,
  with the bar's spacing (before: 30 px rows without spacing, closer together than the
  rest, which were 36 px cells 3 px apart). With all of them 39 px apart the lower group
  was too loose, so every cell is now 30 px high with none between
  (`Theme.barButtonHeight`, `Theme.barSpacing`): 12 px from one icon to the next. The icon is centred in the bar's 18 px square whatever it is. A Tabler glyph is
  drawn at 21 px without Kirigami's rounding to standard sizes: it keeps an eighth of its
  width clear on every side, where the theme's symbolic icons (which Kirigami draws at
  16 px in that square) nearly reach the edges, so at 18 px it looked smaller than its
  neighbours.
- Teams paints its unread count into its pixmap, which a replacement loses. The count
  is also at the end of the tooltip ("Microsoft Teams (2)"): when one is there, the icon
  gets a dot.
- `settings/symbols.js` is a link to the shell's: both sides must agree on keys and on
  how an icon is written, and Quickshell loads no script from outside a config's own
  directory (`import "../shell/..."` fails with "qs-blackhole").
- **Tried and dropped:** KDE's icon chooser (`org.kde.iconthemes` `IconDialog`). It opens
  on the theme's application icons in colour, and its `customLocation` did not show the
  Tabler directory. A general rule that takes `<name>-symbolic` whenever the theme has
  it: `Kirigami.Icon` reports `valid` for names the theme does not have, so the shell
  cannot tell. The tray rows in the shortcuts' `FormLayout`: rows arrive as KDE and the
  tray answer and the form keeps them in that order, so the lists mixed (as did a note
  put after the rows, now below the form); and it warns about every row taken from it,
  hence a `ScriptModel` over the keys.
- Under an icon theme without a chosen name the item shows Kirigami's "unknown" icon.
  Only the Tabler glyphs that `tools/tabler.sh` has fetched are offered (those the
  notifications use). Editing `symbols.js` does not reload the shell; restart it.
- Tested: the settings' code headless (list of items; choosing, resetting, hiding and
  forgetting, and the file after each); a choice written by it showing in the running
  bar and going again on reset; hidden items leaving the bar, coming with the arrow's
  toggle (over IPC) and going again, the same with two modules; the list of icons on screen, opened by a timer; the
  window's layout drawn off screen (`grabToImage` under `QT_QPA_PLATFORM=offscreen`,
  which has no icon theme). Not tested: clicks in the window, in the list and on the
  arrow, and an item coming back from "hidden while idle" (nothing had a count then).
- A screenshot of "the active window" (`spectacle -a`) right after starting the settings
  took the user's browser instead when that kept the focus. Draw off screen instead.

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
- **One menu at a time** (2026-10-08), the tray's and the dock's (`ActionMenu`) alike:
  `Popouts.menu` is the one that is open, a menu is mapped only while it is that one,
  and one that opens closes the other first. Before, a right click on a second tray
  icon opened its menu with the first still there: a press on the frame that an icon
  accepts does not dismiss a grabbing popup (only a press nothing accepts does, or one
  on another program), and Qt made the second popup a child of the first ("does not
  match the current topmost grabbing popup" in the log), with both icons lit.
- **Nothing on the frame is hovered while a menu is open:** a `MouseArea` over the whole
  frame takes the hovering then, so no icon lights up and no hint comes out. A press
  on it closes the menu and is passed on (`mouse.accepted = false`), so a right click
  on another icon opens that one's menu and a left click does what it always does.
  The icon the menu belongs to is left to close it itself. An icon under the pointer
  when the overlay comes or goes keeps its state until the pointer next moves.
- Tested 2026-10-08 without the pointer (the user was working): the real `ActionMenu`
  and `MenuPopup` (with the menus of two running tray items) in a scratch config drawn
  off screen, opened over one another in every order, the first always hidden before
  the second showed; the overlay's hover and press behaviour in a `qmltestrunner` case
  of its own. Not tested: real clicks on the bar.

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
