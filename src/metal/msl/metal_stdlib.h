// metal_stdlib for scion: the Metal Shading Language on top of clang's "C++ for OpenCL" (spir64).
// msl.cpp prepends this to the shader source after rewriting [[attributes]] into clang::annotate and
// vector constructors (float4(...)) into __mw_make<metal::float4>(...). Calls to air.* functions are what
// air2spv translates, the same names Apple's compiler emits.
#pragma OPENCL EXTENSION cl_khr_fp16 : enable
/* OpenCL keywords that are plain identifiers in MSL */
#define global __mw_global
#define local __mw_local
#define generic __mw_generic
#define read_write __mw_read_write
#define read_only __mw_read_only
#define write_only __mw_write_only
#define pipe __mw_pipe
#define coherent(x)
#define atomic_int __mw_atomic_int
#define atomic_uint __mw_atomic_uint
#define atomic_float __mw_atomic_float
#define atomic_bool __mw_atomic_bool
#define atomic_long __mw_atomic_long
#define atomic_ulong __mw_atomic_ulong
#define atomic_double __mw_atomic_double
#define atomic_flag __mw_atomic_flag
#define atomic_size_t __mw_atomic_size_t
#define atomic_intptr_t __mw_atomic_intptr_t
#define atomic_uintptr_t __mw_atomic_uintptr_t
#define atomic_ptrdiff_t __mw_atomic_ptrdiff_t
#define memory_order __mw_memory_order
#define memory_scope __mw_memory_scope
#define device __global
#define constant __constant
#define threadgroup __local
#define thread __private
#define threadgroup_imageblock __local
#define ray_data __private
#define object_data __private
#define kernel [[clang::annotate("air:kernel")]]
#define vertex [[clang::annotate("air:vertex")]]
#define fragment [[clang::annotate("air:fragment")]]
#define METAL_FUNC inline __attribute__((always_inline))
#define __METAL_VERSION__ 310
#define __METAL_MACOS__ 1
#define MAXFLOAT 0x1.fffffep+127f
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define HUGE_VALF __builtin_inff()
#define FLT_MAX 0x1.fffffep+127f
#define FLT_MIN 0x1p-126f
#define FLT_EPSILON 0x1p-23f
#define HALF_MAX 65504.0h
#define M_PI_F 3.14159265358979323846f
#define M_PI_2_F 1.57079632679489661923f
#define M_PI_4_F 0.78539816339744830962f
#define M_1_PI_F 0.31830988618379067154f
#define M_2_PI_F 0.63661977236758134308f
#define M_E_F 2.71828182845904523536f
#define M_LOG2E_F 1.44269504088896340736f
#define M_LN2_F 0.69314718055994530942f
#define M_SQRT2_F 1.41421356237309504880f
#define M_SQRT1_2_F 0.70710678118654752440f
#define M_PI_H 3.14159265358979323846h

