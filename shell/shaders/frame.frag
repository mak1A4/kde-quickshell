#version 440

// Frame border and the panels growing out of it, drawn as one merged
// signed-distance field. The circular smooth-min makes each panel flow into
// the border with a fillet that forms as the panel slides out, which is the
// technique Caelestia's blob renderer uses (much simplified here).
//
// Build: /usr/lib/qt6/bin/qsb --qt6 -o frame.frag.qsb frame.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;     // item size, logical px
    vec4 inner;          // the hole: centre x, centre y, half width, half height
    float innerRadius;
    float panelRadius;
    float smoothing;     // fillet radius where a panel meets the border
    vec4 color;
    // panels as centre x, centre y, half width, half height; unused when half width <= 0
    vec4 panel0;
    vec4 panel1;
    vec4 panel2;
    // A tooltip bubble: a separate shape in its own colour, not merged with
    // the rest, but drawn here so it shares the shadow.
    vec4 bubble;
    float bubbleRadius;
    vec4 bubbleColor;
    float bubbleOpacity;
};

float sdRoundedBox(vec2 p, vec2 center, vec2 halfSize, float radius) {
    vec2 d = abs(p - center) - halfSize + vec2(radius);
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

// Circular smooth min: the blend is a true arc of radius k, tangent to both
// surfaces, and differs from min(a, b) only where both are closer than k.
float smin(float a, float b, float k) {
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

float merge(float d, vec2 p, vec4 panel, float maxRadius, float k) {
    if (panel.z <= 0.0 || panel.w <= 0.0)
        return d;
    float radius = min(maxRadius, min(panel.z, panel.w));
    return smin(d, sdRoundedBox(p, panel.xy, panel.zw, radius), k);
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;

    // the border is everything outside the hole
    float d = -sdRoundedBox(p, inner.xy, inner.zw, innerRadius);
    d = merge(d, p, panel0, panelRadius, smoothing);
    d = merge(d, p, panel1, panelRadius, smoothing);
    d = merge(d, p, panel2, panelRadius, smoothing);

    float fw = fwidth(d);
    vec4 result = vec4(color.rgb, 1.0) * color.a * (1.0 - smoothstep(-fw, fw, d));

    if (bubble.z > 0.0 && bubble.w > 0.0 && bubbleOpacity > 0.0) {
        float b = sdRoundedBox(p, bubble.xy, bubble.zw, min(bubbleRadius, min(bubble.z, bubble.w)));
        float bw = fwidth(b);
        float cover = (1.0 - smoothstep(-bw, bw, b)) * bubbleColor.a * bubbleOpacity;
        result = result * (1.0 - cover) + vec4(bubbleColor.rgb, 1.0) * cover;
    }

    fragColor = result * qt_Opacity;
}
