//
//  VImageBuffer.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/22/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "VImageBuffer.h"

@import AppKit.NSColor;
@import AppKit.NSColorSpace;
@import Accelerate.vImage;
@import simd;
@import Darwin.C.tgmath;

#if CGFLOAT_IS_DOUBLE
typedef vector_double2 vector_cgfloat2;
#else
typedef vector_float2 vector_cgfloat2;
#endif

_Static_assert(sizeof(vector_float4) == 16, "size incorrect");
_Static_assert(sizeof(vector_int4) == 16, "size incorrect");
_Static_assert(sizeof(vector_cgfloat2) == sizeof(NSPoint), "Incorrect sizing");

NS_ASSUME_NONNULL_BEGIN

NSString * const VImageErrorDomain = @"VImageErrorDomain";

#define TRY(...) \
    vImage_Error code = (__VA_ARGS__); \
    if (code != kvImageNoError) { \
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil]; \
        return NO; \
    } \
    return YES;

FOUNDATION_STATIC_INLINE
BOOL InitBuffer(vImage_Buffer *buf, NSUInteger height, NSUInteger width, NSError **error) {
    TRY(vImageBuffer_Init(buf, height, width, 32, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL InitWithCGImage(vImage_Buffer *buf, vImage_CGImageFormat *format, const CGFloat * _Nullable bgColor, CGImageRef image, NSError **error) {
    TRY(vImageBuffer_InitWithCGImage(buf, format, bgColor, image, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL MaxPlanarF(const vImage_Buffer *src, const vImage_Buffer *dst, NSUInteger xOffset, NSUInteger yOffset, NSUInteger ksize, NSError **error) {
    TRY(vImageMax_PlanarF(src, dst, NULL, xOffset, yOffset, ksize, ksize, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL MinPlanarF(const vImage_Buffer *src, const vImage_Buffer *dst, NSUInteger xOffset, NSUInteger yOffset, NSUInteger ksize, NSError **error) {
    TRY(vImageMin_PlanarF(src, dst, NULL, xOffset, yOffset, ksize, ksize, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
_Nullable CGImageRef CreateCGImageFromBuffer(vImage_Buffer *buffer, vImage_CGImageFormat *format, NSError **error) {
    vImage_Error code;

    CGImageRef image = vImageCreateCGImageFromBuffer(buffer, format, NULL, NULL, kvImageNoFlags, &code);
    if (image) return image;

    if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
    return NULL;
}

FOUNDATION_STATIC_INLINE
BOOL ContrastStretch(const vImage_Buffer *src, const vImage_Buffer *dest, unsigned int histogramEntries, NSError **error) {
    TRY(vImageContrastStretch_PlanarF(src, dest, NULL, histogramEntries, 0.0f, 1.0f, kvImageNoFlags));
}

const NSUInteger kMaxTheta = 1024;
const CGFloat kRScale = 2.0;
const CGFloat kGrayscaleThreshold = 0.5;
const NSUInteger kAngleLimit = 128;

static CGFloat Sine[kMaxTheta], Cosine[kMaxTheta];

@implementation VImageBuffer {
    vImage_Buffer buffer;
}

+ (void)initialize {
    for (NSUInteger theta = 0; theta < kMaxTheta; ++theta) {
        CGFloat semiturns = (CGFloat)(theta) / (CGFloat)(kMaxTheta / 2);
        Sine[theta] = __sinpi(semiturns), Cosine[theta] = __cospi(semiturns);
    }

    [NSError setUserInfoValueProviderForDomain:VImageErrorDomain provider:^id(NSError *err, NSString *userInfoKey) {
        if ([NSLocalizedDescriptionKey isEqualToString:userInfoKey]) {
            switch (err.code) {
                case kvImageNoError:
                    return @"No error";
                case kvImageRoiLargerThanInputBuffer:
                    return @"Roi larger than input buffer";
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

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    self = [super init];

    if (self) {
        if (!InitBuffer(&buffer, height, width, error)) return nil;
    }

    return self;
}

- (nullable instancetype)initWithImage:(CGImageRef)image backgroundColor:(nullable NSColor *)backgroundColor error:(NSError **)error {
    self = [super init];

    if (self) {
        NS_VALID_UNTIL_END_OF_SCOPE NSColorSpace *grayColorSpace = [NSColorSpace genericGrayColorSpace];

        backgroundColor = [backgroundColor colorUsingColorSpace:[[NSColorSpace alloc] initWithCGColorSpace:CGImageGetColorSpace(image)]];

        CGFloat backgroundPixels[4] = { 0, 0, 0, 0 };
        if (backgroundColor && backgroundColor.numberOfComponents <= 4) {
            [backgroundColor getComponents:backgroundPixels];
        }

        vImage_CGImageFormat format = {
            32, 32, grayColorSpace.CGColorSpace, kCGBitmapByteOrder32Host | kCGBitmapFloatComponents, 0, NULL, kCGRenderingIntentDefault
        };

        if (!InitWithCGImage(&buffer, &format, backgroundColor ? backgroundPixels : NULL, image, error)) return nil;
    }

    return self;
}

- (nullable VImageBuffer *)maximizeWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    if ((kernelSize & 1) == 0) { // vImage does not check
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidKernelSize userInfo:nil];
        return nil;
    }

    VImageBuffer *maximaBuffer = [[VImageBuffer alloc] initWithWidth:buffer.width height:buffer.height error:error];
    if (!maximaBuffer) return nil;

    return MaxPlanarF(&(buffer), &(maximaBuffer->buffer), 0, 0, kernelSize, error) ? maximaBuffer : nil;
}

- (nullable VImageBuffer *)minimizeWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    if ((kernelSize & 1) == 0) { // vImage does not check
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidKernelSize userInfo:nil];
        return nil;
    }

    VImageBuffer *minimaBuffer = [[VImageBuffer alloc] initWithWidth:buffer.width height:buffer.height error:error];
    if (!minimaBuffer) return nil;

    return MinPlanarF(&(buffer), &(minimaBuffer->buffer), 0, 0, kernelSize, error) ? minimaBuffer : nil;
}

- (BOOL)detectEdgesWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    VImageBuffer *maximaBuffer = [self maximizeWithKernelSize:kernelSize error:error];
    if (!maximaBuffer) return NO;

    VImageBuffer *minimaBuffer = [self minimizeWithKernelSize:kernelSize error:error];
    if (!minimaBuffer) return NO;

    const vImage_Buffer * const maxima = &(maximaBuffer->buffer);
    const vImage_Buffer * const minima = &(minimaBuffer->buffer);

    ptrdiff_t maxElements = (buffer.width + 3) / 4;

    NSAssert(maxElements * sizeof(vector_float4) <= buffer.rowBytes, @"incorrect alignment - rowBytes should be greater than or equal to %lu but is %zu", (unsigned long)(maxElements * sizeof(vector_float4)), buffer.rowBytes);

    dispatch_apply(buffer.height, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t row) {
        const vector_float4 *maxRow = maxima->data + maxima->rowBytes * row;
        const vector_float4 *minRow = minima->data + minima->rowBytes * row;

        vector_float4 *dstRow = buffer.data + buffer.rowBytes * row;
        vector_float4 * const endRow = dstRow + maxElements;

        do {
            *dstRow = *maxRow - *minRow;
        } while (++maxRow, ++minRow, ++dstRow < endRow);
    });

    return ContrastStretch(&buffer, &buffer, 256, error);
}

- (nullable VImageBuffer *)houghTransformWithMargin:(NSUInteger)margin error:(NSError **)error {
    NSParameterAssert(margin < kMaxTheta);

    NSUInteger maxR = ceil(kRScale * hypot(buffer.width, buffer.height));

    VImageBuffer *houghBuffer = [[VImageBuffer alloc] initWithWidth:(kMaxTheta + 2 * margin) height:(maxR + 2 * margin) error:error];
    if (!houghBuffer) return nil;

    const vImage_Buffer * const hough = &(houghBuffer->buffer);

    bzero(hough->data, hough->height * hough->rowBytes);

    // Too much contention and non-local access for this to be parallelized efficiently.
    // The single-threaded version had much better performance.
    for (NSUInteger y = 0; y < buffer.height; ++y) {
        const float * const row = buffer.data + buffer.rowBytes * y;

        for (NSUInteger x = 0; x < buffer.width; ++x) {
            if (row[x] > kGrayscaleThreshold) {
                const CGFloat xf = x, yf = y;
                const CGFloat max = hough->height;

                for (NSUInteger t = 0; t < hough->width; ++t) {
                    NSUInteger theta = (t + kMaxTheta - margin) % kMaxTheta;
                    CGFloat r = Cosine[theta] * xf + Sine[theta] * yf;

                    r *= kRScale;
                    r += margin;

                    if (r <= -1.0 || r >= max) continue;

                    NSInteger lo = floor(r), hi = ceil(r);

                    if (lo >= 0) {
                        float * const row = hough->data + hough->rowBytes * lo;
                        row[t] += (r - lo);
                    }

                    if (hi < hough->height) {
                        float * const row = hough->data + hough->rowBytes * hi;
                        row[t] += 1.0 - (r - lo);
                    }
                }
            }
        }
    }

    return houghBuffer;
}

- (nullable VImageBuffer *)normalizeContrast:(NSError **)error {
    VImageBuffer *result = [[VImageBuffer alloc] initWithWidth:buffer.width height:buffer.height error:error];
    if (!result) return nil;

    if (!ContrastStretch(&buffer, &(result->buffer), 1024, error)) return nil;

    return result;
}

- (nullable CGImageRef)copyCGImage:(NSError **)error {
    NS_VALID_UNTIL_END_OF_SCOPE NSColorSpace *grayColorSpace = [NSColorSpace genericGrayColorSpace];

    vImage_CGImageFormat format = {
        32, 32, grayColorSpace.CGColorSpace,
        kCGBitmapByteOrder32Host | kCGBitmapFloatComponents,
        0, NULL, kCGRenderingIntentDefault
    };

    return CreateCGImageFromBuffer(&buffer, &format, error);
}

- (void)dealloc {
    free(buffer.data);
}

- (void *)data {
    return buffer.data;
}

- (NSUInteger)width {
    return buffer.width;
}

- (NSUInteger)height {
    return buffer.height;
}

- (NSUInteger)bytesPerRow {
    return buffer.rowBytes;
}

@end

NS_ASSUME_NONNULL_END
