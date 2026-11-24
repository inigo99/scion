/* air.h — write AIR test kernels in C: clang emits LLVM IR with Metal's address spaces and air.* calls;
 * mkmetallib.py adds the !air.* metadata and packs a real MTLB container. Only for testing air2spv. */
#define device __attribute__((address_space(1)))
#define constant const __attribute__((address_space(2)))
#define threadgroup __attribute__((address_space(3)))
#define kernel __attribute__((used))
typedef unsigned int uint;
typedef unsigned short ushort;
typedef unsigned char uchar;
typedef float float2 __attribute__((ext_vector_type(2)));
typedef float float3 __attribute__((ext_vector_type(3)));
typedef float float4 __attribute__((ext_vector_type(4)));
typedef uint uint3 __attribute__((ext_vector_type(3)));
typedef _Float16 half;
float air_sin(float) __asm("air.fast_sin.f32");
float air_cos(float) __asm("air.fast_cos.f32");
float air_pow(float, float) __asm("air.fast_pow.f32");
float air_sqrt(float) __asm("air.fast_sqrt.f32");
float air_fmax(float, float) __asm("air.fast_fmax.f32");
float air_clamp(float, float, float) __asm("air.fast_clamp.f32");
float air_dot3(float3, float3) __asm("air.dot.v3f32");
int air_min_s(int, int) __asm("air.min.s.i32");
uint air_max_u(uint, uint) __asm("air.max.u.i32");
float air_convert_f_u(uint) __asm("air.convert.f.f32.u.i32");
void air_wg_barrier(int flags, int scope) __asm("air.wg.barrier");
uint air_atomic_add(device uint *p, uint v, int order, int scope, _Bool vol) __asm("air.atomic.global.add.u.i32");
uint air_atomic_local_add(threadgroup uint *p, uint v, int order, int scope, _Bool vol) __asm("air.atomic.local.add.u.i32");
float air_simd_sum(float) __asm("air.simd_sum.f32");
int air_simd_sum_i(int) __asm("air.simd_sum.s.i32");
float air_simd_prefix_exclusive_sum(float) __asm("air.simd_prefix_exclusive_sum.f32");
float air_simd_shuffle_down(float, ushort) __asm("air.simd_shuffle_down.f32");
float air_simd_max(float) __asm("air.simd_max.f32");
_Bool air_simd_any(_Bool) __asm("air.simd_any");
