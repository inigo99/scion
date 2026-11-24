/* scion SDK: the Blocks runtime API (implemented in libSystem) */
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void *_Block_copy(const void *aBlock);
void _Block_release(const void *aBlock);
void _Block_object_assign(void *dst, const void *src, const int flags);
void _Block_object_dispose(const void *object, const int flags);
extern void *_NSConcreteStackBlock[32];
extern void *_NSConcreteGlobalBlock[32];
#ifdef __cplusplus
}
#endif
#define Block_copy(...) ((__typeof(__VA_ARGS__))_Block_copy((const void *)(__VA_ARGS__)))
#define Block_release(...) _Block_release((const void *)(__VA_ARGS__))
