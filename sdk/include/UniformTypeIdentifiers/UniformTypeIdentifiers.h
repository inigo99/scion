/* scion: UniformTypeIdentifiers subset (the image types). In AppKit.dylib. */
#pragma once
#import <Foundation/Foundation.h>
@interface UTType : NSObject <NSCopying>
+ (instancetype)typeWithIdentifier:(NSString *)identifier;
+ (instancetype)typeWithFilenameExtension:(NSString *)extension;
@property(readonly) NSString *identifier;
@property(readonly) NSString *preferredFilenameExtension;
@end
extern UTType *UTTypePNG, *UTTypeJPEG, *UTTypeTIFF, *UTTypeGIF, *UTTypeBMP, *UTTypeImage, *UTTypeData; /* set when AppKit loads */
