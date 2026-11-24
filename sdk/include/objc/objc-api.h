/* scion SDK: Objective-C runtime export and availability macros */
#pragma once
#if __has_include(<Availability.h>)
#include <Availability.h>
#endif
#ifdef __cplusplus
#  define OBJC_EXTERN extern "C"
#else
#  define OBJC_EXTERN extern
#endif
#define OBJC_VISIBLE __attribute__((visibility("default")))
#define OBJC_EXPORT OBJC_EXTERN OBJC_VISIBLE
#define OBJC_IMPORT extern
#define OBJC_ROOT_CLASS __attribute__((objc_root_class))
#define OBJC_AVAILABLE(x, i, t, w, b)
#define OBJC_OSX_AVAILABLE_OTHERS_UNAVAILABLE(vers)
#define OBJC_OSX_DEPRECATED_OTHERS_UNAVAILABLE(_start, _dep)
#define OBJC_IOS_UNAVAILABLE
#define OBJC_ARC_UNAVAILABLE
#define OBJC_SWIFT_UNAVAILABLE(_msg)
#define OBJC_UNAVAILABLE(_msg)
#define OBJC_DEPRECATED(_msg)
#define OBJC_GC_UNAVAILABLE
#define UNAVAILABLE_ATTRIBUTE __attribute__((unavailable))
#define OBJC_INLINE __inline
#define OBJC_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define OBJC_OPTIONS(_type, _name) enum _name : _type _name; enum _name : _type
#ifndef OBJC_RETURNS_RETAINED
#  if __OBJC__ && __has_attribute(ns_returns_retained)
#    define OBJC_RETURNS_RETAINED __attribute__((ns_returns_retained))
#  else
#    define OBJC_RETURNS_RETAINED
#  endif
#endif
#define OBJC_NOESCAPE __attribute__((noescape))
#define OBJC_NONLAZY_CLASS
#define OBJC_OLD_DISPATCH_PROTOTYPES 1
