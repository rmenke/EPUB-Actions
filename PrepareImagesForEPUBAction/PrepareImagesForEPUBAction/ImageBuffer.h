//
//  ImageBuffer.h
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 12/13/20.
//  Copyright © 2020 Rob Menke. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/NSColor.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXTERN NSErrorDomain const VImageErrorDomain;

typedef NSString *HoughParameterKey NS_STRING_ENUM;

FOUNDATION_EXTERN HoughParameterKey const HoughMaxTheta;
FOUNDATION_EXTERN HoughParameterKey const HoughMinTriggerPoints;
FOUNDATION_EXTERN HoughParameterKey const HoughThreshold;
FOUNDATION_EXTERN HoughParameterKey const HoughChannelWidth;
FOUNDATION_EXTERN HoughParameterKey const HoughMaxGap;
FOUNDATION_EXTERN HoughParameterKey const HoughMinLength;

NS_REQUIRES_PROPERTY_DEFINITIONS
@interface ImageBuffer : NSObject

@property (nonatomic, readonly) NSUInteger width, height;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER;

- (BOOL)flattenAgainstColor:(NSColor *)color error:(NSError **)error;

- (BOOL)autoAlphaAndReturnError:(NSError **)error;
- (BOOL)autoAlphaInROI:(NSRect)ROI error:(NSError **)error;

- (BOOL)convertToLabColorSpaceAndReturnError:(NSError **)error;
- (BOOL)convertToRGBColorSpaceAndReturnError:(NSError **)error;

- (nullable ImageBuffer *)extractAlphaChannelAndReturnError:(NSError **)error;

- (nullable ImageBuffer *)bufferByDilatingWithKernelSize:(NSSize)kernelSize error:(NSError **)error;
- (nullable ImageBuffer *)bufferByErodingWithKernelSize:(NSSize)kernelSize error:(NSError **)error;

- (nullable ImageBuffer *)bufferBySubtractingBuffer:(ImageBuffer *)subtrahand error:(NSError **)error;

- (nullable NSArray<NSArray<NSNumber *> *> *)segmentsFromBufferWithParameters:(nullable NSDictionary<HoughParameterKey, id> *)parameters error:(NSError **)error;
- (nullable NSArray<NSArray<NSNumber *> *> *)regionsFromBufferWithParameters:(nullable NSDictionary<HoughParameterKey, id> *)parameters error:(NSError **)error;

- (nullable CGImageRef)CGImageAndReturnError:(NSError **)error CF_RETURNS_RETAINED;

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
