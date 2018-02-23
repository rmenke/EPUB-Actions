//
//  VImageBuffer.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/22/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import Foundation;
@import CoreImage;

@class NSColor;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSString * const VImageErrorDomain;
FOUNDATION_EXTERN NSUInteger const kMaxTheta;

@interface VImageBuffer : NSObject<NSCopying>

@property (readonly, nonatomic) void *data NS_RETURNS_INNER_POINTER;
@property (readonly, nonatomic) NSUInteger width, height, bytesPerRow;

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCIImage:(CIImage *)image error:(NSError **)error;

- (nullable NSArray<NSArray<NSNumber *> *> *)findSegmentsWithParameters:(NSDictionary *)paramenters error:(NSError **)error;
- (nullable NSArray<NSValue *> *)findRegionsAndReturnError:(NSError **)error;

- (nullable VImageBuffer *)normalizeContrastAndReturnError:(NSError **)error;
- (nullable CGImageRef)copyCGImageAndReturnError:(NSError **)error CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
