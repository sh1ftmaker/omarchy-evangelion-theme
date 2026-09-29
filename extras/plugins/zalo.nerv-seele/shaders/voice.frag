#version 440
// SEELE voice print: a live oscilloscope trace synthesised per pixel.
// env (64x1 texture, red = sqrt(cpu) level, newest sample at texel 63) is the slowly
// sampled envelope; the carrier (three travelling partials under a syllable envelope)
// is generated from `time`, so the trace moves at display rate with no CPU-side redraw.
// `prog` (0..1) slides the envelope one slot left between samples.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float prog;
    float w;
    float h;
};
layout(binding = 1) uniform sampler2D env;

float envAt(float x) {
    float f = x / w * 63.0 - (1.0 - prog);
    float e = texture(env, vec2((clamp(f, 0.0, 63.0) + 0.5) / 64.0, 0.5)).r;
    return max(0.10, e);
}

float traceY(float x) {
    float T = time;
    // syllables: a slow travelling amplitude envelope; formants: three partials at
    // different phase velocities so the waveform keeps morphing like speech
    float syl = 0.35 + 0.65 * pow(abs(sin(x * 0.041 + T * 1.9 + 1.4 * sin(T * 0.63))), 0.8);
    float car = 0.64 * sin(x * 0.33 + T * 9.0)
              + 0.30 * sin(x * 0.71 + T * 14.5 + 1.3 + 0.8 * sin(T * 0.9))
              + 0.12 * sin(x * 1.45 + T * 23.0 + 0.6 * sin(T * 2.3));
    return h * 0.5 - (h * 0.5 - 2.0) * envAt(x) * syl * car;
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(w, h);          // design px
    vec2 px = max(fwidth(p), vec2(1e-4));        // design px per device pixel
    float y0 = traceY(p.x);
    float slope = (traceY(p.x + px.x) - traceY(p.x - px.x)) / (2.0 * px.x);
    float d = abs(p.y - y0) / sqrt(1.0 + slope * slope) / px.y;   // device px
    float core = 1.0 - smoothstep(0.6, 1.6, d);
    float halo = (1.0 - smoothstep(1.5, 5.0, d)) * 0.22;
    float a = max(core, halo);
    // premultiplied #FF1A1A, core tinted toward amber-white at the hottest point
    vec3 c = mix(vec3(1.0, 0.102, 0.102), vec3(1.0, 0.55, 0.40), core * 0.25);
    fragColor = vec4(c * a, a) * qt_Opacity;
}
