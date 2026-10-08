pragma Singleton

import Quickshell
import QtQuick

// Which popout is open, if any. A bar module calls toggle() with its own
// button and a Component for the content; the Frame owning that button shows it.
//
// Also which item is hovered for a hint. Such an item has `hintTitle` (string)
// and `hintLines` (list of strings) and reports its hover state via hover().
//
// And which context menu is open (widgets/MenuPopup.qml, ActionMenu.qml).
// These are windows of their own, and there is one at a time: a menu shows
// only while it is `menu`, and another that opens takes its place.
Singleton {
    id: root

    property string current: ""
    property Item anchorItem: null
    property Component content: null
    property Item hintItem: null
    property QtObject menu: null
    readonly property bool menuOpen: menu?.visible ?? false

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

    // A menu calls this when its `open` changes. The one that was open is
    // closed before the new one is `menu`, so before the new one is mapped:
    // two such popups side by side are not allowed (the second would be made
    // a child of the first).
    function menuToggled(item: QtObject) {
        if (!item.open) {
            if (menu === item)
                menu = null;
            return;
        }
        if (menu && menu !== item)
            menu.open = false;
        menu = item;
    }

    function closeMenu() {
        if (menu)
            menu.open = false;
    }
}
