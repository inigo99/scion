#include "air.h"

/* loops, break/continue, if/else, integer ops, a private array with dynamic index, math */
kernel void loops(device const float *in, device float *out, device int *iout, uint gid) {
    float acc = 0;
    for (int i = 0; i < 64; i++) {
        if (i % 7 == 3) continue;
        if (acc > 1000.0f) break;
        acc += in[(gid + i) % 256] * (float)(i & 3);
    }
    int lut[8];
    for (int i = 0; i < 8; i++) lut[i] = (int)(gid * 3 + i) ^ (i << 2);
    int k = lut[gid & 7] / 3 - (int)(gid % 5);
    int n = 0, x = (int)gid + 1;
    while (x != 1 && n < 200) { x = (x & 1) ? 3 * x + 1 : x >> 1; n++; } /* collatz steps */
    out[gid] = acc + air_sin((float)gid * 0.01f) * air_sqrt((float)gid) + air_pow(2.0f, (float)(gid & 7)) + air_clamp(in[gid], -1.0f, 1.0f);
    iout[gid * 2] = air_min_s(k, 1000) + air_max_u(gid, 3u);
    iout[gid * 2 + 1] = n;
}

/* threadgroup memory + barriers: tree reduction of 256 values per group, then a device atomic */
kernel void reduce(device const uint *in, device uint *sums, device uint *total, uint gid, uint lid, uint grp) {
    static threadgroup uint shared[256];
    static threadgroup ushort halves[256];
    shared[lid] = in[gid];
    halves[lid] = (ushort)(lid * 3);
    air_wg_barrier(2, 1);
    for (uint s = 128; s > 0; s >>= 1) {
        if (lid < s) shared[lid] += shared[lid + s];
        air_wg_barrier(2, 1);
    }
    if (lid == 0) {
        sums[grp] = shared[0] + halves[255];
        air_atomic_add(total, shared[0], 0, 2, 0);
    }
}

/* structs with float3 (16-byte aligned), sub-word fields, program-scope constant table */
typedef struct { float3 p; uchar tag; ushort id; half h; float w; } Item;
constant float table[4] = {1.5f, -2.0f, 0.25f, 8.0f};
kernel void structs(device Item *items, device float4 *out, uint gid) {
    Item it = items[gid];
    float s = air_dot3(it.p, it.p) + (float)it.tag + (float)it.id + (float)it.h + it.w * table[gid & 3];
    it.tag = (uchar)(it.tag + 1);
    it.id = (ushort)(it.id * 2);
    it.h = (half)((float)it.h * 0.5f);
    items[gid] = it;
    out[gid] = (float4){s, it.p.y, air_convert_f_u(gid), table[(gid + 1) & 3]};
}

/* SIMD-group operations (subgroups) and bfloat. The kernel reports its lane and SIMD-group size, so the check works
 * whatever subgroup size the GPU uses (Apple: 32). */
kernel void simdk(device const float *in, device float *out, device uint *info, device ushort *bf, uint gid, uint lane, uint simdsz) {
    float v = in[gid];
    out[gid * 4 + 0] = air_simd_sum(v);
    out[gid * 4 + 1] = air_simd_prefix_exclusive_sum(v);
    out[gid * 4 + 2] = air_simd_shuffle_down(v, (ushort)1);
    out[gid * 4 + 3] = air_simd_max(v) + (float)air_simd_sum_i((int)v) + (air_simd_any(v > 5.5f) ? 1000.0f : 0.0f);
    info[gid * 2] = lane;
    info[gid * 2 + 1] = simdsz;
    __bf16 b = (__bf16)(v * 3.3f + 0.1f);
    b = (__bf16)((float)b * 1.5f);
    bf[gid] = __builtin_bit_cast(ushort, b);
}

/* function constants: values chosen when the pipeline is created (MTLFunctionConstantValues) */
extern constant uint fc_mode __attribute__((section("air.fc_initializer")));
extern constant float fc_scale __attribute__((section("air.fc_initializer")));
kernel void fck(device float *out, uint gid) {
    out[gid] = (fc_mode == 2 ? 100.0f : 0.0f) + (float)gid * fc_scale;
}
