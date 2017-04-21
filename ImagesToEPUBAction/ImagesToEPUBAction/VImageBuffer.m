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

#define UTILITY_QUEUE dispatch_get_global_queue(QOS_CLASS_UTILITY, 0)

#if CGFLOAT_IS_DOUBLE
#define vector_cgfloat vector_double
typedef vector_double2 vector_cgfloat2;
typedef vector_double4 vector_cgfloat4;
#else
#define vector_cgfloat vector_float
typedef vector_float2 vector_cgfloat2;
typedef vector_float4 vector_cgfloat4;
#endif

_Static_assert(sizeof(vector_uchar16) == 16, "size incorrect");
_Static_assert(sizeof(vector_int4) == 16, "size incorrect");
_Static_assert(sizeof(vector_cgfloat2) == sizeof(NSPoint), "Incorrect sizing");

NS_ASSUME_NONNULL_BEGIN

/*!
 * @abstract Calculate the cosine of the angle formed by three points.
 *
 * @discussion Use the law of cosines:
 * <code>cos(∠abc) = (|ab|²+|bc|²-|ac|²) / (2|ab||bc|)</code>
 *
 * @param a The first point of the angle
 * @param b The vertex of the angle
 * @param c The third point of the angle
 * @return The cosine of the angle formed by the three points
 */
FOUNDATION_STATIC_INLINE
CGFloat cosineOfAngle(vector_cgfloat2 a, vector_cgfloat2 b, vector_cgfloat2 c) {
    CGFloat ab2 = vector_distance_squared(a, b);
    CGFloat bc2 = vector_distance_squared(b, c);
    CGFloat ac2 = vector_distance_squared(a, c);

    return (ab2 + bc2 - ac2) / (2.0 * sqrt(ab2) * sqrt(bc2));
}

NSString * const VImageErrorDomain = @"VImageErrorDomain";

#define TRY(...) \
    vImage_Error code = (__VA_ARGS__); \
    if (code != kvImageNoError) { \
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil]; \
        return NO; \
    } \
    return YES

