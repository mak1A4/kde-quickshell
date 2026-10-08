#version 440

// The binary clock's dots (modules/clock/BinaryTime.qml) as one drawing:
// two columns of dots, the hour's and the minutes', each dot lit as far as
// its level says (0 off, 1 on, anything between while it changes). A
// column's lit dots are drawn as one liquid shape, by the smooth minimum the
// frame is drawn with: two that are lit one above the other join with a thin
// neck. They breathe, slowly and not in
// step, have a faint glow, and a dot coming on sends out one ring.
//
// Build: /usr/lib/qt6/bin/qsb --qt6 -o binary.frag.qsb binary.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;   // item size, logical px
    float margin;      // room around the dots, for the glow
    float dotSize;
    float gap;         // between the dots of a column
    float columnGap;   // between the two columns
    float time;        // seconds, wrapping at 2000 pi
    // A column's dots from the lowest (worth 1): `Low` has 1, 2, 4 and 8 in
    // x to w, `High` 16 in x and, for the minutes, 32 in y.
    vec4 hourLow;
    vec4 hourHigh;
    vec4 minuteLow;
    vec4 minuteHigh;
    vec4 hourColor;
    vec4 minuteColor;
    vec4 offColor;
};

// as in frame.frag: an arc of radius k where two shapes are closer than k
float smin(float a, float b, float k) {
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

float levelOf(int column, int row) {
    vec4 l = column == 0 ? (row < 4 ? hourLow : hourHigh) : (row < 4 ? minuteLow : minuteHigh);
    int at = row < 4 ? row : row - 4;
    return at == 0 ? l.x : (at == 1 ? l.y : (at == 2 ? l.z : l.w));
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;
    float pitch = dotSize + gap;
    float lit1 = dotSize * 0.5;
    float off1 = dotSize * 0.33;
    float bottom = resolution.y - margin - lit1;
    // how readily neighbours join; it swells and ebbs a little
    float k = pitch * 0.64 + 0.5 * sin(time * 0.9);

    vec4 result = vec4(0.0);
    // the hour's column, then the minutes': each a shape of its own
    for (int c = 0; c < 2; c++) {
        float d = 1000.0;
        float off = 0.0;
        float ring = 0.0;
        float x = margin + lit1 + float(c) * (dotSize + columnGap);
        // a column is as high as its number can need: 23 is five dots, 59 six
        int rows = c == 0 ? 5 : 6;
        for (int r = 0; r < 6; r++) {
            if (r >= rows)
                continue;
            vec2 centre = vec2(x, bottom - float(r) * pitch);
            float level = levelOf(c, r);
            float lit = clamp(level, 0.0, 1.0);
            float dist = length(p - centre);

            off = max(off, (1.0 - smoothstep(off1 - 0.6, off1 + 0.6, dist)) * (1.0 - lit));

            float phase = float(c) * 1.3 + float(r) * 0.9;
            // one going out shrinks away from its neighbours altogether
            float radius = lit1 * level * (1.0 + 0.07 * sin(time * 1.6 + phase)) - (1.0 - lit) * 5.0;
            d = smin(d, dist - radius, k);

            ring += (1.0 - smoothstep(0.0, 1.2, abs(dist - (lit1 + dotSize * 1.3 * lit)))) * lit * (1.0 - lit) * 4.0;
        }
        vec4 colour = c == 0 ? hourColor : minuteColor;
        float body = 1.0 - smoothstep(-0.6, 0.6, d);
        float glow = exp(-max(d, 0.0) * 0.6) * (0.22 + 0.1 * sin(time * 1.1 - p.y * 0.3 + p.x * 0.2));
        float shimmer = 1.0 + 0.1 * sin(time * 2.0 + p.y * 0.8 - p.x * 0.5);

        vec4 layer = offColor * off * (1.0 - body);
        layer += vec4(colour.rgb * shimmer, colour.a) * body;
        layer += colour * (glow + ring * 0.5) * (1.0 - body);
        result = layer + result * (1.0 - layer.a);
    }

    fragColor = result * qt_Opacity;
}
