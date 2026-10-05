#version 440

// The notification light: a dot that breathes, with rings spreading out from
// it like ripples and its colour drifting between two tints. `energy` 0 is
// the light at rest: only the dot, dimmed.
//
// Build: /usr/lib/qt6/bin/qsb --qt6 -o orb.frag.qsb orb.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float size;      // the item's side, logical px
    float time;      // seconds
    float energy;    // 0 at rest, 1 calling
    vec4 colorA;
    vec4 colorB;
};

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    float d = length(p);
    float angle = atan(p.y, p.x);

    // the tint turns slowly around the dot
    vec3 tint = mix(colorA.rgb, colorB.rgb, 0.5 + 0.5 * sin(angle * 2.0 + time * 1.1));
    float breath = 0.5 + 0.5 * sin(time * 2.2);

    // the dot, a little larger on the in-breath
    float r = 4.2 + 0.7 * breath * energy;
    float core = 1.0 - smoothstep(r - 0.8, r + 0.8, d);

    // a soft halo around it
    float glow = exp(-d * d / (2.0 * 81.0)) * (0.3 + 0.3 * breath) * energy;

    // two ripples, half a cycle apart, not quite round, fading as they spread
    float rings = 0.0;
    for (int i = 0; i < 2; i++) {
        float phase = fract(time / 2.6 + float(i) * 0.5);
        float radius = mix(5.0, size * 0.46, phase);
        radius *= 1.0 + 0.05 * sin(angle * 3.0 + time * 1.7 + float(i) * 2.0);
        float width = mix(1.0, 2.4, phase);
        rings += (1.0 - smoothstep(0.0, width, abs(d - radius))) * pow(1.0 - phase, 2.0);
    }

    float alpha = clamp(core * mix(0.5, 1.0, energy) + glow * 0.7 + rings * 0.5 * energy, 0.0, 1.0);
    vec3 colour = mix(tint, vec3(1.0), core * 0.4 * energy);
    fragColor = vec4(colour * alpha, alpha) * qt_Opacity;
}
