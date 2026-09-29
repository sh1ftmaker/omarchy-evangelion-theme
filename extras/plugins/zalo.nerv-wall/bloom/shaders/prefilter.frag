#version 440
// NervBloom pass 1: pseudo-HDR prefilter fused with the first dual-filter downsample.
// Input is the LDR, premultiplied capture of the wall. Each bilinear tap (already a 2x2 box)
// is un-premultiplied, its "heat" v (0.3 Rec.709 luma + 0.7 max channel, so red/orange count
// as hot while graphite stays cold) is inverse-tonemapped into an HDR gain
// 1 + hdrBoost * v^hdrPower and re-multiplied by coverage. No threshold (SE Natural Bloom).
// Output: rgb = HDR energy (premultiplied), a = its luma (feeds the lens-dirt chain).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;      // 1 / input size
    float hdrBoost;
    float hdrPower;
};
layout(binding = 1) uniform sampler2D src;

vec3 heat(vec2 uv) {
    vec4 s = texture(src, uv);
    vec3 c = s.rgb / max(s.a, 1e-4);
    float v = clamp(0.3 * dot(c, vec3(0.2126, 0.7152, 0.0722)) + 0.7 * max(c.r, max(c.g, c.b)), 0.0, 1.0);
    return s.rgb * (1.0 + hdrBoost * pow(v, hdrPower));
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 c = heat(uv) * 4.0
           + heat(uv - texel) + heat(uv + texel)
           + heat(uv + vec2(texel.x, -texel.y)) + heat(uv - vec2(texel.x, -texel.y));
    c *= 0.125;
    fragColor = vec4(c, dot(c, vec3(0.2126, 0.7152, 0.0722)));
}
