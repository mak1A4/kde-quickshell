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
    vec4 panel3;
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

float merge(float d, vec2 p, vec4 panel) {
    if (panel.z <= 0.0 || panel.w <= 0.0)
        return d;
    float radius = min(panelRadius, min(panel.z, panel.w));
    return smin(d, sdRoundedBox(p, panel.xy, panel.zw, radius), smoothing);
}

void main() {
    vec2 p = qt_TexCoord0 * resolution;

    // the border is everything outside the hole
    float d = -sdRoundedBox(p, inner.xy, inner.zw, innerRadius);
    d = merge(d, p, panel0);
    d = merge(d, p, panel1);
    d = merge(d, p, panel2);
    d = merge(d, p, panel3);

    float fw = fwidth(d);
    float alpha = 1.0 - smoothstep(-fw, fw, d);
    fragColor = vec4(color.rgb, 1.0) * color.a * alpha * qt_Opacity;
}
