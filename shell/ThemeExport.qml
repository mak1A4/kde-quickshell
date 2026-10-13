pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// The theme for everything that is not the shell: KDE's colours (and with
// them whether the desktop counts as dark or light, which applications that
// "follow the system" ask for), the terminals, tmux, Neovim, btop, VS Code,
// the browsers, and the shell's own lock screen, which another program draws.
//
// Each of them reads colours its own way, so this does not talk to any of
// them. It writes down the theme as a flat list of names and values
// (~/.local/state/kde-quickshell/theme/colors.json), each colour also as
// "r,g,b" and without the "#", and apply.sh fills the templates in `themed`
// with it, one per program, and tells the running programs to read theirs
// again. The way Omarchy does it.
Singleton {
    id: root

    readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/kde-quickshell/theme"

    function channels(colour: string): list<int> {
        return [1, 3, 5].map(at => parseInt(colour.slice(at, at + 2), 16));
    }

    // a colour `share` of the way from one to another
    function between(from: string, to: string, share: real): string {
        const a = channels(from), b = channels(to);
        return "#" + a.map((value, i) => Math.round(value + (b[i] - value) * share).toString(16).padStart(2, "0")).join("");
    }

    // how light a colour is to the eye, 0 to 1 (WCAG's relative luminance)
    function luminance(colour: string): real {
        const [r, g, b] = channels(colour).map(value => {
            const part = value / 255;
            return part <= 0.04045 ? part / 12.92 : Math.pow((part + 0.055) / 1.055, 2.4);
        });
        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    // how far apart two colours are for reading one on the other (WCAG's
    // contrast ratio: 1 is none, 4.5 is what body text wants)
    function contrast(one: string, other: string): real {
        const a = luminance(one), b = luminance(other);
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }

    // a colour with each part multiplied, as Qt's lighter() and darker() do
    // for all but the lightest colours
    function scaled(colour: string, by: real): string {
        return "#" + channels(colour).map(value => Math.min(255, Math.round(value * by)).toString(16).padStart(2, "0")).join("");
    }

    // KDE's colour for what is selected. A selected row in Dolphin and in
    // KDE's lists is filled with a share of it over the view (a third, two
    // thirds under the pointer), the text on it is the ordinary text, and
    // round it goes an outline in the colour itself, a little darker (or on
    // a dark view lighter). With the accent as it is, that asks too much
    // twice. The text is hard to read in every theme whose accent is not as
    // bright as Breeze's blue (measured: 2.2 to 3.6 where 4.5 is wanted).
    // And the outline, a line of one and a quarter pixels round a corner of
    // five, is drawn in steps at a fractional scale, which show the more the
    // darker the line is against the view. So the accent is taken towards
    // the view, in steps, until the text can be read and the outline stands
    // out from the view by no more than 1.7: pale, at the user's wish. On a
    // light theme it stops earlier, see below.
    function selectionFor(theme: var): string {
        const dark = isDark(theme.view);
        let selection = theme.accent;
        for (let share = 0; share <= 0.9; share += 0.05) {
            const candidate = between(theme.accent, theme.view, share);
            // Not so pale that it turns light: under the pointer Breeze
            // draws a selected row a tenth lighter than the colour, and on a
            // light theme that must still be darker than the window behind
            // it. (See also ChangeSelectionColor in themed/kde.colors.tpl.)
            if (!dark && share > 0) {
                const lifted = scaled(candidate, 1.1);
                if (luminance(lifted) >= luminance(theme.bg) || contrast(lifted, theme.bg) < 1.1)
                    break;
            }
            selection = candidate;
            // as Dolphin makes the outline: Qt's darker(110) or lighter(110)
            const outline = scaled(selection, dark ? 1.1 : 1 / 1.1);
            if (contrast(theme.fg, between(theme.view, selection, 0.65)) >= 4.5 && contrast(outline, theme.view) <= 1.7)
                break;
        }
        return selection;
    }

    // ---- the lock screen's clock -----------------------------------------

    // The clock stands on the background, not on anything of the theme's, so
    // the theme's text colour is right for it only by chance (dark figures on
    // a dark picture with a light theme). What is under it is measured: the
    // part of the picture the clock is on (a video's frame two seconds in),
    // as 16 by 8 grey values, by ffmpeg. `file` says which background they
    // are of.
    property var under: ({
            file: "",
            cells: []
        })

    readonly property string background: Themes.background
    onBackgroundChanged: measure.look()

    Process {
        id: measure

        property string picture

        function look() {
            if (running)
                return;
            picture = root.background;
            if (picture === "") {
                root.under = {
                    file: "",
                    cells: []
                };
                return;
            }
            // the picture as the wallpaper crops it to the screen, then the
            // middle half of its width from 24 % to 49 % of its height
            command = ["sh", "-c", `case "$1" in *.mp4 | *.webm | *.mkv | *.mov | *.gif) seek="-ss 2" ;; esac
ffmpeg -v error $seek -i "$1" -frames:v 1 -vf "scale=1600:900:force_original_aspect_ratio=increase,crop=1600:900,crop=800:225:400:216,scale=16:8:flags=area,format=gray" -f rawvideo - < /dev/null | od -An -v -tu1`, "sh", picture];
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.under = {
                    file: measure.picture,
                    // grey values to how light they are to the eye, 0 to 1
                    cells: text.trim().split(/\s+/).filter(value => value !== "").map(value => {
                        const part = Number(value) / 255;
                        return part <= 0.04045 ? part / 12.92 : Math.pow((part + 0.055) / 1.055, 2.4);
                    })
                };
            }
        }
        // another background was chosen while this ran
        onExited: {
            if (picture !== root.background)
                look();
        }
    }

    // The clock's colour and its shadow's: the lightest or the darkest of the
    // theme's tones (taken further, see below), whichever reads better on the worst tenth of what is
    // under it, and a shadow of the other kind. With nothing measured (no
    // background of the theme's: Plasma's own wallpaper) the light one,
    // which a dark shadow carries on most pictures.
    function clockFor(theme: var): var {
        const tones = [theme.fg, theme.bg, theme.view].map(colour => String(Qt.color(colour)).slice(0, 7)).sort((a, b) => luminance(a) - luminance(b));
        // A light theme's text is often a middle grey, and a dark theme's
        // not white: taken further, in their own hue, until they are dark
        // and light enough to stand on a picture.
        let dark = tones[0], light = tones[2];
        while (luminance(dark) > 0.04)
            dark = scaled(dark, 0.9);
        while (luminance(light) < 0.8)
            light = between(light, "#ffffff", 0.1);
        const cells = under.file === background ? under.cells : [];
        const worst = tone => {
            const own = luminance(tone);
            const ratios = cells.map(cell => (Math.max(own, cell) + 0.05) / (Math.min(own, cell) + 0.05)).sort((a, b) => a - b);
            return ratios[Math.floor(ratios.length / 10)];
        };
        const colour = cells.length > 0 && worst(dark) > worst(light) ? dark : light;
        return {
            colour: colour,
            shadow: colour === dark ? "#99ffffff" : "#b3000000"
        };
    }

    function isDark(colour: string): bool {
        const [r, g, b] = channels(colour);
        return 0.299 * r + 0.587 * g + 0.114 * b < 128;
    }

    readonly property var values: {
        // not what the theme switcher is only showing
        const theme = Theme.applied;
        const dark = isDark(theme.bg);
        const colours = {};
        for (const name of ["bg", "view", "surface", "surfaceHover", "surfaceActive", "fg", "fgDim", "accent", "accentFg", "warning", "error", "terminalBackground", "terminalForeground", "terminalCursor", "terminalSelection"])
            colours[name] = theme[name];
        theme.terminal.slice(0, 16).forEach((colour, i) => colours["terminal" + i] = colour);
        // what KDE's colour scheme has names for and the theme does not
        colours.positive = theme.terminal[2];
        colours.link = theme.terminal[4];
        colours.visited = theme.terminal[5];
        colours.viewAlternate = between(theme.view, theme.bg, 0.5);
        colours.buttonAlternate = between(theme.surface, theme.accent, 0.3);
        colours.selection = selectionFor(theme);
        // on it, where it is drawn whole (selected text): whichever reads better
        colours.selectionFg = contrast(theme.fg, colours.selection) >= contrast(theme.accentFg, colours.selection) ? theme.fg : theme.accentFg;
        colours.selectionAlternate = between(colours.selection, theme.bg, 0.4);
        colours.selectionInactive = between(colours.selectionFg, colours.selection, 0.4);
        // "complementary" is the dark set KDE uses on top of pictures: of a
        // light theme its text colour as background
        colours.complementaryBg = dark ? theme.view : theme.fg;
        colours.complementaryFg = dark ? theme.fg : theme.bg;
        colours.complementaryDim = dark ? theme.fgDim : between(theme.bg, theme.fg, 0.35);

        const values = {
            name: Themes.chosen,
            title: Themes.title(Themes.chosen),
            // as KDE knows the colour scheme
            scheme: "Quickshell" + Themes.title(Themes.chosen).replace(/[^A-Za-z0-9]/g, ""),
            mode: dark ? "dark" : "light",
            nvim: Themes.apps.nvim ?? "default",
            vscode: Themes.apps.vscode ?? "",
            btop: Themes.apps.btop ?? ""
        };
        for (const name in colours) {
            // "#rgb" and "#aarrggbb" are allowed in a theme; here it is "#rrggbb"
            const colour = String(Qt.color(colours[name])).slice(0, 7);
            values[name] = colour;
            values[name + "_rgb"] = channels(colour).join(",");
            values[name + "_strip"] = colour.slice(1);
        }
        const clock = clockFor(theme);
        values.clock = clock.colour;
        values.clockShadow = clock.shadow;
        // the dark edge libadwaita draws where one surface lies on another
        values.shade = dark ? "rgba(0, 0, 0, 0.36)" : "rgba(0, 0, 0, 0.12)";
        // for the browsers' policy: the colour of the frame, or none
        values.browserColour = Themes.browsers === "system" ? "off" : values.bg_strip;
        for (const name of ["frameBorder", "frameRounding", "panelRounding", "panelSmoothing", "shadowOpacity", "radius", "spacing", "padding", "fontSize", "fontSizeSmall", "iconSize", "moveDuration", "fadeDuration"])
            values[name] = String(Theme[name]);
        for (const name of ["moveCurve", "fadeCurve"])
            values[name] = Theme[name].join(", ");
        return values;
    }

    readonly property string text: JSON.stringify(values, null, 2) + "\n"
    // A change of theme is its name first and its colours a moment later:
    // written when both are in.
    onTextChanged: settle.restart()
    Component.onCompleted: settle.restart()

    Timer {
        id: settle

        interval: 250
        onTriggered: root.write()
    }

    // one run of the script at a time; a theme chosen meanwhile after it
    property bool again: false

    function write() {
        if (script.running) {
            again = true;
            return;
        }
        file.setText(text);
    }

    FileView {
        id: file

        path: root.dir + "/colors.json"
        // it is only written
        preload: false
        printErrors: false
        onSaved: {
            script.command = ["sh", Quickshell.shellPath("apply.sh"), path, Quickshell.shellPath("themed")];
            script.running = true;
        }
    }

    Process {
        id: script

        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    console.warn("ThemeExport:", text.trim());
            }
        }
        onExited: {
            if (root.again) {
                root.again = false;
                root.write();
            }
        }
    }
}
