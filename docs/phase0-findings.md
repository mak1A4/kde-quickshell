# Phase 0 findings

Tested 2026-10-03 on CachyOS, Plasma/KWin 6.7.5 (Wayland), Qt 6.11.2, Quickshell 0.3.1,
DP-1 2560x1440 @165Hz, scale 1.333.

**Update, same day:** the spike first ran against the official package extracted to a
temp dir. After `quickshell 0.3.1-1.1` was installed, the grant was re-tested at
`/usr/bin/quickshell` and works; the portal warning noted below is gone.

## Verdict

The architecture holds. Nothing in Phase 0 needs a C++ plugin.

| Step | Result |
|---|---|
| 1. Protocol survey | Layer-shell yes. No foreign-toplevel, session-lock or screencopy protocols. |
| 2. Bar at 1.333 | Works, rendered 1:1 on device pixels. |
| 3. `import org.kde.taskmanager` | Imports fine. Model stays empty: KWin denies the protocol. |
| 4. Desktop-entry grant | Works. Windows listed live, click-to-activate wired up. |
| 5. Virtual desktops via D-Bus | Works, including live create / switch / remove. |

## 1. What KWin advertises (to an unprivileged client)

| Need | Protocol | Status |
|---|---|---|
| Panels / overlays | `zwlr_layer_shell_v1` v5 | yes |
| Fractional scale | `wp_fractional_scale_manager_v1`, `wp_viewporter` | yes |
| Blur behind surfaces | `ext_background_effect_manager_v1` | yes |
| Virtual desktops | `org_kde_plasma_virtual_desktop_management` v4 | yes, unrestricted |
| Panel roles, shadows, slide | `org_kde_plasma_shell` v8, `org_kde_kwin_shadow_manager`, `org_kde_kwin_slide_manager` | yes |
| Idle | `ext_idle_notifier_v1`, `zwp_idle_inhibit_manager_v1` | yes |
| Clipboard manager | `ext_data_control_manager_v1` | yes |
| Window list | `org_kde_plasma_window_management` | hidden unless granted (step 4) |
| Window list (generic) | `ext_foreign_toplevel_list_v1`, `zwlr_foreign_toplevel_management_v1` | **not implemented** |
| Lock screen | `ext_session_lock_v1` | **not implemented** |
| Screen capture | `wlr-screencopy`, `ext-image-copy-capture` | **not implemented** (KWin has restricted `zkde_screencast_unstable_v1`) |

Consequences for Quickshell modules: `ToplevelManager` returns 0 toplevels, and
`WlSessionLock` / `ScreencopyView` have no backing protocol. That matches the plan (KDE
keeps the lock screen; screenshots go through KWin D-Bus).

## 2. Bar crispness

Confirmed from the protocol trace, not by eye: KWin sends `preferred_scale(160)`
(160/120 = 1.333), Quickshell allocates a 2560-px-wide buffer and sets the viewport
destination to 1920 logical px. No compositor resampling.

- `screen.devicePixelRatio` reports **2** (legacy integer `wl_output` scale). Don't use it
  for layout maths.
- At 1.333 only multiples of 3 logical px land on whole device pixels (32 -> 42.67).
  The bar is 30 (= 40 device px).

## 3 + 4. Window list

`org.kde.taskmanager` loads in Quickshell straight from the system QML path; no plugin,
no `QML_IMPORT_PATH`. Without a grant, `TasksModel.count` stays 0 and libtaskmanager logs
`The PlasmaWindowManagement protocol hasn't activated in time`.

With a desktop entry carrying
`X-KDE-Wayland-Interfaces=org_kde_plasma_window_management`, all 5 open windows appeared
with app id, title and active state, updating live.

How the grant really works:

- KWin matches the client's `/proc/<pid>/exe` against `Exec=` of installed desktop
  entries. **Launching via the desktop file is not required**; `qs -p shell` from a
  terminal gets the grant too.
- The entry must be visible to KSycoca (`~/.local/share/applications` is fine). Run
  `kbuildsycoca6` after adding it, then restart Quickshell.
- The grant is per binary: every Quickshell config on the machine gets it.
- Symlinks are resolved, so a renamed symlink cannot get a separate grant.
- The upstream `org.quickshell.desktop` has no `Exec=` line, so it doesn't collide.

Limitation: libtaskmanager exposes no "denied" flag. An empty model means either no
windows or no access, so the bar says exactly that. A definite answer needs a few lines
of C++ checking the registry for the global.

## 5. Virtual desktops

`org.kde.KWin /VirtualDesktopManager` is readable and writable without any grant.
Quickshell has no generic D-Bus client, so `VirtualDesktops.qml` runs `busctl`: one
long-lived `monitor` for signals, one `GetAll` per change. Verified by creating a second
desktop, switching to it and back, and removing it; the bar followed each change.
Click-to-switch in the bar uses the same `current` property but was not clicked by hand.

Alternative found on the way: `VirtualDesktopInfo` from the same `org.kde.taskmanager`
module returns identical data over the Wayland protocol, with no grant and no subprocess.
Correction to the first version of this report: in Plasma 6.7 it exposes **no**
activate / create / remove calls to QML, so it is read-only. Phase 1 reads from it and
switches desktops through the D-Bus `current` property.

## Other probes

- `org.kde.KWin.NightLight`: open, properties readable (enabled, temperature, mode).
- `org.kde.KWin.ScreenShot2` (v5): present, but callers need
  `X-KDE-DBUS-Restricted-Interfaces=org.kde.KWin.ScreenShot2` in their desktop entry, the
  same exe-matching mechanism as step 4.
- `ActivityInfo` from `org.kde.taskmanager` works.
- The bar gets rounded corners that the config doesn't draw, most likely from the
  ShapeCorners KWin effect on this machine treating the layer surface like a window.
- `Failed to register with host portal ... App info not found for 'org.quickshell'` is
  logged at startup with the temp-dir install only; gone with the real package.

## Fallback states (both seen on screen)

- Protocol denied: `no windows (or KWin denied window management)`
- QML module missing: `taskbar: org.kde.taskmanager not loadable`, rest of the bar intact
- D-Bus read fails: `desktops: KWin D-Bus unavailable` (code path present, not triggered)

## To run

```sh
install -Dm644 packaging/kde-quickshell.desktop ~/.local/share/applications/kde-quickshell.desktop
kbuildsycoca6
qs -p shell
```

(Since 2026-10-06 the shell installs the entry itself at its start, `shell/setup.sh`;
`qs -p shell` is enough, and a second start has the window list.)

## Open questions (resolved 2026-10-03)

1. Desktops backend: `VirtualDesktopInfo` for state, D-Bus only for switching.
2. Grant scope: per-binary grant accepted.
3. "Access denied" detection: stays heuristic until the Phase 3 plugin.
