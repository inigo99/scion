// MSL compiled at run time (newLibraryWithSource:). Checked by tests/metal/msl.m.
#include <metal_stdlib>
using namespace metal;

struct Item { float3 p; half h; packed_float3 q; uint tag; };   // 48 bytes: p@0 h@16 q@20 tag@32
struct Params { float scale; uint n; float4x4 m; };              // m@16
constant float kTable[4] = {1.0, 2.0, 4.0, 8.0};
constant bool useBias [[function_constant(0)]];
constant float biasValue [[function_constant(1)]];

float helper(float x, thread float &acc) { acc += x; return x * 2; }

kernel void basics(device float *out [[buffer(0)]], constant Params &p [[buffer(1)]], device const Item *items [[buffer(2)]],
                   uint id [[thread_position_in_grid]]) {
    if (id != 0) return;
    float4 v = float4(1.0, 2.0, 3.0, 4.0);
    float3 c = float3(v.xy, 5);
    out[0] = v.x + v.w;
    out[1] = dot(v, float4(1));
    out[2] = length(float2(3, 4));
    float4 mv = p.m * v;
    out[3] = mv.x; out[4] = mv.y; out[5] = mv.w;
    out[6] = clamp(7.5, 0.0, 5.0);
    out[7] = mix(0.0, 10.0, 0.25);
    out[8] = kTable[id + 3];
    float acc = 1;
    out[9] = helper(3, acc) + acc;
    Item it = items[1];
    out[10] = it.p.y; out[11] = float(it.h); out[12] = it.q[2]; out[13] = float(it.tag);
    int4 iv = int4(v) * 2;
    out[14] = float(iv.z);
    half4 hv = half4(v) * 0.5h;
    out[15] = float(hv.w);
    out[16] = select(1.0, 2.0, v.x < v.y);
    out[17] = any(v > 3.5) ? 1.0 : 0.0;
    out[18] = all(v > 0.5) ? 1.0 : 0.0;
    float3x3 m3 = float3x3(float3(1, 0, 0), float3(0, 2, 0), float3(0, 0, 3));
    out[19] = (m3 * c).z;
    out[20] = determinant(m3);
    out[21] = as_type<float>(0x3f800000u);
    out[22] = fract(2.75) + floor(-1.5);
    out[23] = sqrt(16.0) + rsqrt(4.0);
    out[24] = pow(2.0, 10.0);
    out[25] = float(max(3, 7) + min(2u, 9u));
    out[26] = abs(-2.5);
    float2 sw = v.wz; sw.y = 9; out[27] = sw.x + sw.y;
    out[28] = transpose(p.m)[0][1];
    out[29] = sin(0.0) + cos(0.0) + exp2(3.0) + log2(8.0);
    out[30] = useBias ? biasValue : -1.0;
    float s = 0;
    for (int i = 0; i < 10; i++) { if (i == 7) break; if (i & 1) continue; s += float(i); }
    out[31] = s;                                   // 0+2+4+6
    switch (int(v.y)) { case 1: out[32] = 10; break; case 2: out[32] = 20; break; default: out[32] = 30; }
    out[33] = float(popcount(0xF0u) + clz(1u));    // 4 + 31
    out[34] = smoothstep(0.0, 1.0, 0.5) + step(0.5, 0.7);
    out[35] = normalize(float3(0, 3, 4)).z;
    out[36] = cross(float3(1, 0, 0), float3(0, 1, 0)).z;
    out[37] = distance(float2(1, 1), float2(4, 5));
    out[38] = fmod(7.5, 2.0);
    out[39] = float(uint(-1.0 < 0.0) + uint(isnan(as_type<float>(0x7fc00000u))));
}

kernel void reduce(device const uint *in [[buffer(0)]], device atomic_uint *total [[buffer(1)]], device uint *partial [[buffer(2)]],
                   uint gid [[thread_position_in_grid]], uint lid [[thread_position_in_threadgroup]],
                   uint grp [[threadgroup_position_in_grid]], uint tg [[threads_per_threadgroup]]) {
    threadgroup uint scratch[64];
    scratch[lid] = in[gid];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = tg / 2; s > 0; s >>= 1) {
        if (lid < s) scratch[lid] += scratch[lid + s];
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (lid == 0) {
        partial[grp] = scratch[0];
        atomic_fetch_add_explicit(total, scratch[0], memory_order_relaxed);
    }
}

kernel void image(texture2d<float, access::write> dst [[texture(0)]], texture2d<float> src [[texture(1)]], sampler smp [[sampler(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    constexpr sampler nearest(coord::pixel, filter::nearest, address::clamp_to_edge);
    if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) return;
    float4 a = src.read(gid / 2);
    float4 b = src.sample(nearest, float2(gid / 2) + 0.5);
    float4 c = src.sample(smp, (float2(gid) + 0.5) / float2(dst.get_width(), dst.get_height()), level(0));
    dst.write(float4(a.r, b.g, c.b, 1.0), gid);
}
