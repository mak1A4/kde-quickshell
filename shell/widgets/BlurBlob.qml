import Quickshell
import QtQuick
import qs

// For the glass frame's blur (Frame.qml): one panel's background as the
// shader draws it (`blob`: centre and half size). The rounded rectangle, and
// a fillet wherever one of its sides crosses an edge of the hole (`hole`:
// left, top, right, bottom).
Region {
    id: blobBlur

    property vector4d blob
    property vector4d hole
    readonly property bool there: blob.z > 0 && blob.w > 0
    readonly property real left: blob.x - blob.z
    readonly property real right: blob.x + blob.z
    readonly property real top: blob.y - blob.w
    readonly property real bottom: blob.y + blob.w
    // the corners' radius, as the shader has it
    readonly property real rounding: Math.min(Theme.panelRounding, blob.z, blob.w)
    readonly property var fillets: {
        const found = [];
        if (!there)
            return found;
        const reach = Theme.panelSmoothing;
        const between = (value, low, high) => value > low && value < high;
        // One fillet, as strips. (px, py) is where a side of the blob
        // crosses an edge of the hole, (ox, oy) points along that edge away
        // from the blob, (ix, iy) into the hole, and `depth` is how far the
        // blob comes out of the edge.
        //
        // The shader joins the two with a smooth minimum of their
        // distances, a from the edge and b from the blob: the shape ends
        // where (reach - a)² + (reach - b)² = reach². So at a pixels from
        // the edge it ends b = reach - √(reach² - (reach - a)²) from the
        // blob; and that far from the blob is that far from its straight
        // side, or once past the straight part, from its rounded corner.
        // Each strip stops a pixel short of that, under the glass's rim.
        const add = (px, py, ox, oy, ix, iy, depth) => {
            const straight = depth - rounding;
            const strips = [];
            for (let a = 0; a < Math.min(reach, depth); a++) {
                // where the strip is narrowest: at its far side
                const far = a + 1;
                const gap = reach - Math.sqrt(reach * reach - (reach - far) * (reach - far));
                const beside = far <= straight;
                const across = (gap + rounding) * (gap + rounding) - (far - straight) * (far - straight);
                if (!beside && across <= 0)
                    break;
                const end = (beside ? gap : Math.sqrt(across) - rounding) - 1;
                const from = beside ? 0 : -rounding;
                if (end <= from)
                    continue;
                const ax = px + ox * from + ix * a, ay = py + oy * from + iy * a;
                const bx = px + ox * end + ix * far, by = py + oy * end + iy * far;
                const x = Math.round(Math.min(ax, bx)), y = Math.round(Math.min(ay, by));
                strips.push({
                    x: x,
                    y: y,
                    width: Math.round(Math.max(ax, bx)) - x,
                    height: Math.round(Math.max(ay, by)) - y
                });
            }
            found.push(strips);
        };
        // out of the hole's top edge, its bottom, its left, its right
        if (between(hole.y, top, bottom)) {
            if (between(left, hole.x, hole.z))
                add(left, hole.y, -1, 0, 0, 1, bottom - hole.y);
            if (between(right, hole.x, hole.z))
                add(right, hole.y, 1, 0, 0, 1, bottom - hole.y);
        }
        if (between(hole.w, top, bottom)) {
            if (between(left, hole.x, hole.z))
                add(left, hole.w, -1, 0, 0, -1, hole.w - top);
            if (between(right, hole.x, hole.z))
                add(right, hole.w, 1, 0, 0, -1, hole.w - top);
        }
        if (between(hole.x, left, right)) {
            if (between(top, hole.y, hole.w))
                add(hole.x, top, 0, -1, 1, 0, right - hole.x);
            if (between(bottom, hole.y, hole.w))
                add(hole.x, bottom, 0, 1, 1, 0, right - hole.x);
        }
        if (between(hole.z, left, right)) {
            if (between(top, hole.y, hole.w))
                add(hole.z, top, 0, -1, -1, 0, hole.z - left);
            if (between(bottom, hole.y, hole.w))
                add(hole.z, bottom, 0, 1, -1, 0, hole.z - left);
        }
        return found;
    }

    x: there ? Math.round(left) : 0
    y: there ? Math.round(top) : 0
    width: there ? Math.round(right) - Math.round(left) : 0
    height: there ? Math.round(bottom) - Math.round(top) : 0
    // a pixel more than the shape's: see `blur` in Frame.qml
    radius: there ? Math.round(rounding) + 1 : 0

    BlurFillet {
        strips: blobBlur.fillets[0] ?? []
    }

    BlurFillet {
        strips: blobBlur.fillets[1] ?? []
    }

    BlurFillet {
        strips: blobBlur.fillets[2] ?? []
    }

    BlurFillet {
        strips: blobBlur.fillets[3] ?? []
    }
}
