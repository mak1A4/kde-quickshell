#!/usr/bin/env python3
"""Presses keys on a virtual keyboard, to exercise the shell's key handling.

The keys enter through the kernel (uinput) like a real keyboard's, so they take
the whole path: KWin, global shortcuts, keyboard focus, the layer surface. They
go to whatever has the focus, exactly as if typed. Before sending Enter, make
sure the shell has it: type a letter and read it back with
`qs ipc call palette query`.

    tools/keys.py ctrl+space            a chord
    tools/keys.py down down enter       keys in sequence
    tools/keys.py hold:down:1.5         held for 1.5 s (the client auto-repeats)
    tools/keys.py type:filelight        letters, digits and spaces
    tools/keys.py sleep:0.5             a pause between steps
    tools/keys.py gap:0.01 type:ab enter   following keys this close together

Key names are evdev's without the KEY_ prefix (down, enter, tab, esc,
pagedown, backspace, ...); ctrl, shift, alt and meta are the left modifiers.
Letters are sent as key positions, so on a layout other than US some come out
as their neighbours (y/z on German).

Needs python-evdev and write access to /dev/uinput.
"""

import sys
import time

from evdev import UInput, ecodes

MODIFIERS = {"ctrl": "LEFTCTRL", "shift": "LEFTSHIFT", "alt": "LEFTALT", "meta": "LEFTMETA"}
# time a key stays down, and the gap before the next one
TAP = 0.03
GAP = 0.09


def code(name):
    name = MODIFIERS.get(name.lower(), name.upper())
    if name == " ":
        name = "SPACE"
    try:
        return getattr(ecodes, "KEY_" + name)
    except AttributeError:
        sys.exit(f"keys.py: no key named {name!r}")


def main(steps):
    if not steps:
        sys.exit(__doc__)
    keyboard = UInput(name="kde-quickshell test keyboard")
    # the compositor needs a moment to take up a new keyboard
    time.sleep(1.0)

    gap = GAP

    def press(codes, held=TAP):
        for key in codes:
            keyboard.write(ecodes.EV_KEY, key, 1)
            keyboard.syn()
        time.sleep(held)
        for key in reversed(codes):
            keyboard.write(ecodes.EV_KEY, key, 0)
            keyboard.syn()
        time.sleep(gap)

    try:
        for step in steps:
            kind, _, rest = step.partition(":")
            if kind == "sleep":
                time.sleep(float(rest))
            elif kind == "gap":
                gap = float(rest)
            elif kind == "type":
                for letter in rest:
                    press([code(letter)])
            elif kind == "hold":
                name, _, seconds = rest.partition(":")
                press([code(part) for part in name.split("+")], float(seconds))
            else:
                press([code(part) for part in step.split("+")])
    finally:
        keyboard.close()


if __name__ == "__main__":
    main(sys.argv[1:])
