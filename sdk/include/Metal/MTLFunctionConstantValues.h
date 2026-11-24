/* scion: Metal function constants (MTLDataType subset, MTLFunctionConstantValues, MTLFunctionConstant) */
#ifndef _METAL_MTLFUNCTIONCONSTANTVALUES_H_
#define _METAL_MTLFUNCTIONCONSTANTVALUES_H_
#import <Foundation/Foundation.h>
#import <Metal/MTLDefines.h>

typedef NS_ENUM(NSUInteger, MTLDataType) {
    MTLDataTypeNone = 0, MTLDataTypeStruct = 1, MTLDataTypeArray = 2,
    MTLDataTypeFloat = 3, MTLDataTypeFloat2 = 4, MTLDataTypeFloat3 = 5, MTLDataTypeFloat4 = 6,
    MTLDataTypeHalf = 16, MTLDataTypeHalf2 = 17, MTLDataTypeHalf3 = 18, MTLDataTypeHalf4 = 19,
    MTLDataTypeInt = 29, MTLDataTypeInt2 = 30, MTLDataTypeInt3 = 31, MTLDataTypeInt4 = 32,
    MTLDataTypeUInt = 33, MTLDataTypeUInt2 = 34, MTLDataTypeUInt3 = 35, MTLDataTypeUInt4 = 36,
    MTLDataTypeShort = 37, MTLDataTypeUShort = 41, MTLDataTypeChar = 45, MTLDataTypeUChar = 49,
    MTLDataTypeBool = 53, MTLDataTypeBool2 = 54, MTLDataTypeBool3 = 55, MTLDataTypeBool4 = 56,
    MTLDataTypeTexture = 58, MTLDataTypeSampler = 59, MTLDataTypePointer = 60,
    MTLDataTypeLong = 81, MTLDataTypeULong = 85, MTLDataTypeBFloat = 121,
};

@interface MTLFunctionConstantValues : NSObject <NSCopying>
- (void)setConstantValue:(const void *)value type:(MTLDataType)type atIndex:(NSUInteger)index;
- (void)setConstantValues:(const void *)values type:(MTLDataType)type withRange:(NSRange)range;
- (void)setConstantValue:(const void *)value type:(MTLDataType)type withName:(NSString *)name;
- (void)reset;
@end

@interface MTLFunctionConstant : NSObject
@property(readonly) NSString *name;
@property(readonly) MTLDataType type;
@property(readonly) NSUInteger index;
@property(readonly) BOOL required;
@end
#endif
