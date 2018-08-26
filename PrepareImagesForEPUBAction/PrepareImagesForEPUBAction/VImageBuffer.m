//
//  VImageBuffer.m
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/16/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#import "VImageBuffer.h"
#import "AnalysisTools.h"

#include <inttypes.h>

@import CoreImage;
@import Accelerate.vImage;
@import simd;

@import AppKit.NSColor;
@import AppKit.NSColorSpace;

NS_ASSUME_NONNULL_BEGIN

NSString * const VImageErrorDomain = @"VImageErrorDomain";

@implementation VImageBuffer {
    vImage_Buffer buffer;
}

@dynamic width, height;

+ (void)initialize {
    [NSError setUserInfoValueProviderForDomain:VImageErrorDomain provider:^id(NSError *err, NSString *userInfoKey) {
        if ([NSLocalizedFailureReasonErrorKey isEqualToString:userInfoKey]) {
            switch (err.code) {
                case kvImageNoError:
                    return @"No error";
                case kvImageRoiLargerThanInputBuffer:
                    return @"ROI larger than input buffer";
                case kvImageInvalidKernelSize:
                    return @"Invalid kernel size";
                case kvImageInvalidEdgeStyle:
                    return @"Invalid edge style";
                case kvImageInvalidOffset_X:
                    return @"Invalid offset x";
                case kvImageInvalidOffset_Y:
                    return @"Invalid offset y";
                case kvImageMemoryAllocationError:
                    return @"Memory allocation error";
                case kvImageNullPointerArgument:
                    return @"Null pointer argument";
                case kvImageInvalidParameter:
                    return @"Invalid parameter";
                case kvImageBufferSizeMismatch:
                    return @"Buffer size mismatch";
                case kvImageUnknownFlagsBit:
                    return @"Unknown flags bit";
                case kvImageInternalError:
                    return @"Internal error";
                case kvImageInvalidRowBytes:
                    return @"Invalid row bytes";
                case kvImageInvalidImageFormat:
                    return @"Invalid image format";
                case kvImageColorSyncIsAbsent:
                    return @"Color sync is absent";
                case kvImageOutOfPlaceOperationRequired:
                    return @"Out of place operation required";
                case kvImageInvalidImageObject:
                    return @"Invalid image object";
                case kvImageInvalidCVImageFormat:
                    return @"Invalid cvimage format";
                case kvImageUnsupportedConversion:
                    return @"Unsupported conversion";
                case kvImageCoreVideoIsAbsent:
                    return @"Core video is absent";
            }
        }

        return nil;
    }];
}

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height bitsPerPixel:(NSUInteger)bitsPerPixel error:(NSError **)error {
    self = [super init];

    if (self) {
        vImage_Error errc = vImageBuffer_Init(&buffer, height, width, (uint32_t)bitsPerPixel, kvImageNoFlags);

        if (errc != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:errc userInfo:nil];
            return nil;
        }
    }

    return self;
}

+ (nullable instancetype)bufferWithWidth:(NSUInteger)width height:(NSUInteger)height bitsPerPixel:(NSUInteger)bitsPerPixel error:(NSError **)error {
    return [[VImageBuffer alloc] initWithWidth:width height:height bitsPerPixel:bitsPerPixel error:error];
}

- (nullable instancetype)initWithCGImage:(CGImageRef)image error:(NSError **)error {
    self = [super init];

    if (self) {
        vImage_CGImageFormat format = {
            .bitsPerComponent = 32, .bitsPerPixel = 128,
            .colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericXYZ),
            .bitmapInfo = kCGBitmapByteOrder32Host | kCGBitmapFloatComponents | kCGImageAlphaLast,
            .version = 0, .decode = NULL, .renderingIntent = kCGRenderingIntentDefault
        };

        NSAssert(format.colorSpace != NULL, @"Unable to create XYZ color space");

        vImage_Error errc = vImageBuffer_InitWithCGImage(&buffer, &format, NULL, image, kvImageNoFlags);

        CGColorSpaceRelease(format.colorSpace);

        if (errc != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:errc userInfo:nil];
            return nil;
        }
    }

    return self;
}

- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);

    if (source == NULL) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidImageObject userInfo:@{NSURLErrorKey:url, NSLocalizedFailureReasonErrorKey:@"Unable to create image source."}];
        return nil;
    }

    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);

    if (image == NULL) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidImageObject userInfo:@{NSURLErrorKey:url, NSLocalizedFailureReasonErrorKey:@"Unable to create image."}];
        return nil;
    }

    self = [self initWithCGImage:image error:error];

    CGImageRelease(image);

    return self;
}

+ (nullable instancetype)bufferWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    return [[VImageBuffer alloc] initWithContentsOfURL:url error:error];
}

- (void)dealloc {
    free(buffer.data);
}

