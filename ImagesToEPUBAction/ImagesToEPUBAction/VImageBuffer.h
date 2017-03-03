//
//  VImageBuffer.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/22/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import Foundation;

@class NSColor;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const VImageErrorDomain;
FOUNDATION_EXTERN NSUInteger const kMaxTheta;

@interface VImageBuffer : NSObject

@property (readonly, nonatomic) void *data NS_RETURNS_INNER_POINTER;
@property (readonly, nonatomic) NSUInteger width, height, bytesPerRow;

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithImage:(CGImageRef)image backgroundColor:(nullable NSColor *)backgroundColor error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (nullable VImageBuffer *)maximizeWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error;
- (nullable VImageBuffer *)minimizeWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error;

- (BOOL)detectEdgesWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error;
- (nullable VImageBuffer *)houghTransformWithMargin:(NSUInteger)margin error:(NSError **)error;

- (nullable VImageBuffer *)normalizeContrast:(NSError **)error;
- (nullable CGImageRef)copyCGImage:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
