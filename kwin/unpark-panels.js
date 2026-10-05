// Moves plasmashell's panels back from where kwin/park-panels.js put them.
// Run once, after that script has been unloaded.

var OFFSET = 10000;

workspace.windowList().forEach(function (window) {
    if (!window.dock || window.resourceClass != "plasmashell")
        return;
    var at = window.frameGeometry;
    if (at.y < OFFSET / 2)
        return;
    window.frameGeometry = {
        x: at.x,
        y: at.y - OFFSET,
        width: at.width,
        height: at.height
    };
});
