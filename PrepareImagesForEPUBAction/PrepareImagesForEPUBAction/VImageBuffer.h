//
//  VImageBuffer.h
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/16/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface VImageBuffer : NSObject

@property (nonatomic, readonly) NSUInteger width, height;
@property (nonatomic, readonly) CGRect ROI;

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height bitsPerPixel:(NSUInteger)bitsPerPixel error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCGImage:(CGImageRef)image error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error;

+ (nullable instancetype)bufferWithWidth:(NSUInteger)width height:(NSUInteger)height bitsPerPixel:(NSUInteger)bitsPerPixel error:(NSError **)error;
+ (nullable instancetype)bufferWithContentsOfURL:(NSURL *)url error:(NSError **)error;

- (void)cropTop:(NSUInteger)top bottom:(NSUInteger)bottom left:(NSUInteger)left right:(NSUInteger)right NS_SWIFT_NAME(crop(top:bottom:left:right:));

- (nullable VImageBuffer *)extractBorderMaskAndReturnError:(NSError **)error;

- (BOOL)detectEdgesAndReturnError:(NSError **)error;
- (nullable NSArray<NSArray<NSNumber *> *> *)detectSegmentsAndReturnError:(NSError **)error;

- (nullable CGImageRef)newGrayscaleImageFromBufferAndReturnError:(NSError **)error CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
