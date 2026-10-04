import QtQuick
import qs

// Opacity animation for content that takes turns with other content in one
// panel: it fades out at once, but waits Theme.swapDelay before fading in, so
// the outgoing content is gone before the incoming one appears.
// Use as `Behavior on opacity { SwapFade { incoming: <true when fading in> } }`.
SequentialAnimation {
    id: root

    property bool incoming: false

    PauseAnimation {
        duration: root.incoming ? Theme.swapDelay : 0
    }

    Anim {
        kind: Anim.Fade
    }
}
