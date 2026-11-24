/* scion SDK — MTLCompileOptions */
#ifndef _METAL_MTLCOMPILEOPTIONS_H_
#define _METAL_MTLCOMPILEOPTIONS_H_
#import <Foundation/Foundation.h>
typedef NS_ENUM(NSUInteger, MTLLanguageVersion) {
    MTLLanguageVersion1_1 = (1 << 16) + 1, MTLLanguageVersion1_2 = (1 << 16) + 2, MTLLanguageVersion2_0 = 2 << 16,
    MTLLanguageVersion2_1 = (2 << 16) + 1, MTLLanguageVersion2_2 = (2 << 16) + 2, MTLLanguageVersion2_3 = (2 << 16) + 3,
    MTLLanguageVersion2_4 = (2 << 16) + 4, MTLLanguageVersion3_0 = 3 << 16, MTLLanguageVersion3_1 = (3 << 16) + 1,
    MTLLanguageVersion3_2 = (3 << 16) + 2, MTLLanguageVersion4_0 = 4 << 16,
};
typedef NS_ENUM(NSInteger, MTLMathMode) { MTLMathModeSafe = 0, MTLMathModeRelaxed = 1, MTLMathModeFast = 2 };
typedef NS_ENUM(NSInteger, MTLMathFloatingPointFunctions) { MTLMathFloatingPointFunctionsFast = 0, MTLMathFloatingPointFunctionsPrecise = 1 };
@interface MTLCompileOptions : NSObject <NSCopying>
@property (assign, nonatomic) MTLMathMode mathMode;
@property (assign, nonatomic) MTLMathFloatingPointFunctions mathFloatingPointFunctions;
@property (copy, nonatomic) NSDictionary *preprocessorMacros;
@property (assign, nonatomic) BOOL fastMathEnabled, preserveInvariance;
@property (assign, nonatomic) MTLLanguageVersion languageVersion;
@end
#endif
