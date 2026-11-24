/* scion SDK (clean-room): Objective-C basic types, as <objc/objc.h> declares them (usable from C and C++ too). */
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <objc/objc-api.h>
typedef struct objc_class *Class;
struct objc_object { Class isa; };
typedef struct objc_object *id;
typedef struct objc_selector *SEL;
/* the old prototype (OBJC_OLD_DISPATCH_PROTOTYPES=1): scion's own code calls IMPs directly */
typedef id _Nullable (*IMP)(id _Nonnull, SEL _Nonnull, ...);
#if defined(__OBJC_BOOL_IS_BOOL) && __OBJC_BOOL_IS_BOOL
typedef bool BOOL;
#else
typedef signed char BOOL;
#endif
#define OBJC_BOOL_DEFINED
#define YES ((BOOL)1)
#define NO ((BOOL)0)
#ifndef Nil
#  if __has_feature(cxx_nullptr)
#    define Nil nullptr
#  else
#    define Nil ((void *)0)
#  endif
#endif
#ifndef nil
#  if __has_feature(cxx_nullptr)
#    define nil nullptr
#  else
#    define nil ((void *)0)
#  endif
#endif
#ifndef __strong
#  if !__has_feature(objc_arc)
#    define __strong
#  endif
#endif
#ifndef __unsafe_unretained
#  if !__has_feature(objc_arc)
#    define __unsafe_unretained
#  endif
#endif
#ifndef __autoreleasing
#  if !__has_feature(objc_arc)
#    define __autoreleasing
#  endif
#endif
typedef unsigned long NSUInteger;
typedef long NSInteger;
typedef void *objc_objectptr_t;
OBJC_EXPORT const char * _Nonnull sel_getName(SEL _Nonnull sel);
OBJC_EXPORT SEL _Nonnull sel_registerName(const char * _Nonnull str);
OBJC_EXPORT const char * _Nonnull object_getClassName(id _Nullable obj);
OBJC_EXPORT void * _Nullable object_getIndexedIvars(id _Nullable obj);
OBJC_EXPORT BOOL sel_isMapped(SEL _Nonnull sel);
OBJC_EXPORT SEL _Nonnull sel_getUid(const char * _Nonnull str);
