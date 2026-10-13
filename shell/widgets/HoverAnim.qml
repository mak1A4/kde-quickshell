import QtQuick
import qs

// The colour of what answers the pointer being on it: a background that
// lights up, an icon that brightens. Quick, and the same everywhere
// (`Theme.followDuration`): an answer that comes at the fade's 200 ms is
// still arriving when the pointer has gone on. Where the same colour also
// shows a state (pressed in, armed, the active window), that changes as
// quickly: one colour has one animation. For a size or an opacity that
// answers the pointer there is `Anim.Hover`.
ColorAnimation {
    duration: Theme.followDuration
    easing.type: Easing.OutCubic
}
