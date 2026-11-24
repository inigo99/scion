// vertex + fragment shaders compiled at run time. A 2x2 texture (red, green, blue, white) on a quad that
// fills the target, tinted per draw; vertices come through a vertex descriptor ([[stage_in]]).
#include <metal_stdlib>
#include <simd/simd.h>
using namespace metal;

struct VIn { float2 pos [[attribute(0)]]; float2 uv [[attribute(1)]]; };
struct VOut { float4 position [[position]]; float2 uv; float3 tint [[flat]]; };
struct FOut { float4 color [[color(0)]]; };
struct Uniforms { float2 scale; float4 tint; };

vertex VOut vmain(VIn in [[stage_in]], constant Uniforms &u [[buffer(1)]], uint vid [[vertex_id]]) {
    VOut o;
    o.position = float4(in.pos * u.scale, 0.0, 1.0);
    o.uv = in.uv;
    o.tint = u.tint.rgb;
    return o;
}

fragment FOut fmain(VOut in [[stage_in]], texture2d<half> tex [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    FOut o;
    o.color = float4(tex.sample(s, in.uv)) * float4(in.tint, 1.0);
    return o;
}
