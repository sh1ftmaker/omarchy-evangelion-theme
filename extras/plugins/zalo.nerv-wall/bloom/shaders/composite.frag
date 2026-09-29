#version 440
// NervBloom final (composite mode): captured wall + glow in one full-res pass. Same math as
// glow.frag, with the "over" blend done here instead of by Qt: out = glow + (1 - a) * src.
// (glow.frag header below)
// NervBloom final: full-res glow layer drawn OVER the (untouched) source.
// bloom = tent-filtered accumulated octaves; SE's composite lerp(src, bloom, k) is expressed as a
// premultiplied layer: rgb = shoulder(k*bloom + lensDirt*kL*lensBloom), alpha = max channel, so
// Qt/compositor "over" blending gives src*(1-a) + glow (energy-conserving screen blend).
// Where there is no energy rgb = a = 0: the wallpaper and panels are untouched; in transparent
// gutters alpha grows with bloom energy so the glow reads over the wallpaper.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;      // 1 / bloom size
    float k;         // exp(intensity) - 1
    float kL;        // exp(lensDirtIntensity) - 1
};
layout(binding = 1) uniform sampler2D bloom;
layout(binding = 2) uniform sampler2D lens;
layout(binding = 3) uniform sampler2D src;

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 o = texel * 0.5;
    vec4 b = (texture(bloom, uv + vec2(-o.x, -o.y)) + texture(bloom, uv + vec2(o.x, -o.y))
            + texture(bloom, uv + vec2(-o.x, o.y)) + texture(bloom, uv + vec2(o.x, o.y))) * 0.25;
    float bl = max(dot(b.rgb, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
    vec3 lensBloom = b.rgb * (b.a / bl);               // lens-weighted energy, bloom's hue
    vec3 g = b.rgb * k + lensBloom * clamp(texture(lens, uv).rgb * kL, 0.0, 1.0);
    g = 1.0 - exp(-g);                                  // soft shoulder: hot cores bleach, never clip
    float a = max(g.r, max(g.g, g.b));
    fragColor = (vec4(g, a) + (1.0 - a) * texture(src, uv)) * qt_Opacity;
}