FOUNDATION_STATIC_INLINE
BOOL InitBuffer(vImage_Buffer *buf, NSUInteger height, NSUInteger width, uint32_t pixelBits, NSError **error) {
    TRY(vImageBuffer_Init(buf, height, width, pixelBits, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL InitWithCGImage(vImage_Buffer *buf, vImage_CGImageFormat *format, const CGFloat * _Nullable bgColor, CGImageRef image, NSError **error) {
    TRY(vImageBuffer_InitWithCGImage(buf, format, bgColor, image, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL CopyBuffer(const vImage_Buffer *src, const vImage_Buffer *dst, size_t pixelBytes, NSError **error) {
    TRY(vImageCopyBuffer(src, dst, pixelBytes, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL MaxPlanar8(const vImage_Buffer *src, const vImage_Buffer *dst, NSUInteger xOffset, NSUInteger yOffset, NSUInteger ksize, NSError **error) {
    TRY(vImageMax_Planar8(src, dst, NULL, xOffset, yOffset, ksize, ksize, kvImageNoFlags));
}

FOUNDATION_STATIC_INLINE
BOOL MinPlanar8(const vImage_Buffer *src, const vImage_Buffer *dst, NSUInteger xOffset, NSUInteger yOffset, NSUInteger ksize, NSError **error) {
    TRY(vImageMin_Planar8(src, dst, NULL, xOffset, yOffset, ksize, ksize, kvImageNoFlags));
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
BOOL ContrastStretch(const vImage_Buffer *src, const vImage_Buffer *dest, NSError **error) {
    TRY(vImageContrastStretch_Planar8(src, dest, kvImageNoFlags));
}

const NSUInteger kMaxTheta = 1024;
const CGFloat kRScale = 2.0;
const uint8_t kGrayscaleThreshold = 0x7f;
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

- (nullable instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height error:(NSError **)error {
    self = [super init];

    if (self) {
        if (!InitBuffer(&buffer, height, width, 8, error)) return nil;
    }

    return self;
}

- (nullable instancetype)initWithImage:(CGImageRef)image backgroundColor:(nullable NSColor *)backgroundColor error:(NSError **)error {
    self = [super init];

    if (self) {
        NSColorSpace *imageColorSpace = [[NSColorSpace alloc] initWithCGColorSpace:CGImageGetColorSpace(image)];
        NS_VALID_UNTIL_END_OF_SCOPE NSColorSpace *grayColorSpace = [NSColorSpace genericGrayColorSpace];

        backgroundColor = [backgroundColor colorUsingColorSpace:imageColorSpace];
        if (!backgroundColor) backgroundColor = [[NSColor whiteColor] colorUsingColorSpace:imageColorSpace];

        CGFloat backgroundPixels[backgroundColor.numberOfComponents];        
        [backgroundColor getComponents:backgroundPixels];

        vImage_CGImageFormat format = {
            8, 8, grayColorSpace.CGColorSpace, kCGBitmapByteOrderDefault, 0, NULL, kCGRenderingIntentDefault
        };

        if (!InitWithCGImage(&buffer, &format, backgroundColor ? backgroundPixels : NULL, image, error)) return nil;
    }

    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    NSError * __autoreleasing error;

    VImageBuffer *copy = [[VImageBuffer allocWithZone:zone] initWithWidth:buffer.width height:buffer.height error:&error];
    if (!copy || !CopyBuffer(&buffer, &(copy->buffer), 1, &error)) {
        @throw [NSException exceptionWithName:NSGenericException reason:error.localizedDescription userInfo:@{NSUnderlyingErrorKey: error}];
    }

    return copy;
}

- (nullable VImageBuffer *)maximizeWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    if ((kernelSize & 1) == 0) { // vImage does not check
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidKernelSize userInfo:nil];
        return nil;
    }

    VImageBuffer *maximaBuffer = [[VImageBuffer alloc] initWithWidth:buffer.width height:buffer.height error:error];
    if (!maximaBuffer) return nil;

    return MaxPlanar8(&(buffer), &(maximaBuffer->buffer), 0, 0, kernelSize, error) ? maximaBuffer : nil;
}

- (nullable VImageBuffer *)minimizeWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    if ((kernelSize & 1) == 0) { // vImage does not check
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidKernelSize userInfo:nil];
        return nil;
    }

    VImageBuffer *minimaBuffer = [[VImageBuffer alloc] initWithWidth:buffer.width height:buffer.height error:error];
    if (!minimaBuffer) return nil;

    return MinPlanar8(&(buffer), &(minimaBuffer->buffer), 0, 0, kernelSize, error) ? minimaBuffer : nil;
}

- (BOOL)detectEdgesWithKernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    VImageBuffer *maximaBuffer = [self maximizeWithKernelSize:kernelSize error:error];
    if (!maximaBuffer) return NO;

    const vImage_Buffer * const maxima = &(maximaBuffer->buffer);

    ptrdiff_t vec_per_row = (buffer.width + 15) / 16;

    NSAssert(vec_per_row * sizeof(vector_uchar16) <= buffer.rowBytes, @"incorrect alignment - rowBytes should be greater than or equal to %zu but is %zu", vec_per_row * sizeof(vector_uchar16), buffer.rowBytes);

    dispatch_apply(buffer.height, UTILITY_QUEUE, ^(size_t row) {
        const vector_uchar16 *maxRow = maxima->data + maxima->rowBytes * row;

        vector_uchar16 *dstRow = buffer.data + buffer.rowBytes * row;
        vector_uchar16 *endRow = dstRow + vec_per_row;

        do {
            *dstRow = *maxRow - *dstRow;
        } while (++maxRow, ++dstRow < endRow);
    });

    return YES;
}

- (nullable NSArray<NSValue *> *)findSegmentsAndReturnError:(NSError **)error {
    return @[]; // TODO: Implement
}

- (nullable NSArray<NSValue *> *)findRegionsAndReturnError:(NSError **)error {
    return @[]; // TODO: Implement
}

- (nullable VImageBuffer *)normalizeContrastAndReturnError:(NSError **)error {
    VImageBuffer *result = [[VImageBuffer alloc] initWithWidth:buffer.width height:buffer.height error:error];
    if (!result) return nil;

    if (!ContrastStretch(&buffer, &(result->buffer), error)) return nil;

    return result;
}

- (nullable CGImageRef)copyCGImageAndReturnError:(NSError **)error {
    NS_VALID_UNTIL_END_OF_SCOPE NSColorSpace *grayColorSpace = [NSColorSpace genericGrayColorSpace];

    vImage_CGImageFormat format = {
        8, 8, grayColorSpace.CGColorSpace, kCGBitmapByteOrderDefault
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
