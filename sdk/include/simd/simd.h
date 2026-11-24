/* scion SDK — <simd/simd.h> subset: Apple's vector/matrix types (clang ext_vector_type), same layout as Apple's */
#pragma once
#include <stdint.h>
#define MW_SIMD_TYPES(T, N) \
    typedef T simd_##N##2 __attribute__((ext_vector_type(2))); typedef T simd_##N##3 __attribute__((ext_vector_type(3))); \
    typedef T simd_##N##4 __attribute__((ext_vector_type(4))); \
    typedef simd_##N##2 vector_##N##2; typedef simd_##N##3 vector_##N##3; typedef simd_##N##4 vector_##N##4;
MW_SIMD_TYPES(float, float) MW_SIMD_TYPES(double, double) MW_SIMD_TYPES(int32_t, int) MW_SIMD_TYPES(uint32_t, uint)
MW_SIMD_TYPES(int16_t, short) MW_SIMD_TYPES(uint16_t, ushort) MW_SIMD_TYPES(int8_t, char) MW_SIMD_TYPES(uint8_t, uchar)
#undef MW_SIMD_TYPES
typedef struct { simd_float2 columns[2]; } simd_float2x2;
typedef struct { simd_float3 columns[3]; } simd_float3x3;
typedef struct { simd_float4 columns[4]; } simd_float4x4;
typedef simd_float2x2 matrix_float2x2; typedef simd_float3x3 matrix_float3x3; typedef simd_float4x4 matrix_float4x4;
static const simd_float4x4 matrix_identity_float4x4 = {{{1, 0, 0, 0}, {0, 1, 0, 0}, {0, 0, 1, 0}, {0, 0, 0, 1}}};
static inline simd_float4x4 simd_matrix(simd_float4 a, simd_float4 b, simd_float4 c, simd_float4 d) { simd_float4x4 m = {{a, b, c, d}}; return m; }
static inline simd_float4 simd_mul_v(simd_float4x4 m, simd_float4 v) { return m.columns[0] * v.x + m.columns[1] * v.y + m.columns[2] * v.z + m.columns[3] * v.w; }
static inline simd_float4x4 simd_mul(simd_float4x4 a, simd_float4x4 b) {
    simd_float4x4 r; for (int i = 0; i < 4; i++) r.columns[i] = simd_mul_v(a, b.columns[i]); return r;
}
static inline simd_float4x4 matrix_multiply(simd_float4x4 a, simd_float4x4 b) { return simd_mul(a, b); }
static inline float simd_dot3(simd_float3 a, simd_float3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
