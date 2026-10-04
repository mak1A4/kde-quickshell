.pragma library

// Key combinations between the two forms KDE uses: the text of a
// QKeySequence ("Meta+Space", what QML sees) and the number KGlobalAccel
// takes over D-Bus (Qt key code plus modifier bits). QML has no way to ask Qt
// for the conversion, hence the tables. One key combination only, no chords.

// in the order Qt writes them
const modifiers = [["Meta", 0x10000000], ["Ctrl", 0x04000000], ["Alt", 0x08000000], ["Shift", 0x02000000], ["Num", 0x20000000]];
const modifierMask = 0x3e000000;

// Qt's names for the keys that are not a single character
const named = {
    "Space": 0x20,
    "Esc": 0x01000000,
    "Tab": 0x01000001,
    "Backtab": 0x01000002,
    "Backspace": 0x01000003,
    "Return": 0x01000004,
    "Enter": 0x01000005,
    "Ins": 0x01000006,
    "Del": 0x01000007,
    "Pause": 0x01000008,
    "Print": 0x01000009,
    "SysReq": 0x0100000a,
    "Home": 0x01000010,
    "End": 0x01000011,
    "Left": 0x01000012,
    "Up": 0x01000013,
    "Right": 0x01000014,
    "Down": 0x01000015,
    "PgUp": 0x01000016,
    "PgDown": 0x01000017,
    "CapsLock": 0x01000024,
    "NumLock": 0x01000025,
    "ScrollLock": 0x01000026,
    "Menu": 0x01000055,
    "Help": 0x01000058,
    "Back": 0x01000061,
    "Forward": 0x01000062,
    "Volume Down": 0x01000070,
    "Volume Mute": 0x01000071,
    "Volume Up": 0x01000072,
    "Media Play": 0x01000080,
    "Media Stop": 0x01000081,
    "Media Previous": 0x01000082,
    "Media Next": 0x01000083,
    "Home Page": 0x01000090,
    "Favorites": 0x01000091,
    "Search": 0x01000092
};
// F1 to F35
for (let n = 1; n <= 35; n++)
    named["F" + n] = 0x01000030 + n - 1;

// "Meta+Space" -> number; 0 for no shortcut, null for text this table does
// not cover (a chord, an unusual key)
function toInt(text) {
    if (text === "")
        return 0;
    let rest = text, bits = 0;
    for (let found = true; found; ) {
        found = false;
        for (const [name, bit] of modifiers) {
            // "Ctrl++" is Ctrl and the plus key: a modifier is only cut off
            // while something follows it
            if (rest.startsWith(name + "+") && rest.length > name.length + 1) {
                rest = rest.slice(name.length + 1);
                bits |= bit;
                found = true;
            }
        }
    }
    if (rest in named)
        return bits | named[rest];
    if ([...rest].length === 1)
        return bits | rest.toUpperCase().codePointAt(0);
    return null;
}

// number -> "Meta+Space"; "" for none
function toText(value) {
    if (!value)
        return "";
    const key = value & ~modifierMask;
    let text = "";
    for (const [name, bit] of modifiers)
        if (value & bit)
            text += name + "+";
    for (const name in named)
        if (named[name] === key)
            return text + name;
    return key < 0x01000000 ? text + String.fromCodePoint(key) : "";
}
