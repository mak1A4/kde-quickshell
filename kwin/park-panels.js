// A KWin script, loaded by the shell while it runs (shell/panels.sh).
//
// It moves plasmashell's panels far off the screen and keeps them there, so
// that Plasma's panel does not come up over the shell: an auto-hidden panel
// still "shows" when the pointer pushes against its edge, but where nobody
// sees it and it takes no input. Nothing in Plasma is changed: the panels,
// their widgets and their settings are as they were, only somewhere else.
// kwin/unpark-panels.js moves them back.
//
// Why here and not in Plasma: a panel has no "hidden" mode (always visible,
// auto-hide, dodge windows, windows go below), and its window cannot be
// reached from a widget that is not shown in it.

var OFFSET = 10000;

function isPanel(window) {
    return window.dock && window.resourceClass == "plasmashell";
}

function park(window) {
    var at = window.frameGeometry;
    // already out there
    if (at.y >= OFFSET / 2)
        return;
    window.frameGeometry = {
        x: at.x,
        y: at.y + OFFSET,
        width: at.width,
        height: at.height
    };
}

// KWin lays a panel out again whenever Plasma changes something about it
function watch(window) {
    if (!isPanel(window))
        return;
    park(window);
    window.frameGeometryChanged.connect(function () {
        park(window);
    });
}

workspace.windowList().forEach(watch);
workspace.windowAdded.connect(watch);
