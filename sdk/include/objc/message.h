/* scion SDK (clean-room): <objc/message.h> */
#pragma once
#include <objc/objc.h>
#include <objc/runtime.h>
struct objc_super { __unsafe_unretained _Nonnull id receiver; __unsafe_unretained _Nonnull Class super_class; };
#ifdef __cplusplus
extern "C" {
#endif
OBJC_EXPORT id _Nullable objc_msgSend(id _Nullable self, SEL _Nonnull op, ...);
OBJC_EXPORT id _Nullable objc_msgSendSuper(struct objc_super * _Nonnull super, SEL _Nonnull op, ...);
OBJC_EXPORT id _Nullable objc_msgSendSuper2(struct objc_super * _Nonnull super, SEL _Nonnull op, ...);
#if defined(__x86_64__)
OBJC_EXPORT void objc_msgSend_stret(void);
OBJC_EXPORT void objc_msgSendSuper_stret(void);
OBJC_EXPORT long double objc_msgSend_fpret(id _Nullable self, SEL _Nonnull op, ...);
OBJC_EXPORT void objc_msgSend_fp2ret(void);
#endif
OBJC_EXPORT id _Nullable method_invoke(id _Nullable receiver, Method _Nonnull m, ...);
OBJC_EXPORT void _objc_msgForward(void);
#ifdef __cplusplus
}
#endif