- (NSUInteger)width {
    return buffer.width;
}

- (NSUInteger)height {
    return buffer.height;
}

- (nullable VImageBuffer *)dilateWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    VImageBuffer *result = [VImageBuffer bufferWithWidth:buffer.width height:buffer.height bitsPerPixel:8 error:error];

    if (result) {
        vImage_Error errc = vImageMax_Planar8(&buffer, &(result->buffer), NULL, 0, 0, height, width, kvImageNoFlags);

        if (errc != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:errc userInfo:nil];
            return nil;
        }
    }

    return result;
}

- (nullable VImageBuffer *)erodeWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    VImageBuffer *result = [VImageBuffer bufferWithWidth:buffer.width height:buffer.height bitsPerPixel:8 error:error];

    if (result) {
        vImage_Error errc = vImageMin_Planar8(&buffer, &(result->buffer), NULL, 0, 0, height, width, kvImageNoFlags);

        if (errc != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:errc userInfo:nil];
            return nil;
        }
    }

    return result;
}

- (nullable VImageBuffer *)openWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    return [[self dilateWithWidth:width height:height error:error] erodeWithWidth:width height:height error:error];
}

- (BOOL)detectEdgesAndReturnError:(NSError **)error {
    VImageBuffer *erosion = [self erodeWithWidth:3 height:3 error:error];
    return erosion ? [self subtractBuffer:erosion error:error] : NO;
}

- (BOOL)subtractBuffer:(VImageBuffer *)subtrahend error:(NSError **)error {
    if (buffer.width != subtrahend->buffer.width || buffer.height != subtrahend->buffer.height) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageBufferSizeMismatch userInfo:nil];
        return NO;
    }

    dispatch_apply(buffer.height, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t y) {
              vector_uchar16 * a = buffer.data + buffer.rowBytes * y;
        const vector_uchar16 * b = subtrahend->buffer.data + subtrahend->buffer.rowBytes * y;
        const vector_uchar16 * const end = b + (buffer.width + 15) / 16;

        do *a -= *b; while (++a, ++b < end);
    });

    return YES;
}

- (nullable VImageBuffer *)extractBorderMaskInRect:(CGRect)rect error:(NSError **)error {
    VImageBuffer *result = [VImageBuffer bufferWithWidth:buffer.width height:buffer.height bitsPerPixel:8 error:error];
    if (!result) return nil;

    extractBorder(&buffer, &(result->buffer), CGRectIntegral(rect));

    return result;
}

- (nullable NSArray<NSArray<NSNumber *> *> *)detectSegmentsWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    if (error) {
        NSArray<NSArray<NSNumber *> *> *result;

        CFErrorRef cfError;
        result = CFBridgingRelease(detectSegments(&buffer, (__bridge CFDictionaryRef)(options), &cfError));
        if (!result) *error = CFBridgingRelease(cfError);
        return result;
    }
    else {
        return CFBridgingRelease(detectSegments(&buffer, (__bridge CFDictionaryRef)(options), NULL));
    }
}

- (nullable NSArray<NSArray<NSNumber *> *> *)detectPolylinesWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    if (error) {
        CFErrorRef cfError;
        NSArray<NSArray<NSNumber *> *> *result = CFBridgingRelease(detectPolylines(&buffer, (__bridge CFDictionaryRef)(options), &cfError));
        if (!result) *error = CFBridgingRelease(cfError);
        return result;
    }
    else {
        return CFBridgingRelease(detectPolylines(&buffer, (__bridge CFDictionaryRef)(options), NULL));
    }
}

- (nullable NSArray<NSArray<NSNumber *> *> *)detectRegionsWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    if (error) {
        CFErrorRef cfError;
        NSArray<NSArray<NSNumber *> *> *result = CFBridgingRelease(detectRegions(&buffer, (__bridge CFDictionaryRef)(options), &cfError));
        if (!result) *error = CFBridgingRelease(cfError);
        return result;
    }
    else {
        return CFBridgingRelease(detectRegions(&buffer, (__bridge CFDictionaryRef)(options), NULL));
    }
}

- (nullable CGImageRef)newGrayscaleImageFromBufferAndReturnError:(NSError **)error {
    static vImage_CGImageFormat format = {
        .bitsPerComponent = 8, .bitsPerPixel = 8,
        .bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrderDefault,
        .version = 0, .decode = NULL, .renderingIntent = kCGRenderingIntentDefault
    };

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        format.colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
    });

    vImage_Error errc;

    CGImageRef image = vImageCreateCGImageFromBuffer(&buffer, &format, NULL, NULL, kvImageNoFlags, &errc);

    if (image == NULL) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:errc userInfo:nil];
    }

    return image;
}

- (void *)row:(NSUInteger)row {
    return buffer.data + buffer.rowBytes * row;
}

@end

NS_ASSUME_NONNULL_END
