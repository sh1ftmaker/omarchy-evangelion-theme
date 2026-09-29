#version 440
// NervBloom upsample-accumulate: U_k = tent(U_k+1) + w_k * D_k.
// rgb accumulates the bloom octaves with SE's pow(i+1, scatter) weights, alpha accumulates the
// octave lumas with the lens-dirt weights (SE's second weighting, luminance-only), and wide
// octaves also add a carmine film halation (evangelion post.ts) - all in the same pass.
// sScale lets the first pass weight the raw coarsest octave it reads as `coarse`.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;      // 1 / size of `coarse`
    vec4 sScale;     // (bloom w, lens w, halation w, 0) applied to `coarse` (1,1,0 after the first pass)
    vec4 dScale;     // (bloom w, lens w, halation w, 0) applied to `cur`
};
layout(binding = 1) uniform sampler2D coarse;
layout(binding = 2) uniform sampler2D cur;

const vec3 CARMINE = vec3(1.0, 0.04, 0.12);

vec4 weigh(vec4 s, vec4 w) {
    return vec4(s.rgb * w.x + CARMINE * (s.a * w.z), s.a * w.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 o = texel * 0.75;
    vec4 s = (texture(coarse, uv + vec2(-o.x, -o.y)) + texture(coarse, uv + vec2(o.x, -o.y))
            + texture(coarse, uv + vec2(-o.x, o.y)) + texture(coarse, uv + vec2(o.x, o.y))) * 0.25;
    fragColor = weigh(s, sScale) + weigh(texture(cur, uv), dScale);
}
