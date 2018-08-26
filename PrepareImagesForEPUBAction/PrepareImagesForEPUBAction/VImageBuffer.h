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

- (instancetype)init NS_UNAVAILABLE;

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height bitsPerPixel:(NSUInteger)bitsPerPixel error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCGImage:(CGImageRef)image error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error;

+ (nullable instancetype)bufferWithWidth:(NSUInteger)width height:(NSUInteger)height bitsPerPixel:(NSUInteger)bitsPerPixel error:(NSError **)error;
+ (nullable instancetype)bufferWithContentsOfURL:(NSURL *)url error:(NSError **)error;

- (nullable VImageBuffer *)dilateWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error NS_SWIFT_NAME(dilate(width:height:));
- (nullable VImageBuffer *)erodeWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error NS_SWIFT_NAME(erode(width:height:));

- (nullable VImageBuffer *)openWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error NS_SWIFT_NAME(open(width:height:));

- (BOOL)subtractBuffer:(VImageBuffer *)subtrahend error:(NSError **)error;

- (nullable VImageBuffer *)extractBorderMaskInRect:(CGRect)rect error:(NSError **)error;

- (BOOL)detectEdgesAndReturnError:(NSError **)error;
- (nullable NSArray<NSArray<NSNumber *> *> *)detectSegmentsWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;
- (nullable NSArray<NSArray<NSNumber *> *> *)detectPolylinesWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;
- (nullable NSArray<NSArray<NSNumber *> *> *)detectRegionsWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;

- (nullable CGImageRef)newGrayscaleImageFromBufferAndReturnError:(NSError **)error CF_RETURNS_RETAINED;

@end

NS_ASSUME_NONNULL_END