namespace std {
template <class E> class initializer_list {
    const E *b; __SIZE_TYPE__ n;
    constexpr initializer_list(const E *p, __SIZE_TYPE__ s) : b(p), n(s) {}
public:
    constexpr initializer_list() : b(nullptr), n(0) {}
    constexpr __SIZE_TYPE__ size() const { return n; }
    constexpr const E *begin() const { return b; }
    constexpr const E *end() const { return b + n; }
};
}
namespace metal {
typedef unsigned char uchar;
typedef unsigned short ushort;
typedef unsigned int uint;
typedef unsigned long ulong;
typedef __SIZE_TYPE__ size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
typedef signed char int8_t;
typedef unsigned char uint8_t;
typedef short int16_t;
typedef unsigned short uint16_t;
typedef int int32_t;
typedef unsigned int uint32_t;
typedef long int64_t;
typedef unsigned long uint64_t;

template <class T, int N> using vec = T __attribute__((ext_vector_type(N)));
#define MW_VEC(T) typedef vec<T, 2> T##2; typedef vec<T, 3> T##3; typedef vec<T, 4> T##4;
MW_VEC(float) MW_VEC(half) MW_VEC(int) MW_VEC(uint) MW_VEC(short) MW_VEC(ushort) MW_VEC(char) MW_VEC(uchar) MW_VEC(long) MW_VEC(ulong)
#ifndef __MW_NO_BOOLVEC
MW_VEC(bool)
#endif
#define MW_PACKED(T) typedef T##2 packed_##T##2 __attribute__((aligned(sizeof(T)))); typedef T##4 packed_##T##4 __attribute__((aligned(sizeof(T))));
MW_PACKED(float) MW_PACKED(half) MW_PACKED(int) MW_PACKED(uint) MW_PACKED(short) MW_PACKED(ushort) MW_PACKED(char) MW_PACKED(uchar)

/* ---- type traits (address spaces stripped) */
template <class T> struct __rm_as { typedef T type; };
template <class T> struct __rm_as<__private T> { typedef T type; };
template <class T> struct __rm_as<__global T> { typedef T type; };
template <class T> struct __rm_as<__local T> { typedef T type; };
template <class T> struct __rm_as<__constant T> { typedef T type; };
template <class T> struct __rm_as<__generic T> { typedef T type; };
template <class T> struct __rm_as<const T> { typedef typename __rm_as<T>::type type; };
template <class T> struct __rm_as<volatile T> { typedef typename __rm_as<T>::type type; };
template <class T> struct __vt0 { typedef T elem; static constexpr int n = 1; static constexpr bool packed = false; };
template <class T, int N> struct __vt0<T __attribute__((ext_vector_type(N)))> { typedef T elem; static constexpr int n = N; static constexpr bool packed = false; };
template <class T> using __vt = __vt0<typename __rm_as<T>::type>;
template <class T> struct packed3 {
    T x, y, z;
    packed3() = default;
    packed3(vec<T, 3> v) : x(v.x), y(v.y), z(v.z) {}
    operator vec<T, 3>() const { vec<T, 3> r; r.x = x; r.y = y; r.z = z; return r; }
    T &operator[](int i) { return (&x)[i]; }
    T operator[](int i) const { return (&x)[i]; }
};
template <class T> struct __vt0<packed3<T>> { typedef T elem; static constexpr int n = 3; static constexpr bool packed = true; };
typedef packed3<float> packed_float3; typedef packed3<half> packed_half3; typedef packed3<int> packed_int3; typedef packed3<uint> packed_uint3;
typedef packed3<short> packed_short3; typedef packed3<ushort> packed_ushort3; typedef packed3<char> packed_char3; typedef packed3<uchar> packed_uchar3;

template <bool B, class T = void> struct enable_if {};
template <class T> struct enable_if<true, T> { typedef T type; };
template <bool B, class T = void> using enable_if_t = typename enable_if<B, T>::type;
template <class A, class B> struct is_same { static constexpr bool value = false; };
template <class A> struct is_same<A, A> { static constexpr bool value = true; };
template <class A, class B> constexpr bool is_same_v = is_same<A, B>::value;
template <class T> struct is_floating_point { static constexpr bool value = is_same_v<T, float> || is_same_v<T, half>; };
template <class T> constexpr bool is_floating_point_v = is_floating_point<T>::value;
template <class T> struct is_scalar { static constexpr bool value = __vt<T>::n == 1; };
template <class T> constexpr bool is_vector_v = __vt<T>::n > 1;
template <class T> T &&declval();
template <class T> struct is_integral { static constexpr bool value = !is_floating_point<typename __vt<T>::elem>::value; };
template <class T> constexpr bool is_integral_v = is_integral<T>::value;
template <class T> struct remove_cv { typedef typename __rm_as<T>::type type; };
template <class T> using remove_cv_t = typename remove_cv<T>::type;
template <class T> struct make_unsigned { typedef T type; };
template <> struct make_unsigned<int> { typedef uint type; };
template <> struct make_unsigned<short> { typedef ushort type; };
template <> struct make_unsigned<char> { typedef uchar type; };
template <class T> struct numeric_limits {};
template <> struct numeric_limits<float> {
    static constexpr float max() { return FLT_MAX; } static constexpr float min() { return FLT_MIN; }
    static constexpr float lowest() { return -FLT_MAX; } static constexpr float infinity() { return __builtin_inff(); }
    static constexpr float epsilon() { return FLT_EPSILON; } static constexpr float quiet_NaN() { return __builtin_nanf(""); }
};
template <> struct numeric_limits<half> {
    static constexpr half max() { return 65504.0h; } static constexpr half lowest() { return -65504.0h; }
    static constexpr half infinity() { return (half)__builtin_inff(); } static constexpr half min() { return 6.10352e-5h; }
    static constexpr half epsilon() { return 0.000976562h; }
};
template <> struct numeric_limits<int> { static constexpr int max() { return 0x7fffffff; } static constexpr int min() { return -0x7fffffff - 1; } static constexpr int lowest() { return min(); } };
template <> struct numeric_limits<uint> { static constexpr uint max() { return 0xffffffffu; } static constexpr uint min() { return 0; } static constexpr uint lowest() { return 0; } };
template <> struct numeric_limits<short> { static constexpr short max() { return 0x7fff; } static constexpr short min() { return -0x8000; } };
template <> struct numeric_limits<ushort> { static constexpr ushort max() { return 0xffff; } static constexpr ushort min() { return 0; } };

/* ---- vector construction: float4(a.xy, 1, b), float3(x), half4(float4) ... */
template <class V, class A> inline void __mw_put(thread V &r, thread int &i, A a) {
    typedef typename __vt<V>::elem E;
    typedef typename __rm_as<A>::type AT;
    if constexpr (__vt<A>::packed) __mw_put(r, i, (vec<typename __vt<A>::elem, 3>)a);
    else if constexpr (__vt<A>::n == 1) r[i++] = (E)a;
    else {
        vec<E, __vt<A>::n> c = __builtin_convertvector((AT)a, vec<E, __vt<A>::n>);
        for (int j = 0; j < __vt<A>::n; j++) r[i++] = c[j];
    }
}
} // namespace metal
template <class V, class... A> inline V __mw_make(A... a) {
    using namespace metal;
    if constexpr (__vt<V>::packed) return V(__mw_make<vec<typename __vt<V>::elem, 3>>(a...));
    else {
        typedef typename __vt<V>::elem E;
        if constexpr (sizeof...(A) == 0) return V(0);
        else if constexpr (sizeof...(A) == 1 && (__vt<A>::n + ...) == 1 && !(__vt<A>::packed || ...)) { E e = (E)(a + ...); return V(e); }
        else {
            V r;
            int i = 0;
            (__mw_put(r, i, a), ...);
            return r;
        }
    }
}
namespace metal {
template <class T, class U> inline T as_type(U u) { return __builtin_bit_cast(T, (typename __rm_as<U>::type)u); }

/* ---- matrices (column-major, columns are vectors) */
template <class T, int C, int R> struct matrix {
    vec<T, R> columns[C];
    matrix() = default;
    template <class... A> matrix(A... a) {
        if constexpr (sizeof...(A) == 1 && (__vt<A>::n + ...) == 1) { /* diagonal */
            T d = (T)(a + ...);
            for (int c = 0; c < C; c++) { columns[c] = vec<T, R>(0); if (c < R) columns[c][c] = d; }
        } else if constexpr (sizeof...(A) == C) { /* columns */
            int c = 0;
            ((columns[c++] = __mw_make<vec<T, R>>(a)), ...);
        } else { /* C*R scalars, column-major */
            T s[] = {(T)a...};
            for (int c = 0; c < C; c++) for (int r = 0; r < R; r++) columns[c][r] = s[c * R + r];
        }
    }
    template <class U> explicit matrix(const matrix<U, C, R> &m) { for (int c = 0; c < C; c++) columns[c] = __builtin_convertvector(m.columns[c], vec<T, R>); }
    vec<T, R> &operator[](int i) { return columns[i]; }
    vec<T, R> operator[](int i) const { return columns[i]; }
};
#define MW_MAT(T) typedef matrix<T, 2, 2> T##2x2; typedef matrix<T, 2, 3> T##2x3; typedef matrix<T, 2, 4> T##2x4; \
    typedef matrix<T, 3, 2> T##3x2; typedef matrix<T, 3, 3> T##3x3; typedef matrix<T, 3, 4> T##3x4; \
    typedef matrix<T, 4, 2> T##4x2; typedef matrix<T, 4, 3> T##4x3; typedef matrix<T, 4, 4> T##4x4;
MW_MAT(float) MW_MAT(half)
template <class T, int C, int R> inline vec<T, R> operator*(const matrix<T, C, R> &m, vec<T, C> v) {
    vec<T, R> r = m.columns[0] * v[0];
    for (int c = 1; c < C; c++) r += m.columns[c] * v[c];
    return r;
}
template <class T, int C, int R> inline vec<T, C> operator*(vec<T, R> v, const matrix<T, C, R> &m) {
    vec<T, C> r;
    for (int c = 0; c < C; c++) { vec<T, R> p = m.columns[c] * v; T s = p[0]; for (int i = 1; i < R; i++) s += p[i]; r[c] = s; }
    return r;
}
template <class T, int K, int C, int R> inline matrix<T, C, R> operator*(const matrix<T, K, R> &a, const matrix<T, C, K> &b) {
    matrix<T, C, R> r;
    for (int c = 0; c < C; c++) r.columns[c] = a * b.columns[c];
    return r;
}
template <class T, int C, int R> inline matrix<T, C, R> operator*(const matrix<T, C, R> &m, T s) { matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = m.columns[c] * s; return r; }
template <class T, int C, int R> inline matrix<T, C, R> operator*(T s, const matrix<T, C, R> &m) { return m * s; }
template <class T, int C, int R> inline matrix<T, C, R> operator+(const matrix<T, C, R> &a, const matrix<T, C, R> &b) { matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = a.columns[c] + b.columns[c]; return r; }
template <class T, int C, int R> inline matrix<T, C, R> operator-(const matrix<T, C, R> &a, const matrix<T, C, R> &b) { matrix<T, C, R> r; for (int c = 0; c < C; c++) r.columns[c] = a.columns[c] - b.columns[c]; return r; }
template <class T, int C, int R> inline thread matrix<T, C, R> &operator*=(thread matrix<T, C, R> &a, const matrix<T, C, C> &b) { a = a * b; return a; }
template <class T, int C, int R> inline matrix<T, R, C> transpose(const matrix<T, C, R> &m) {
    matrix<T, R, C> r;
    for (int c = 0; c < C; c++) for (int i = 0; i < R; i++) r.columns[i][c] = m.columns[c][i];
    return r;
}
template <class T> inline T determinant(const matrix<T, 2, 2> &m) { return m[0][0] * m[1][1] - m[1][0] * m[0][1]; }
template <class T> inline T determinant(const matrix<T, 3, 3> &m) {
    return m[0][0] * (m[1][1] * m[2][2] - m[2][1] * m[1][2]) - m[1][0] * (m[0][1] * m[2][2] - m[2][1] * m[0][2]) + m[2][0] * (m[0][1] * m[1][2] - m[1][1] * m[0][2]);
}
template <class T> inline T determinant(const matrix<T, 4, 4> &m) {
    T r = 0;
    for (int c = 0; c < 4; c++) {
        matrix<T, 3, 3> s;
        for (int i = 0, k = 0; i < 4; i++) if (i != c) { s.columns[k++] = m.columns[i].yzw; }
        r += (c & 1 ? -1 : 1) * m.columns[c][0] * determinant(s);
    }
    return r;
}

/* ---- math: air.<name>.<type>, see air2spv kMath */
#define MW_FTYPES(X, ...) X(float, f32, __VA_ARGS__) X(float2, v2f32, __VA_ARGS__) X(float3, v3f32, __VA_ARGS__) X(float4, v4f32, __VA_ARGS__) \
    X(half, f16, __VA_ARGS__) X(half2, v2f16, __VA_ARGS__) X(half3, v3f16, __VA_ARGS__) X(half4, v4f16, __VA_ARGS__)
#define MW_STYPES(X, ...) X(int, s.i32, __VA_ARGS__) X(int2, s.v2i32, __VA_ARGS__) X(int3, s.v3i32, __VA_ARGS__) X(int4, s.v4i32, __VA_ARGS__) \
    X(short, s.i16, __VA_ARGS__) X(short2, s.v2i16, __VA_ARGS__) X(short3, s.v3i16, __VA_ARGS__) X(short4, s.v4i16, __VA_ARGS__) \
    X(char, s.i8, __VA_ARGS__) X(char2, s.v2i8, __VA_ARGS__) X(char3, s.v3i8, __VA_ARGS__) X(char4, s.v4i8, __VA_ARGS__)
#define MW_UTYPES(X, ...) X(uint, u.i32, __VA_ARGS__) X(uint2, u.v2i32, __VA_ARGS__) X(uint3, u.v3i32, __VA_ARGS__) X(uint4, u.v4i32, __VA_ARGS__) \
    X(ushort, u.i16, __VA_ARGS__) X(ushort2, u.v2i16, __VA_ARGS__) X(ushort3, u.v3i16, __VA_ARGS__) X(ushort4, u.v4i16, __VA_ARGS__) \
    X(uchar, u.i8, __VA_ARGS__) X(uchar2, u.v2i8, __VA_ARGS__) X(uchar3, u.v3i8, __VA_ARGS__) X(uchar4, u.v4i8, __VA_ARGS__)
#define MW_D1(T, S, name) T name(T) __asm("air." #name "." #S);
#define MW_D2(T, S, name) T name(T, T) __asm("air." #name "." #S);
#define MW_D3(T, S, name) T name(T, T, T) __asm("air." #name "." #S);
#define MW_DA(T, S, name, air) T name(T) __asm("air." #air "." #S);
#define MW_DA2(T, S, name, air) T name(T, T) __asm("air." #air "." #S);
MW_FTYPES(MW_D1, sin) MW_FTYPES(MW_D1, cos) MW_FTYPES(MW_D1, tan) MW_FTYPES(MW_D1, asin) MW_FTYPES(MW_D1, acos) MW_FTYPES(MW_D1, atan)
MW_FTYPES(MW_D1, sinh) MW_FTYPES(MW_D1, cosh) MW_FTYPES(MW_D1, tanh) MW_FTYPES(MW_D1, asinh) MW_FTYPES(MW_D1, acosh) MW_FTYPES(MW_D1, atanh)
MW_FTYPES(MW_D1, exp) MW_FTYPES(MW_D1, exp2) MW_FTYPES(MW_D1, exp10) MW_FTYPES(MW_D1, log) MW_FTYPES(MW_D1, log2) MW_FTYPES(MW_D1, log10)
MW_FTYPES(MW_D1, sqrt) MW_FTYPES(MW_D1, rsqrt) MW_FTYPES(MW_D1, floor) MW_FTYPES(MW_D1, ceil) MW_FTYPES(MW_D1, trunc) MW_FTYPES(MW_D1, rint)
MW_FTYPES(MW_D1, round) MW_FTYPES(MW_D1, fract) MW_FTYPES(MW_D1, fabs) MW_FTYPES(MW_D1, sign) MW_FTYPES(MW_D1, saturate) MW_FTYPES(MW_DA, abs, fabs)
MW_FTYPES(MW_D2, atan2) MW_FTYPES(MW_D2, pow) MW_FTYPES(MW_D2, powr) MW_FTYPES(MW_D2, fmin) MW_FTYPES(MW_D2, fmax) MW_FTYPES(MW_D2, fmod)
MW_FTYPES(MW_DA2, min, fmin) MW_FTYPES(MW_DA2, max, fmax) MW_FTYPES(MW_D2, step) MW_FTYPES(MW_D2, fdim)
MW_FTYPES(MW_D3, fma) MW_FTYPES(MW_D3, mix) MW_FTYPES(MW_D3, smoothstep) MW_FTYPES(MW_D3, clamp)
MW_FTYPES(MW_D1, dfdx) MW_FTYPES(MW_D1, dfdy) MW_FTYPES(MW_D1, fwidth)
MW_STYPES(MW_D2, min) MW_STYPES(MW_D2, max) MW_STYPES(MW_D3, clamp) MW_STYPES(MW_D1, abs)
MW_UTYPES(MW_D2, min) MW_UTYPES(MW_D2, max) MW_UTYPES(MW_D3, clamp)
MW_STYPES(MW_D1, popcount) MW_UTYPES(MW_D1, popcount) MW_STYPES(MW_D1, clz) MW_UTYPES(MW_D1, clz) MW_STYPES(MW_D1, ctz) MW_UTYPES(MW_D1, ctz)
#define MW_GEO(T, S, unused) float length(T) __asm("air.length." #S); float distance(T, T) __asm("air.distance." #S); \
    T normalize(T) __asm("air.normalize." #S); float dot(T, T) __asm("air.dot." #S); T reflect(T, T) __asm("air.reflect." #S); \
    T refract(T, T, float) __asm("air.refract." #S);
MW_GEO(float2, v2f32, 0) MW_GEO(float3, v3f32, 0) MW_GEO(float4, v4f32, 0)
#define MW_GEOH(T, S, unused) half length(T) __asm("air.length." #S); half distance(T, T) __asm("air.distance." #S); \
    T normalize(T) __asm("air.normalize." #S); half dot(T, T) __asm("air.dot." #S); T reflect(T, T) __asm("air.reflect." #S); \
    T refract(T, T, half) __asm("air.refract." #S);
MW_GEOH(half2, v2f16, 0) MW_GEOH(half3, v3f16, 0) MW_GEOH(half4, v4f16, 0)
float3 cross(float3, float3) __asm("air.cross.v3f32");
half3 cross(half3, half3) __asm("air.cross.v3f16");
inline int dot(int2 a, int2 b) { int2 p = a * b; return p.x + p.y; }
inline int dot(int3 a, int3 b) { int3 p = a * b; return p.x + p.y + p.z; }
inline int dot(int4 a, int4 b) { int4 p = a * b; return p.x + p.y + p.z + p.w; }
inline uint dot(uint2 a, uint2 b) { uint2 p = a * b; return p.x + p.y; }
inline uint dot(uint3 a, uint3 b) { uint3 p = a * b; return p.x + p.y + p.z; }
inline uint dot(uint4 a, uint4 b) { uint4 p = a * b; return p.x + p.y + p.z + p.w; }
inline float length_squared(float2 v) { return dot(v, v); }
inline float length_squared(float3 v) { return dot(v, v); }
inline float length_squared(float4 v) { return dot(v, v); }
inline float distance_squared(float2 a, float2 b) { return length_squared(a - b); }
inline float distance_squared(float3 a, float3 b) { return length_squared(a - b); }
inline float distance_squared(float4 a, float4 b) { return length_squared(a - b); }
template <class T> inline T faceforward(T n, T i, T nref) { return dot(nref, i) < 0 ? n : -n; }
template <class T> inline T frexp(T x, thread int &e) { if (x == 0) { e = 0; return x; } int ex = int((as_type<uint>(float(x)) >> 23) & 255) - 126; e = ex; return T(float(x) * exp2(float(-ex))); }
/* scalar arguments mixed with vectors: mix(v, w, 0.5), clamp(v, 0.0, 1.0), step(0.5, v), pow(v, 2.0) ... */
#define MW_SPLAT(T, S, unused) \
    inline T mix(T a, T b, __vt<T>::elem t) { return mix(a, b, T(t)); } \
    inline T clamp(T x, __vt<T>::elem a, __vt<T>::elem b) { return clamp(x, T(a), T(b)); } \
    inline T step(__vt<T>::elem e, T x) { return step(T(e), x); } \
    inline T smoothstep(__vt<T>::elem a, __vt<T>::elem b, T x) { return smoothstep(T(a), T(b), x); } \
    inline T min(T a, __vt<T>::elem b) { return min(a, T(b)); } \
    inline T max(T a, __vt<T>::elem b) { return max(a, T(b)); } \
    inline T fmin(T a, __vt<T>::elem b) { return fmin(a, T(b)); } \
    inline T fmax(T a, __vt<T>::elem b) { return fmax(a, T(b)); } \
    inline T pow(T a, __vt<T>::elem b) { return pow(a, T(b)); } \
    inline T powr(T a, __vt<T>::elem b) { return powr(a, T(b)); } \
    inline T fmod(T a, __vt<T>::elem b) { return fmod(a, T(b)); }
MW_SPLAT(float2, 0, 0) MW_SPLAT(float3, 0, 0) MW_SPLAT(float4, 0, 0) MW_SPLAT(half2, 0, 0) MW_SPLAT(half3, 0, 0) MW_SPLAT(half4, 0, 0)
#define MW_ISPLAT(T, S, unused) inline T min(T a, __vt<T>::elem b) { return min(a, T(b)); } inline T max(T a, __vt<T>::elem b) { return max(a, T(b)); } \
    inline T clamp(T x, __vt<T>::elem a, __vt<T>::elem b) { return clamp(x, T(a), T(b)); }
MW_ISPLAT(int2, 0, 0) MW_ISPLAT(int3, 0, 0) MW_ISPLAT(int4, 0, 0) MW_ISPLAT(uint2, 0, 0) MW_ISPLAT(uint3, 0, 0) MW_ISPLAT(uint4, 0, 0)
template <class T> inline T ldexp(T x, int e) { return x * exp2((T)(float)e); }
template <class T> inline T ldexp(T x, vec<int, __vt<T>::n> e) { return x * exp2(__builtin_convertvector(e, T)); }
template <class T> inline T divide(T a, T b) { return a / b; }
template <class T> inline T sincos(T x, thread T &c) { c = cos(x); return sin(x); }
template <class T> inline T modf(T x, thread T &ip) { ip = trunc(x); return x - ip; }
template <class T> inline T copysign(T a, T b) { return __builtin_elementwise_copysign(a, b); }
template <class T> inline T fmin3(T a, T b, T c) { return fmin(fmin(a, b), c); }
template <class T> inline T fmax3(T a, T b, T c) { return fmax(fmax(a, b), c); }
template <class T> inline T min3(T a, T b, T c) { return min(min(a, b), c); }
template <class T> inline T max3(T a, T b, T c) { return max(max(a, b), c); }
template <class T> inline T median3(T a, T b, T c) { return max(min(a, b), min(max(a, b), c)); }
template <class T> inline T reverse_bits(T x) { return __builtin_elementwise_bitreverse(x); }
template <class T> inline T extract_bits(T x, uint o, uint b) { return b == 32 ? x : (x >> o) & (T)((1u << b) - 1); }
template <class T> inline T insert_bits(T x, T y, uint o, uint b) { T m = (T)(((b == 32 ? 0u : (1u << b)) - 1) << o); return (x & ~m) | ((y << o) & m); }
template <class T> inline T mad(T a, T b, T c) { return a * b + c; }
template <class T> inline T absdiff(T a, T b) { return a > b ? a - b : b - a; }
template <class T> inline T rotate(T v, T n) { uint s = (uint)n & 31; return (v << s) | (v >> ((32 - s) & 31)); }
template <class T> inline T mulhi(T a, T b) {
    typedef typename __vt<T>::elem E;
    constexpr int n = __vt<T>::n;
    if constexpr (n == 1) { if constexpr (sizeof(E) == 4) return (T)(((E(-1) < 0 ? (ulong)(long)a : (ulong)a) * (E(-1) < 0 ? (ulong)(long)b : (ulong)b)) >> 32); else return (T)(((long)a * (long)b) >> (8 * sizeof(E))); }
    else { T r; for (int i = 0; i < n; i++) r[i] = mulhi(a[i], b[i]); return r; }
}
template <class T> inline T rhadd(T a, T b) { return (a >> 1) + (b >> 1) + ((a | b) & 1); }
template <class T> inline T addsat(T a, T b) { return __builtin_elementwise_add_sat(a, b); }
template <class T> inline T subsat(T a, T b) { return __builtin_elementwise_sub_sat(a, b); }
template <class T> inline T hadd(T a, T b) { return (a >> 1) + (b >> 1) + (a & b & 1); }

/* relational: comparisons give boolN */
template <class T> inline bool any(T v) { if constexpr (__vt<T>::n == 1) return v; else { bool r = false; for (int i = 0; i < __vt<T>::n; i++) r = r || v[i]; return r; } }
template <class T> inline bool all(T v) { if constexpr (__vt<T>::n == 1) return v; else { bool r = true; for (int i = 0; i < __vt<T>::n; i++) r = r && v[i]; return r; } }
template <class T, class B> inline T select(T a, T b, B c) {
    if constexpr (__vt<B>::n == 1) return c ? b : a;
    else { T r; for (int i = 0; i < __vt<T>::n; i++) r[i] = c[i] ? b[i] : a[i]; return r; }
}
template <class T> inline auto isnan(T x) { return x != x; }
template <class T> inline auto isinf(T x) { return __builtin_elementwise_abs(x) == (T)__builtin_inff(); }
template <class T> inline auto isfinite(T x) { return __builtin_elementwise_abs(x) < (T)__builtin_inff(); }
template <class T> inline auto isnormal(T x) { return isfinite(x) & (__builtin_elementwise_abs(x) >= (T)FLT_MIN); }
template <class T> inline auto signbit(T x) { return as_type<typename enable_if<sizeof(T) == sizeof(T), vec<int, __vt<T>::n>>::type>(x) < 0; }
inline bool signbit(float x) { return as_type<int>(x) < 0; }
template <class T> inline auto isordered(T a, T b) { return (a == a) & (b == b); }
template <class T> inline auto isunordered(T a, T b) { return (a != a) | (b != b); }

namespace fast { using metal::sin; using metal::cos; using metal::tan; using metal::asin; using metal::acos; using metal::atan; using metal::atan2;
    using metal::sinh; using metal::cosh; using metal::tanh; using metal::exp; using metal::exp2; using metal::exp10; using metal::log; using metal::log2;
    using metal::log10; using metal::pow; using metal::powr; using metal::sqrt; using metal::rsqrt; using metal::floor; using metal::ceil; using metal::trunc;
    using metal::round; using metal::rint; using metal::fract; using metal::fabs; using metal::abs; using metal::fmin; using metal::fmax; using metal::min;
    using metal::max; using metal::clamp; using metal::saturate; using metal::sign; using metal::fmod; using metal::divide; using metal::normalize;
    using metal::length; using metal::distance; using metal::sincos; using metal::step; using metal::smoothstep; using metal::mix; using metal::fma; }
namespace precise { using namespace fast; }

/* ---- textures and samplers */
enum class access { sample, read, write, read_write };
enum class coord { normalized = 0, pixel = 1 };
enum class filter { nearest = 0, linear = 1 };
enum class mag_filter { nearest = 0, linear = 1 };
enum class min_filter { nearest = 0, linear = 1 };
enum class mip_filter { none = 0, nearest = 1, linear = 2 };
enum class address { clamp_to_zero = 0, clamp_to_edge = 1, repeat = 2, mirrored_repeat = 3, clamp_to_border = 4 };
enum class s_address { clamp_to_zero = 0, clamp_to_edge = 1, repeat = 2, mirrored_repeat = 3, clamp_to_border = 4 };
enum class t_address { clamp_to_zero = 0, clamp_to_edge = 1, repeat = 2, mirrored_repeat = 3, clamp_to_border = 4 };
enum class r_address { clamp_to_zero = 0, clamp_to_edge = 1, repeat = 2, mirrored_repeat = 3, clamp_to_border = 4 };
enum class compare_func { none = 0, less = 1, less_equal = 2, greater = 3, greater_equal = 4, equal = 5, not_equal = 6, always = 7, never = 8 };
enum class border_color { transparent_black = 0, opaque_black = 1, opaque_white = 2 };
enum class component { x, y, z, w };
struct max_anisotropy { int n; constexpr max_anisotropy(int a) : n(a) {} };
struct lod_clamp { ushort lo, hi; constexpr lod_clamp(float a, float b) : lo(__mw_h(a)), hi(__mw_h(b)) {}
    static constexpr ushort __mw_h(float f) { return f >= 65504.0f ? 0x7bff : f <= 0 ? 0 : (ushort)((__builtin_bit_cast(uint, f) >> 13) - (112 << 10)); } };
struct _sampler_t;
struct sampler {
    __constant _sampler_t *h;
    ulong st;
    constexpr sampler() : h(nullptr), st(1 | (1 << 3) | (1 << 6) | (0x7bffull << 40)) {}
    template <class... A> constexpr sampler(A... a) : h(nullptr), st(sampler().st) { (set(a), ...); }
    constexpr void set(coord c) { st = (st & ~(1ull << 15)) | (ulong(c) << 15); }
    constexpr void set(filter f) { st = (st & ~(0xfull << 9)) | (ulong(f) << 9) | (ulong(f) << 11); }
    constexpr void set(mag_filter f) { st = (st & ~(3ull << 9)) | (ulong(f) << 9); }
    constexpr void set(min_filter f) { st = (st & ~(3ull << 11)) | (ulong(f) << 11); }
    constexpr void set(mip_filter f) { st = (st & ~(3ull << 13)) | (ulong(f) << 13); }
    constexpr void set(address a) { st = (st & ~0x1ffull) | ulong(a) | (ulong(a) << 3) | (ulong(a) << 6); }
    constexpr void set(s_address a) { st = (st & ~7ull) | ulong(a); }
    constexpr void set(t_address a) { st = (st & ~(7ull << 3)) | (ulong(a) << 3); }
    constexpr void set(r_address a) { st = (st & ~(7ull << 6)) | (ulong(a) << 6); }
    constexpr void set(compare_func f) { st = (st & ~(0xfull << 16)) | (ulong(f) << 16); }
    constexpr void set(border_color b) { st = (st & ~(3ull << 56)) | (ulong(b) << 56); }
    constexpr void set(max_anisotropy a) { st = (st & ~(0xfull << 20)) | (ulong((a.n - 1) & 15) << 20); }
    constexpr void set(lod_clamp l) { st = (st & ~(0xffffffffull << 24)) | (ulong(l.lo) << 24) | (ulong(l.hi) << 40); }
};
/* resolved by msl.cpp: a runtime sampler's handle, or a global in !air.sampler_states for a constexpr one */
__constant _sampler_t *__mw_sampler(__constant _sampler_t *h, ulong st) __asm("__mw_sampler");
/* a sampler field of an argument buffer ([[id(n)]]): 8 bytes, the sampler's resource ID (the compiler retypes those fields) */
struct __mw_ab_sampler {
    __constant _sampler_t *h;
    operator sampler() const { sampler s; s.h = h; return s; }
};
struct _texture_t;
struct level { float lod; level(float l) : lod(l) {} };
struct bias { float b; bias(float x) : b(x) {} };
struct min_lod_clamp { float l; min_lod_clamp(float x) : l(x) {} };
struct gradient2d { float2 dx, dy; gradient2d(float2 a, float2 b) : dx(a), dy(b) {} };
struct gradient3d { float3 dx, dy; gradient3d(float3 a, float3 b) : dx(a), dy(b) {} };
struct gradientcube { float3 dx, dy; gradientcube(float3 a, float3 b) : dx(a), dy(b) {} };
/* options for the scion sample intrinsics: mode 0 none/implicit, 1 lod, 2 bias, 3 gradient */
struct __mw_opt { int mode = 0; float a = 0; float4 dx = 0, dy = 0;
    __mw_opt() {} __mw_opt(level l) : mode(1), a(l.lod) {} __mw_opt(bias b) : mode(2), a(b.b) {} __mw_opt(min_lod_clamp) {}
    __mw_opt(gradient2d g) : mode(3) { dx.xy = g.dx; dy.xy = g.dy; } __mw_opt(gradient3d g) : mode(3) { dx.xyz = g.dx; dy.xyz = g.dy; }
    __mw_opt(gradientcube g) : mode(3) { dx.xyz = g.dx; dy.xyz = g.dy; } };

/* intrinsic families: air.<op>_texture_<kind>.mw.<type> (scion extended forms, see air2spv airTexture) */
#define MW_TEXFN(K, CT, CI)                                                                                                                   \
    float4 __mw_sample_##K(__global _texture_t *, __constant _sampler_t *, CT, uint, int, float, float4, float4, int4) __asm("air.sample_texture_" #K ".mw.v4f32"); \
    half4 __mw_sample_##K##_h(__global _texture_t *, __constant _sampler_t *, CT, uint, int, float, float4, float4, int4) __asm("air.sample_texture_" #K ".mw.v4f16"); \
    int4 __mw_sample_##K##_i(__global _texture_t *, __constant _sampler_t *, CT, uint, int, float, float4, float4, int4) __asm("air.sample_texture_" #K ".mw.s.v4i32"); \
    uint4 __mw_sample_##K##_u(__global _texture_t *, __constant _sampler_t *, CT, uint, int, float, float4, float4, int4) __asm("air.sample_texture_" #K ".mw.u.v4i32"); \
    float4 __mw_gather_##K(__global _texture_t *, __constant _sampler_t *, CT, uint, int4, int) __asm("air.gather_texture_" #K ".mw.v4f32"); \
    float4 __mw_read_##K(__global _texture_t *, CI, uint, uint) __asm("air.read_texture_" #K ".mw.v4f32");                                \
    half4 __mw_read_##K##_h(__global _texture_t *, CI, uint, uint) __asm("air.read_texture_" #K ".mw.v4f16");                             \
    int4 __mw_read_##K##_i(__global _texture_t *, CI, uint, uint) __asm("air.read_texture_" #K ".mw.s.v4i32");                            \
    uint4 __mw_read_##K##_u(__global _texture_t *, CI, uint, uint) __asm("air.read_texture_" #K ".mw.u.v4i32");                           \
    void __mw_write_##K(__global _texture_t *, CI, float4, uint, uint) __asm("air.write_texture_" #K ".mw.v4f32");                        \
    void __mw_write_##K##_h(__global _texture_t *, CI, half4, uint, uint) __asm("air.write_texture_" #K ".mw.v4f16");                    \
    void __mw_write_##K##_i(__global _texture_t *, CI, int4, uint, uint) __asm("air.write_texture_" #K ".mw.s.v4i32");                   \
    void __mw_write_##K##_u(__global _texture_t *, CI, uint4, uint, uint) __asm("air.write_texture_" #K ".mw.u.v4i32");                  \
    uint __mw_width_##K(__global _texture_t *, uint) __asm("air.get_width_texture_" #K);                                             \
    uint __mw_height_##K(__global _texture_t *, uint) __asm("air.get_height_texture_" #K);                                           \
    uint __mw_depth_##K(__global _texture_t *, uint) __asm("air.get_depth_texture_" #K);                                             \
    uint __mw_array_##K(__global _texture_t *) __asm("air.get_array_size_texture_" #K);                                              \
    uint __mw_levels_##K(__global _texture_t *) __asm("air.get_num_mip_levels_texture_" #K);                                    \
    float2 __mw_lod_##K(__global _texture_t *, __constant _sampler_t *, CT) __asm("air.calculate_lod_texture_" #K);
MW_TEXFN(1d, float, uint) MW_TEXFN(1d_array, float, uint) MW_TEXFN(2d, float2, uint2) MW_TEXFN(2d_array, float2, uint2) MW_TEXFN(3d, float3, uint3)
MW_TEXFN(cube, float3, uint2) MW_TEXFN(cube_array, float3, uint2) MW_TEXFN(2d_ms, float2, uint2)
float __mw_samplecmp_depth_2d(__global _texture_t *, __constant _sampler_t *, float2, uint, float, int, float, float4, float4, int4) __asm("air.sample_compare_depth_2d.mw.f32");
float __mw_samplecmp_depth_2d_array(__global _texture_t *, __constant _sampler_t *, float2, uint, float, int, float, float4, float4, int4) __asm("air.sample_compare_depth_2d_array.mw.f32");
float __mw_samplecmp_depth_cube(__global _texture_t *, __constant _sampler_t *, float3, uint, float, int, float, float4, float4, int4) __asm("air.sample_compare_depth_cube.mw.f32");
float4 __mw_gathercmp_depth_2d(__global _texture_t *, __constant _sampler_t *, float2, uint, float, int4) __asm("air.gather_compare_depth_2d.mw.v4f32");

template <class T> struct __tex_ops;
#define MW_TEXOPS(T, sfx)                                                                                                                       \
    template <> struct __tex_ops<T> {                                                                                                          \
        template <class C> static vec<T, 4> s1d(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_1d##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        template <class C> static vec<T, 4> s1da(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_1d_array##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        template <class C> static vec<T, 4> s2d(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_2d##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        template <class C> static vec<T, 4> s2da(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_2d_array##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        template <class C> static vec<T, 4> s3d(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_3d##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        template <class C> static vec<T, 4> scube(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_cube##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        template <class C> static vec<T, 4> scubea(__global _texture_t *t, __constant _sampler_t *s, C c, uint sl, __mw_opt o, int4 off) { return __mw_sample_cube_array##sfx(t, s, c, sl, o.mode, o.a, o.dx, o.dy, off); } \
        static vec<T, 4> r1d(__global _texture_t *t, uint c, uint sl, uint l) { return __mw_read_1d##sfx(t, c, sl, l); }                   \
        static vec<T, 4> r1da(__global _texture_t *t, uint c, uint sl, uint l) { return __mw_read_1d_array##sfx(t, c, sl, l); }            \
        static vec<T, 4> r2d(__global _texture_t *t, uint2 c, uint sl, uint l) { return __mw_read_2d##sfx(t, c, sl, l); }                 \
        static vec<T, 4> r2da(__global _texture_t *t, uint2 c, uint sl, uint l) { return __mw_read_2d_array##sfx(t, c, sl, l); }          \
        static vec<T, 4> r2dms(__global _texture_t *t, uint2 c, uint sl, uint l) { return __mw_read_2d_ms##sfx(t, c, sl, l); }            \
        static vec<T, 4> r3d(__global _texture_t *t, uint3 c, uint sl, uint l) { return __mw_read_3d##sfx(t, c, sl, l); }                 \
        static vec<T, 4> rcube(__global _texture_t *t, uint2 c, uint sl, uint l) { return __mw_read_cube##sfx(t, c, sl, l); }             \
        static void w1d(__global _texture_t *t, uint c, vec<T, 4> v, uint sl, uint l) { __mw_write_1d##sfx(t, c, v, sl, l); }           \
        static void w1da(__global _texture_t *t, uint c, vec<T, 4> v, uint sl, uint l) { __mw_write_1d_array##sfx(t, c, v, sl, l); }    \
        static void w2d(__global _texture_t *t, uint2 c, vec<T, 4> v, uint sl, uint l) { __mw_write_2d##sfx(t, c, v, sl, l); }         \
        static void w2da(__global _texture_t *t, uint2 c, vec<T, 4> v, uint sl, uint l) { __mw_write_2d_array##sfx(t, c, v, sl, l); }  \
        static void w3d(__global _texture_t *t, uint3 c, vec<T, 4> v, uint sl, uint l) { __mw_write_3d##sfx(t, c, v, sl, l); }         \
        static void wcube(__global _texture_t *t, uint2 c, vec<T, 4> v, uint sl, uint l) { __mw_write_cube##sfx(t, c, v, sl, l); }     \
    };
MW_TEXOPS(float, ) MW_TEXOPS(half, _h) MW_TEXOPS(int, _i) MW_TEXOPS(uint, _u)
template <> struct __tex_ops<short> : __tex_ops<int> {};
template <> struct __tex_ops<ushort> : __tex_ops<uint> {};
#define MW_SMP(s) __mw_sampler((s).h, (s).st)
#define MW_TEXCOMMON(K)                                                                                       \
    __global _texture_t *h;                                                                                  \
    void fence() const {}                                                                                    \
    uint get_width(uint l = 0) const { return __mw_width_##K(h, l); }                                       \
    uint get_num_mip_levels() const { return __mw_levels_##K(h); }
template <class T, access A = access::sample> struct texture1d {
    MW_TEXCOMMON(1d)
    float calculate_clamped_lod(sampler s, float c) const { return __mw_lod_1d(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float c) const { return __mw_lod_1d(h, MW_SMP(s), c).y; }
    vec<T, 4> sample(sampler s, float c) const { return __tex_ops<T>::s1d(h, MW_SMP(s), c, 0, __mw_opt(), 0); }
    vec<T, 4> read(uint c, uint l = 0) const { return __tex_ops<T>::r1d(h, c, 0, l); }
    vec<T, 4> read(ushort c, ushort l = 0) const { return __tex_ops<T>::r1d(h, c, 0, l); }
    void write(vec<T, 4> v, uint c, uint l = 0) const { __tex_ops<T>::w1d(h, c, v, 0, l); }
    void write(vec<T, 4> v, ushort c, ushort l = 0) const { __tex_ops<T>::w1d(h, c, v, 0, l); }
};
template <class T, access A = access::sample> struct texture1d_array {
    MW_TEXCOMMON(1d_array)
    float calculate_clamped_lod(sampler s, float c) const { return __mw_lod_1d_array(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float c) const { return __mw_lod_1d_array(h, MW_SMP(s), c).y; }
    uint get_array_size() const { return __mw_array_1d_array(h); }
    vec<T, 4> sample(sampler s, float c, uint a) const { return __tex_ops<T>::s1da(h, MW_SMP(s), c, a, __mw_opt(), 0); }
    vec<T, 4> read(uint c, uint a, uint l = 0) const { return __tex_ops<T>::r1da(h, c, a, l); }
    void write(vec<T, 4> v, uint c, uint a, uint l = 0) const { __tex_ops<T>::w1da(h, c, v, a, l); }
};
template <class T, access A = access::sample> struct texture2d {
    MW_TEXCOMMON(2d)
    float calculate_clamped_lod(sampler s, float2 c) const { return __mw_lod_2d(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float2 c) const { return __mw_lod_2d(h, MW_SMP(s), c).y; }
    uint get_height(uint l = 0) const { return __mw_height_2d(h, l); }
    vec<T, 4> sample(sampler s, float2 c, int2 off = 0) const { return __tex_ops<T>::s2d(h, MW_SMP(s), c, 0, __mw_opt(), ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    template <class O> vec<T, 4> sample(sampler s, float2 c, O o, int2 off = 0) const { return __tex_ops<T>::s2d(h, MW_SMP(s), c, 0, __mw_opt(o), ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    vec<T, 4> read(uint2 c, uint l = 0) const { return __tex_ops<T>::r2d(h, c, 0, l); }
    vec<T, 4> read(ushort2 c, ushort l = 0) const { return __tex_ops<T>::r2d(h, ::__mw_make<uint2>(c.x, c.y), 0, l); }
    void write(vec<T, 4> v, uint2 c, uint l = 0) const { __tex_ops<T>::w2d(h, c, v, 0, l); }
    void write(vec<T, 4> v, ushort2 c, ushort l = 0) const { __tex_ops<T>::w2d(h, ::__mw_make<uint2>(c.x, c.y), v, 0, l); }
    vec<T, 4> gather(sampler s, float2 c, int2 off = 0, component k = component::x) const { return __mw_gather_2d(h, MW_SMP(s), c, 0, ::__mw_make<int4>(off.x, off.y, 0, 0), int(k)); }
};
template <class T, access A = access::sample> struct texture2d_array {
    MW_TEXCOMMON(2d_array)
    float calculate_clamped_lod(sampler s, float2 c) const { return __mw_lod_2d_array(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float2 c) const { return __mw_lod_2d_array(h, MW_SMP(s), c).y; }
    uint get_height(uint l = 0) const { return __mw_height_2d_array(h, l); }
    uint get_array_size() const { return __mw_array_2d_array(h); }
    vec<T, 4> sample(sampler s, float2 c, uint a, int2 off = 0) const { return __tex_ops<T>::s2da(h, MW_SMP(s), c, a, __mw_opt(), ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    template <class O> vec<T, 4> sample(sampler s, float2 c, uint a, O o, int2 off = 0) const { return __tex_ops<T>::s2da(h, MW_SMP(s), c, a, __mw_opt(o), ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    vec<T, 4> read(uint2 c, uint a, uint l = 0) const { return __tex_ops<T>::r2da(h, c, a, l); }
    vec<T, 4> read(ushort2 c, ushort a, ushort l = 0) const { return __tex_ops<T>::r2da(h, ::__mw_make<uint2>(c.x, c.y), a, l); }
    void write(vec<T, 4> v, uint2 c, uint a, uint l = 0) const { __tex_ops<T>::w2da(h, c, v, a, l); }
    void write(vec<T, 4> v, ushort2 c, ushort a, ushort l = 0) const { __tex_ops<T>::w2da(h, ::__mw_make<uint2>(c.x, c.y), v, a, l); }
    vec<T, 4> gather(sampler s, float2 c, uint a, int2 off = 0, component k = component::x) const { return __mw_gather_2d_array(h, MW_SMP(s), c, a, ::__mw_make<int4>(off.x, off.y, 0, 0), int(k)); }
};
template <class T, access A = access::sample> struct texture3d {
    MW_TEXCOMMON(3d)
    float calculate_clamped_lod(sampler s, float3 c) const { return __mw_lod_3d(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float3 c) const { return __mw_lod_3d(h, MW_SMP(s), c).y; }
    uint get_height(uint l = 0) const { return __mw_height_3d(h, l); }
    uint get_depth(uint l = 0) const { return __mw_depth_3d(h, l); }
    vec<T, 4> sample(sampler s, float3 c, int3 off = 0) const { return __tex_ops<T>::s3d(h, MW_SMP(s), c, 0, __mw_opt(), ::__mw_make<int4>(off.x, off.y, off.z, 0)); }
    template <class O> vec<T, 4> sample(sampler s, float3 c, O o, int3 off = 0) const { return __tex_ops<T>::s3d(h, MW_SMP(s), c, 0, __mw_opt(o), ::__mw_make<int4>(off.x, off.y, off.z, 0)); }
    vec<T, 4> read(uint3 c, uint l = 0) const { return __tex_ops<T>::r3d(h, c, 0, l); }
    void write(vec<T, 4> v, uint3 c, uint l = 0) const { __tex_ops<T>::w3d(h, c, v, 0, l); }
};
template <class T, access A = access::sample> struct texturecube {
    MW_TEXCOMMON(cube)
    float calculate_clamped_lod(sampler s, float3 c) const { return __mw_lod_cube(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float3 c) const { return __mw_lod_cube(h, MW_SMP(s), c).y; }
    uint get_height(uint l = 0) const { return __mw_height_cube(h, l); }
    vec<T, 4> sample(sampler s, float3 c) const { return __tex_ops<T>::scube(h, MW_SMP(s), c, 0, __mw_opt(), 0); }
    template <class O> vec<T, 4> sample(sampler s, float3 c, O o) const { return __tex_ops<T>::scube(h, MW_SMP(s), c, 0, __mw_opt(o), 0); }
    vec<T, 4> read(uint2 c, uint face, uint l = 0) const { return __tex_ops<T>::rcube(h, c, face, l); }
    void write(vec<T, 4> v, uint2 c, uint face, uint l = 0) const { __tex_ops<T>::wcube(h, c, v, face, l); }
};
template <class T, access A = access::sample> struct texturecube_array {
    MW_TEXCOMMON(cube_array)
    float calculate_clamped_lod(sampler s, float3 c) const { return __mw_lod_cube_array(h, MW_SMP(s), c).x; }
    float calculate_unclamped_lod(sampler s, float3 c) const { return __mw_lod_cube_array(h, MW_SMP(s), c).y; }
    uint get_height(uint l = 0) const { return __mw_height_cube_array(h, l); }
    uint get_array_size() const { return __mw_array_cube_array(h); }
    vec<T, 4> sample(sampler s, float3 c, uint a) const { return __tex_ops<T>::scubea(h, MW_SMP(s), c, a, __mw_opt(), 0); }
    template <class O> vec<T, 4> sample(sampler s, float3 c, uint a, O o) const { return __tex_ops<T>::scubea(h, MW_SMP(s), c, a, __mw_opt(o), 0); }
};
template <class T, access A = access::read> struct texture2d_ms {
    MW_TEXCOMMON(2d_ms)
    uint get_height() const { return __mw_height_2d_ms(h, 0); }
    uint get_num_samples() const { return 1; }
    vec<T, 4> read(uint2 c, uint smp) const { return __tex_ops<T>::r2dms(h, c, 0, smp); }
};
template <class T, access A = access::read> struct texture_buffer {
    __global _texture_t *h;
    uint get_width() const { return __mw_width_1d(h, 0); }
    vec<T, 4> read(uint c) const { return __tex_ops<T>::r1d(h, c, 0, 0); }
    void write(vec<T, 4> v, uint c) const { __tex_ops<T>::w1d(h, c, v, 0, 0); }
};
template <class T, access A = access::sample> struct depth2d {
    MW_TEXCOMMON(2d)
    uint get_height(uint l = 0) const { return __mw_height_2d(h, l); }
    T sample(sampler s, float2 c, int2 off = 0) const { return __tex_ops<float>::s2d(h, MW_SMP(s), c, 0, __mw_opt(), ::__mw_make<int4>(off.x, off.y, 0, 0)).x; }
    template <class O> T sample(sampler s, float2 c, O o, int2 off = 0) const { return __tex_ops<float>::s2d(h, MW_SMP(s), c, 0, __mw_opt(o), ::__mw_make<int4>(off.x, off.y, 0, 0)).x; }
    T sample_compare(sampler s, float2 c, float r, int2 off = 0) const { __mw_opt o; return __mw_samplecmp_depth_2d(h, MW_SMP(s), c, 0, r, o.mode, o.a, o.dx, o.dy, ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    template <class O> T sample_compare(sampler s, float2 c, float r, O op, int2 off = 0) const { __mw_opt o(op); return __mw_samplecmp_depth_2d(h, MW_SMP(s), c, 0, r, o.mode, o.a, o.dx, o.dy, ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    T read(uint2 c, uint l = 0) const { return __tex_ops<float>::r2d(h, c, 0, l).x; }
    vec<T, 4> gather(sampler s, float2 c, int2 off = 0) const { return __mw_gather_2d(h, MW_SMP(s), c, 0, ::__mw_make<int4>(off.x, off.y, 0, 0), 0); }
    vec<T, 4> gather_compare(sampler s, float2 c, float r, int2 off = 0) const { return __mw_gathercmp_depth_2d(h, MW_SMP(s), c, 0, r, ::__mw_make<int4>(off.x, off.y, 0, 0)); }
};
template <class T, access A = access::sample> struct depth2d_array {
    MW_TEXCOMMON(2d_array)
    uint get_height(uint l = 0) const { return __mw_height_2d_array(h, l); }
    uint get_array_size() const { return __mw_array_2d_array(h); }
    T sample(sampler s, float2 c, uint a, int2 off = 0) const { return __tex_ops<float>::s2da(h, MW_SMP(s), c, a, __mw_opt(), ::__mw_make<int4>(off.x, off.y, 0, 0)).x; }
    T sample_compare(sampler s, float2 c, uint a, float r, int2 off = 0) const { __mw_opt o; return __mw_samplecmp_depth_2d_array(h, MW_SMP(s), c, a, r, o.mode, o.a, o.dx, o.dy, ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    template <class O> T sample_compare(sampler s, float2 c, uint a, float r, O op, int2 off = 0) const { __mw_opt o(op); return __mw_samplecmp_depth_2d_array(h, MW_SMP(s), c, a, r, o.mode, o.a, o.dx, o.dy, ::__mw_make<int4>(off.x, off.y, 0, 0)); }
    T read(uint2 c, uint a, uint l = 0) const { return __tex_ops<float>::r2da(h, c, a, l).x; }
};
template <class T, access A = access::sample> struct depthcube {
    MW_TEXCOMMON(cube)
    T sample(sampler s, float3 c) const { return __tex_ops<float>::scube(h, MW_SMP(s), c, 0, __mw_opt(), 0).x; }
    T sample_compare(sampler s, float3 c, float r) const { __mw_opt o; return __mw_samplecmp_depth_cube(h, MW_SMP(s), c, 0, r, o.mode, o.a, o.dx, o.dy, 0); }
};
template <class T, access A = access::sample> struct depthcube_array {
    MW_TEXCOMMON(cube_array)
    uint get_height(uint l = 0) const { return __mw_height_cube_array(h, l); }
    uint get_array_size() const { return __mw_array_cube_array(h); }
    T sample(sampler s, float3 c, uint a) const { return __tex_ops<float>::scubea(h, MW_SMP(s), c, a, __mw_opt(), 0).x; }
};
template <class T, access A = access::read> struct texture2d_ms_array {
    MW_TEXCOMMON(2d_ms)
    uint get_height() const { return __mw_height_2d_ms(h, 0); }
    uint get_num_samples() const { return 1; }
    vec<T, 4> read(uint2 c, uint a, uint smp) const { return __tex_ops<T>::r2dms(h, c, a, smp); }
};
template <class T, access A = access::read> struct depth2d_ms {
    MW_TEXCOMMON(2d_ms)
    T read(uint2 c, uint smp) const { return __tex_ops<float>::r2dms(h, c, 0, smp).x; }
};

/* ---- barriers, atomics, SIMD-group functions */
enum class mem_flags { mem_none = 0, mem_device = 1, mem_threadgroup = 2, mem_texture = 4, mem_threadgroup_imageblock = 8, mem_object_data = 16 };
constexpr mem_flags operator|(mem_flags a, mem_flags b) { return mem_flags(int(a) | int(b)); }
void __mw_wg_barrier(int, int) __asm("air.wg.barrier");
void __mw_sg_barrier(int, int) __asm("air.simdgroup.barrier");
inline void threadgroup_barrier(mem_flags f) { __mw_wg_barrier(int(f), 1); }
inline void simdgroup_barrier(mem_flags f) { __mw_sg_barrier(int(f), 4); }
inline void atomic_thread_fence(mem_flags f, int = 0, int = 0) {}
enum memory_order { memory_order_relaxed, memory_order_consume, memory_order_acquire, memory_order_release, memory_order_acq_rel, memory_order_seq_cst };
enum thread_scope { thread_scope_thread, thread_scope_simdgroup, thread_scope_threadgroup, thread_scope_device };
template <class T> struct atomic { T __v; };
typedef atomic<int> atomic_int;
typedef atomic<uint> atomic_uint;
typedef atomic<float> atomic_float;
typedef atomic<bool> atomic_bool;
#define __MW_AS_gl "global"
#define __MW_AS_lo "local"
#define MW_AT(AS, ASN, T, K, S, op) T __mw_at_##ASN##_##op##_##K(volatile AS T *, T, int, int, bool) __asm("air.atomic." __MW_AS_##ASN "." #op "." #K "." #S);
#define MW_ATS(AS, ASN, T, K, S) MW_AT(AS, ASN, T, K, S, add) MW_AT(AS, ASN, T, K, S, sub) MW_AT(AS, ASN, T, K, S, and) MW_AT(AS, ASN, T, K, S, or) \
    MW_AT(AS, ASN, T, K, S, xor) MW_AT(AS, ASN, T, K, S, min) MW_AT(AS, ASN, T, K, S, max) MW_AT(AS, ASN, T, K, S, xchg)                     \
    T __mw_at_##ASN##_load_##K(volatile AS T *, int, int, bool) __asm("air.atomic." __MW_AS_##ASN ".load." #S);                                   \
    void __mw_at_##ASN##_store_##K(volatile AS T *, T, int, int, bool) __asm("air.atomic." __MW_AS_##ASN ".store." #S);
MW_ATS(__global, gl, int, s, i32) MW_ATS(__global, gl, uint, u, i32) MW_ATS(__local, lo, int, s, i32) MW_ATS(__local, lo, uint, u, i32)
MW_AT(__global, gl, float, f, f32, add) MW_AT(__global, gl, float, f, f32, sub) MW_AT(__global, gl, float, f, f32, xchg)
MW_AT(__local, lo, float, f, f32, add) MW_AT(__local, lo, float, f, f32, sub) MW_AT(__local, lo, float, f, f32, xchg)
float __mw_at_gl_load_f(volatile __global float *, int, int, bool) __asm("air.atomic.global.load.f32");
void __mw_at_gl_store_f(volatile __global float *, float, int, int, bool) __asm("air.atomic.global.store.f32");
float __mw_at_lo_load_f(volatile __local float *, int, int, bool) __asm("air.atomic.local.load.f32");
void __mw_at_lo_store_f(volatile __local float *, float, int, int, bool) __asm("air.atomic.local.store.f32");
template <class T> struct __mw_id { typedef T type; };
template <class T> using __mw_id_t = typename __mw_id<T>::type;
template <class T> struct __at_k;
template <> struct __at_k<int> { static constexpr char k = 's'; };
template <> struct __at_k<uint> { static constexpr char k = 'u'; };
template <> struct __at_k<float> { static constexpr char k = 'f'; };
#define MW_ATFN(op)                                                                                                                         \
    template <class T> inline T atomic_fetch_##op##_explicit(volatile __global atomic<T> *o, __mw_id_t<T> v, memory_order = memory_order_relaxed) {   \
        if constexpr (__at_k<T>::k == 's') return __mw_at_gl_##op##_s(&o->__v, v, 0, 2, true);                                       \
        else if constexpr (__at_k<T>::k == 'u') return __mw_at_gl_##op##_u(&o->__v, v, 0, 2, true);                                  \
        else return __mw_at_gl_##op##_f(&o->__v, v, 0, 2, true);                                                                       \
    }                                                                                                                                      \
    template <class T> inline T atomic_fetch_##op##_explicit(volatile __local atomic<T> *o, __mw_id_t<T> v, memory_order = memory_order_relaxed) {    \
        if constexpr (__at_k<T>::k == 's') return __mw_at_lo_##op##_s(&o->__v, v, 0, 1, true);                                        \
        else if constexpr (__at_k<T>::k == 'u') return __mw_at_lo_##op##_u(&o->__v, v, 0, 1, true);                                   \
        else return __mw_at_lo_##op##_f(&o->__v, v, 0, 1, true);                                                                        \
    }
MW_ATFN(add) MW_ATFN(sub) MW_ATFN(and) MW_ATFN(or) MW_ATFN(xor) MW_ATFN(min) MW_ATFN(max)
template <class T> inline T atomic_exchange_explicit(volatile __global atomic<T> *o, __mw_id_t<T> v, memory_order = memory_order_relaxed) {
    if constexpr (__at_k<T>::k == 's') return __mw_at_gl_xchg_s(&o->__v, v, 0, 2, true);
    else if constexpr (__at_k<T>::k == 'u') return __mw_at_gl_xchg_u(&o->__v, v, 0, 2, true);
    else return __mw_at_gl_xchg_f(&o->__v, v, 0, 2, true);
}
template <class T> inline T atomic_exchange_explicit(volatile __local atomic<T> *o, __mw_id_t<T> v, memory_order = memory_order_relaxed) {
    if constexpr (__at_k<T>::k == 's') return __mw_at_lo_xchg_s(&o->__v, v, 0, 1, true);
    else if constexpr (__at_k<T>::k == 'u') return __mw_at_lo_xchg_u(&o->__v, v, 0, 1, true);
    else return __mw_at_lo_xchg_f(&o->__v, v, 0, 1, true);
}
template <class T> inline T atomic_load_explicit(volatile __global atomic<T> *o, memory_order = memory_order_relaxed) {
    if constexpr (__at_k<T>::k == 's') return __mw_at_gl_load_s(&o->__v, 0, 2, true);
    else if constexpr (__at_k<T>::k == 'u') return __mw_at_gl_load_u(&o->__v, 0, 2, true);
    else return __mw_at_gl_load_f(&o->__v, 0, 2, true);
}
template <class T> inline T atomic_load_explicit(volatile __local atomic<T> *o, memory_order = memory_order_relaxed) {
    if constexpr (__at_k<T>::k == 's') return __mw_at_lo_load_s(&o->__v, 0, 1, true);
    else if constexpr (__at_k<T>::k == 'u') return __mw_at_lo_load_u(&o->__v, 0, 1, true);
    else return __mw_at_lo_load_f(&o->__v, 0, 1, true);
}
template <class T> inline void atomic_store_explicit(volatile __global atomic<T> *o, __mw_id_t<T> v, memory_order = memory_order_relaxed) {
    if constexpr (__at_k<T>::k == 's') __mw_at_gl_store_s(&o->__v, v, 0, 2, true);
    else if constexpr (__at_k<T>::k == 'u') __mw_at_gl_store_u(&o->__v, v, 0, 2, true);
    else __mw_at_gl_store_f(&o->__v, v, 0, 2, true);
}
template <class T> inline void atomic_store_explicit(volatile __local atomic<T> *o, __mw_id_t<T> v, memory_order = memory_order_relaxed) {
    if constexpr (__at_k<T>::k == 's') __mw_at_lo_store_s(&o->__v, v, 0, 1, true);
    else if constexpr (__at_k<T>::k == 'u') __mw_at_lo_store_u(&o->__v, v, 0, 1, true);
    else __mw_at_lo_store_f(&o->__v, v, 0, 1, true);
}
/* compare-exchange: a CAS loop on exchange is not atomic; air.atomic.*.cmpxchg (expected by pointer) */
bool __mw_at_gl_cmpxchg_u(volatile __global uint *, __private uint *, uint, int, int, int, bool) __asm("air.atomic.global.cmpxchg.weak.u.i32");
bool __mw_at_lo_cmpxchg_u(volatile __local uint *, __private uint *, uint, int, int, int, bool) __asm("air.atomic.local.cmpxchg.weak.u.i32");
template <class T> inline bool atomic_compare_exchange_weak_explicit(volatile __global atomic<T> *o, thread __mw_id_t<T> *e, __mw_id_t<T> d, memory_order = memory_order_relaxed, memory_order = memory_order_relaxed) {
    return __mw_at_gl_cmpxchg_u((volatile __global uint *)&o->__v, (__private uint *)e, as_type<uint>(d), 0, 0, 2, true);
}
template <class T> inline bool atomic_compare_exchange_weak_explicit(volatile __local atomic<T> *o, thread __mw_id_t<T> *e, __mw_id_t<T> d, memory_order = memory_order_relaxed, memory_order = memory_order_relaxed) {
    return __mw_at_lo_cmpxchg_u((volatile __local uint *)&o->__v, (__private uint *)e, as_type<uint>(d), 0, 0, 1, true);
}

#define MW_SIMD1(T, S, name) T name(T) __asm("air." #name "." #S);
#define MW_SIMDU(T, S, name) T name(T, ushort) __asm("air." #name "." #S);
#define MW_SIMD_T4(X, name, T, S) X(T, S, name) X(T##2, v2##S, name) X(T##3, v3##S, name) X(T##4, v4##S, name)
#define MW_SIMD_ALL(X, name) MW_SIMD_T4(X, name, float, f32) MW_SIMD_T4(X, name, half, f16) X(int, s.i32, name) X(int2, s.v2i32, name) X(int3, s.v3i32, name) X(int4, s.v4i32, name) \
    X(uint, u.i32, name) X(uint2, u.v2i32, name) X(uint3, u.v3i32, name) X(uint4, u.v4i32, name) X(short, s.i16, name) X(short2, s.v2i16, name) X(short4, s.v4i16, name) \
    X(ushort, u.i16, name) X(ushort2, u.v2i16, name) X(ushort4, u.v4i16, name) X(char, s.i8, name) X(uchar, u.i8, name)
MW_SIMD_ALL(MW_SIMD1, simd_sum) MW_SIMD_ALL(MW_SIMD1, simd_product) MW_SIMD_ALL(MW_SIMD1, simd_min) MW_SIMD_ALL(MW_SIMD1, simd_max)
MW_SIMD_ALL(MW_SIMD1, simd_prefix_inclusive_sum) MW_SIMD_ALL(MW_SIMD1, simd_prefix_exclusive_sum)
MW_SIMD_ALL(MW_SIMD1, simd_prefix_inclusive_product) MW_SIMD_ALL(MW_SIMD1, simd_prefix_exclusive_product)
MW_SIMD_ALL(MW_SIMDU, simd_shuffle) MW_SIMD_ALL(MW_SIMDU, simd_shuffle_down) MW_SIMD_ALL(MW_SIMDU, simd_shuffle_up) MW_SIMD_ALL(MW_SIMDU, simd_shuffle_xor)
MW_SIMD_ALL(MW_SIMDU, simd_broadcast) MW_SIMD_ALL(MW_SIMD1, simd_broadcast_first) MW_SIMD_ALL(MW_SIMD1, quad_broadcast_first)
MW_SIMD_ALL(MW_SIMDU, simd_shuffle_rotate_down) MW_SIMD_ALL(MW_SIMDU, simd_shuffle_rotate_up)
MW_SIMD_ALL(MW_SIMD1, quad_sum) MW_SIMD_ALL(MW_SIMD1, quad_min) MW_SIMD_ALL(MW_SIMD1, quad_max)
MW_SIMD_ALL(MW_SIMDU, quad_shuffle) MW_SIMD_ALL(MW_SIMDU, quad_shuffle_down) MW_SIMD_ALL(MW_SIMDU, quad_shuffle_up) MW_SIMD_ALL(MW_SIMDU, quad_shuffle_xor)
MW_SIMD_ALL(MW_SIMDU, quad_broadcast)
#define MW_SIMDB(T, S, name) T name(T) __asm("air." #name "." #S);
MW_SIMDB(int, s.i32, simd_and) MW_SIMDB(uint, u.i32, simd_and) MW_SIMDB(int, s.i32, simd_or) MW_SIMDB(uint, u.i32, simd_or) MW_SIMDB(int, s.i32, simd_xor) MW_SIMDB(uint, u.i32, simd_xor)
bool simd_any(bool) __asm("air.simd_any");
bool simd_all(bool) __asm("air.simd_all");
bool quad_any(bool) __asm("air.quad_any");
bool quad_all(bool) __asm("air.quad_all");
bool simd_is_first() __asm("air.simd_is_first");
bool quad_is_first() __asm("air.quad_is_first");
struct simd_vote { typedef ulong vote_t; ulong v; explicit simd_vote(ulong x) : v(x) {} explicit operator ulong() const { return v; } bool all() const { return v == ~0ul; } bool any() const { return v != 0; } };
ulong __mw_ballot(bool) __asm("air.simd_ballot.i64");
inline simd_vote simd_ballot(bool b) { return simd_vote(__mw_ballot(b)); }
ulong __mw_active() __asm("air.simd_active_threads_mask.i64");
inline simd_vote simd_active_threads_mask() { return simd_vote(__mw_active()); }
ushort __mw_qballot(bool) __asm("air.quad_ballot.i16");

/* ---- fragment */
void discard_fragment() __asm("air.discard_fragment");
bool simd_is_helper_thread() __asm("air.simd_is_helper_thread");
template <class T> inline bool is_function_constant_defined(T) { return true; }
#define is_function_constant_defined(x) true

template <class T, size_t N> struct array {
    T __e[N ? N : 1];
    T &operator[](size_t i) { return __e[i]; }
    const T &operator[](size_t i) const { return __e[i]; }
    constexpr size_t size() const { return N; }
};
} // namespace metal

/* <simd/simd.h> names used by headers shared between the app and its shaders */
typedef metal::float2 vector_float2, simd_float2; typedef metal::float3 vector_float3, simd_float3; typedef metal::float4 vector_float4, simd_float4;
typedef metal::half2 vector_half2, simd_half2; typedef metal::half3 vector_half3, simd_half3; typedef metal::half4 vector_half4, simd_half4;
typedef metal::int2 vector_int2, simd_int2; typedef metal::int3 vector_int3, simd_int3; typedef metal::int4 vector_int4, simd_int4;
typedef metal::uint2 vector_uint2, simd_uint2; typedef metal::uint3 vector_uint3, simd_uint3; typedef metal::uint4 vector_uint4, simd_uint4;
typedef metal::float2x2 matrix_float2x2, simd_float2x2; typedef metal::float3x3 matrix_float3x3, simd_float3x3; typedef metal::float4x4 matrix_float4x4, simd_float4x4;
typedef metal::float4x3 matrix_float4x3, simd_float4x3; typedef metal::float3x4 matrix_float3x4, simd_float3x4;
