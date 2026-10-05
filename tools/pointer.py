#!/usr/bin/env python3
"""Moves and clicks a virtual pointer, to exercise the shell's mouse handling.

Like keys.py it enters through the kernel (uinput), as an absolute pointing
device, so KWin and the layer surface's input region are part of what is
tested. It moves the real cursor: the user sees it jump, and a click lands on
whatever is there. Look at a screenshot first, click only where the shell is,
and put the cursor back afterwards.

    tools/pointer.py 1920x1080 move:1700,40          to a position
    tools/pointer.py 1920x1080 move:1700,40 click    then a left click
    tools/pointer.py 1920x1080 move:1700,40 middle   a middle click
    tools/pointer.py 1920x1080 move:1700,40 right    a right click
    tools/pointer.py 1920x1080 drag:1700,40:1900,40:0.4   press, move there in 0.4 s, release
    tools/pointer.py 1920x1080 sleep:0.5             a pause between steps

The first argument is the screen's size in the units the positions are given
in (logical pixels, as QML sees them). One screen is assumed.

Needs python-evdev and write access to /dev/uinput.
"""

import sys
import time

from evdev import AbsInfo, UInput, ecodes

RANGE = 65535


def main(arguments):
    if len(arguments) < 2:
        sys.exit(__doc__)
    width, height = (float(part) for part in arguments[0].split("x"))
    pointer = UInput({
        ecodes.EV_KEY: [ecodes.BTN_LEFT, ecodes.BTN_MIDDLE, ecodes.BTN_RIGHT],
        ecodes.EV_ABS: [
            (ecodes.ABS_X, AbsInfo(0, 0, RANGE, 0, 0, 0)),
            (ecodes.ABS_Y, AbsInfo(0, 0, RANGE, 0, 0, 0)),
        ],
    }, name="kde-quickshell test pointer")
    # the compositor needs a moment to take up a new device
    time.sleep(1.0)

    def move(x, y):
        pointer.write(ecodes.EV_ABS, ecodes.ABS_X, round(x / width * RANGE))
        pointer.write(ecodes.EV_ABS, ecodes.ABS_Y, round(y / height * RANGE))
        pointer.syn()
        time.sleep(0.03)

    def button(code, down):
        pointer.write(ecodes.EV_KEY, code, 1 if down else 0)
        pointer.syn()
        time.sleep(0.05)

    def point(text):
        x, y = text.split(",")
        return float(x), float(y)

    try:
        for step in arguments[1:]:
            kind, _, rest = step.partition(":")
            if kind == "sleep":
                time.sleep(float(rest))
            elif kind == "move":
                x, y = point(rest)
                # twice, a pixel apart: a device that reports the position it
                # already has produces no event
                move(x - 1, y)
                move(x, y)
            elif kind in ("click", "middle", "right"):
                code = {"click": ecodes.BTN_LEFT, "middle": ecodes.BTN_MIDDLE, "right": ecodes.BTN_RIGHT}[kind]
                button(code, True)
                button(code, False)
            elif kind == "drag":
                start, end, seconds = rest.split(":")
                (x1, y1), (x2, y2) = point(start), point(end)
                move(x1 - 1, y1)
                move(x1, y1)
                button(ecodes.BTN_LEFT, True)
                steps = max(2, int(float(seconds) / 0.016))
                for n in range(1, steps + 1):
                    pointer.write(ecodes.EV_ABS, ecodes.ABS_X, round((x1 + (x2 - x1) * n / steps) / width * RANGE))
                    pointer.write(ecodes.EV_ABS, ecodes.ABS_Y, round((y1 + (y2 - y1) * n / steps) / height * RANGE))
                    pointer.syn()
                    time.sleep(0.016)
                button(ecodes.BTN_LEFT, False)
            else:
                sys.exit(f"pointer.py: unknown step {step!r}")
            time.sleep(0.1)
    finally:
        pointer.close()


if __name__ == "__main__":
    main(sys.argv[1:])
