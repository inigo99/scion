/* scion: ImageIO subset: writing a CGImage to a file (PNG, JPEG, BMP, TIFF, GIF; encoded by the host). In AppKit.dylib. */
#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <MacTypes.h>
typedef struct CGImageDestination *CGImageDestinationRef;
CGImageDestinationRef CGImageDestinationCreateWithURL(CFURLRef url, CFStringRef type, size_t count, CFDictionaryRef options);
void CGImageDestinationAddImage(CGImageDestinationRef d, CGImageRef image, CFDictionaryRef properties);
bool CGImageDestinationFinalize(CGImageDestinationRef d);
