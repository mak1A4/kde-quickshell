import Quickshell
import QtQuick

// For the glass frame's blur (Frame.qml): the fillet where a panel meets
// the border, as strips one pixel thick laid along the border's edge, each
// as long as the fillet is wide there (BlurBlob.qml works them out). A
// region has no curves but a circle's, and a fillet is an arc of a circle
// only out of a deep panel: out of a shallow one (the notch) it is another
// curve, and a circle in its place left glass without blur beside it, in
// steps. There are as many strips as the widest fillet has pixels.
Region {
    id: fillet

    property var strips: []

    BlurStrip {
        at: fillet.strips[0] ?? null
    }

    BlurStrip {
        at: fillet.strips[1] ?? null
    }

    BlurStrip {
        at: fillet.strips[2] ?? null
    }

    BlurStrip {
        at: fillet.strips[3] ?? null
    }

    BlurStrip {
        at: fillet.strips[4] ?? null
    }

    BlurStrip {
        at: fillet.strips[5] ?? null
    }

    BlurStrip {
        at: fillet.strips[6] ?? null
    }

    BlurStrip {
        at: fillet.strips[7] ?? null
    }

    BlurStrip {
        at: fillet.strips[8] ?? null
    }

    BlurStrip {
        at: fillet.strips[9] ?? null
    }

    BlurStrip {
        at: fillet.strips[10] ?? null
    }

    BlurStrip {
        at: fillet.strips[11] ?? null
    }

    BlurStrip {
        at: fillet.strips[12] ?? null
    }

    BlurStrip {
        at: fillet.strips[13] ?? null
    }

    BlurStrip {
        at: fillet.strips[14] ?? null
    }

    BlurStrip {
        at: fillet.strips[15] ?? null
    }

    BlurStrip {
        at: fillet.strips[16] ?? null
    }

    BlurStrip {
        at: fillet.strips[17] ?? null
    }

    BlurStrip {
        at: fillet.strips[18] ?? null
    }

    BlurStrip {
        at: fillet.strips[19] ?? null
    }

    BlurStrip {
        at: fillet.strips[20] ?? null
    }

    BlurStrip {
        at: fillet.strips[21] ?? null
    }
}
