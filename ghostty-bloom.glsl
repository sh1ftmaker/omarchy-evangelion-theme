// NERV phosphor bloom for Ghostty: a lighter, single-pass cousin of the desktop wall's
// SE Natural Bloom port (zalo.nerv-wall/bloom). Bright glyphs (orange, amber, bone, green)
// get a tight warm halo plus a faint wide haze; dim text and the black ground barely glow.
// Runs only when the terminal redraws (no custom-shader-animation), so idle cost is zero.

const float TIGHT_RADIUS = 2.5;    // px, the halo hugging each glyph
const float WIDE_RADIUS  = 12.0;   // px, the soft CRT haze
const float TIGHT_GAIN   = 1.30;
const float WIDE_GAIN    = 0.55;
const float HDR_POWER    = 1.6;    // pseudo-HDR: how much brighter colours dominate the glow
const vec3  HALATION     = vec3(1.0, 0.35, 0.12); // warm tint on the wide haze, like the video's carmine halation
const int   TAPS         = 20;     // per ring; golden-angle spiral

vec3 heat(vec3 c) {
    // weight by the brightest channel so saturated orange glows as much as white text,
    // while dim graphite (#4a3218) and the ink background contribute almost nothing
    float v = max(max(c.r, c.g), c.b);
    return c * pow(v, HDR_POWER);
}

vec3 ring(vec2 uv, vec2 px, float radius) {
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    float sigma = radius * 0.5;
    for (int i = 0; i < TAPS; i++) {
        float fi = float(i) + 0.5;
        float r = sqrt(fi / float(TAPS)) * radius;
        float a = fi * 2.39996323;
        vec2 o = vec2(cos(a), sin(a)) * r * px;
        float w = exp(-(r * r) / (2.0 * sigma * sigma));
        acc += heat(texture(iChannel0, uv + o).rgb) * w;
        wsum += w;
    }
    return acc / wsum;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    vec2 px = 1.0 / iResolution.xy;
    vec4 src = texture(iChannel0, uv);

    vec3 glow = ring(uv, px, TIGHT_RADIUS) * TIGHT_GAIN
              + ring(uv, px, WIDE_RADIUS) * WIDE_GAIN * HALATION;

    // screen blend: adds light without clipping bright glyphs to flat white
    vec3 col = 1.0 - (1.0 - src.rgb) * (1.0 - glow);
    fragColor = vec4(col, src.a);
}
