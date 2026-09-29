#version 440
// Radar phosphor gate for the contact echoes. `lit` holds every blip drawn at full beam
// brightness, `flash` their beam-strike halos. Each pixel's brightness is computed from the
// angle between its bearing and the beam, so the fade is continuous and per-frame work is
// one uniform (the beam angle) instead of per-blip bindings.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float sweep;      // beam bearing, radians, clockwise from north
    float decay;      // afterglow decay per revolution
    float flashDecay; // halo decay per revolution
};
layout(binding = 1) uniform sampler2D lit;
layout(binding = 2) uniform sampler2D flash;

void main() {
    vec2 d = qt_TexCoord0 - vec2(0.5);
    float a = atan(d.x, -d.y);
    float f = fract((sweep - a) * 0.15915494309);
    vec4 c = texture(lit, qt_TexCoord0) * exp(-f * decay);
    float t = clamp(f * flashDecay, 0.0, 1.0);
    c += texture(flash, qt_TexCoord0) * (1.0 - t) * (1.0 - t);
    fragColor = c * qt_Opacity;
}
