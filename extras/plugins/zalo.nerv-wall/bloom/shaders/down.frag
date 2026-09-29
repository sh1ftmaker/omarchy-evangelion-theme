#version 440
// NervBloom downsample: dual-filter (Bjorge 2015) 5-tap, one pass per octave. The pass itself is
// the blur, replacing SE's downsample + 2x separable Gaussian per octave.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;      // 1 / input size
};
layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 uv = qt_TexCoord0;
    fragColor = (texture(src, uv) * 4.0
               + texture(src, uv - texel) + texture(src, uv + texel)
               + texture(src, uv + vec2(texel.x, -texel.y)) + texture(src, uv - vec2(texel.x, -texel.y))) * 0.125;
}
