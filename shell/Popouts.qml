pragma Singleton

import Quickshell
import QtQuick

// Which popout is open, if any. A bar module calls toggle() with its own
// button and a Component for the content; the Frame owning that button shows it.
//
// Also which item is hovered for a hint. Such an item has `hintTitle` (string)
// and `hintLines` (list of strings) and reports its hover state via hover().
Singleton {
    id: root

    property string current: ""
    property Item anchorItem: null
    property Component content: null
    property Item hintItem: null

    function hover(item: Item, hovered: bool) {
        if (hovered)
            hintItem = item;
        else if (hintItem === item)
            hintItem = null;
    }

    // Emitted just before a popout closes. `byOwner` is true when the button
    // that opened it closed it, i.e. the pointer is on that button.
    signal closing(Item anchorItem, bool byOwner)

    function toggle(name: string, anchorItem: Item, content: Component) {
        if (current === name) {
            closing(root.anchorItem, true);
            current = "";
            return;
        }
        Launcher.hide();
        CommandPalette.hide();
        Notifications.listOpen = false;
        root.anchorItem = anchorItem;
        root.content = content;
        current = name;
    }

    function close() {
        if (current !== "")
            closing(root.anchorItem, false);
        current = "";
    }
}
