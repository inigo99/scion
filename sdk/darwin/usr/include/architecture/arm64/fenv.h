/* Scion SDK: floating-point environment of arm64 (FPCR/FPSR), as declared by macOS on Apple silicon. */
#ifndef _SCION_ARM64_FENV_H_
#define _SCION_ARM64_FENV_H_

typedef struct {
    unsigned long long __fpsr;
    unsigned long long __fpcr;
} fenv_t;
typedef unsigned short fexcept_t;

#define FE_INVALID 0x0001
#define FE_DIVBYZERO 0x0002
#define FE_OVERFLOW 0x0004
#define FE_UNDERFLOW 0x0008
#define FE_INEXACT 0x0010
#define FE_ALL_EXCEPT 0x001F

#define FE_TONEAREST 0x00000000
#define FE_UPWARD 0x00400000
#define FE_DOWNWARD 0x00800000
#define FE_TOWARDZERO 0x00C00000

#ifdef __cplusplus
extern "C" {
#endif
extern const fenv_t _FE_DFL_ENV;
#define FE_DFL_ENV (&_FE_DFL_ENV)

int feclearexcept(int);
int fegetexceptflag(fexcept_t *, int);
int feraiseexcept(int);
int fesetexceptflag(const fexcept_t *, int);
int fetestexcept(int);
int fegetround(void);
int fesetround(int);
int fegetenv(fenv_t *);
int feholdexcept(fenv_t *);
int fesetenv(const fenv_t *);
int feupdateenv(const fenv_t *);
#ifdef __cplusplus
}
#endif

#endif
