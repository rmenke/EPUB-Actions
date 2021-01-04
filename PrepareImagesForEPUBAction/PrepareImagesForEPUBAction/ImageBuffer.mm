//
//  ImageBuffer.m
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 12/13/20.
//  Copyright © 2020 Rob Menke. All rights reserved.
//

#import "ImageBuffer.h"

#import <Accelerate/Accelerate.h>

#include "ppht.hpp"

#include <simd/simd.h>

#include <array>
#include <queue>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const VImageErrorDomain = @"VImageErrorDomain";

FOUNDATION_EXPORT HoughParameterKey const HoughMaxTheta = @"maxTheta";
FOUNDATION_EXPORT HoughParameterKey const HoughMinTriggerPoints = @"minTriggerPoints";
FOUNDATION_EXPORT HoughParameterKey const HoughThreshold = @"threshold";
FOUNDATION_EXPORT HoughParameterKey const HoughChannelWidth = @"channelWidth";
FOUNDATION_EXPORT HoughParameterKey const HoughMaxGap = @"maxGap";
FOUNDATION_EXPORT HoughParameterKey const HoughMinLength = @"minLength";

static CGFloat whitePoint[] = { 0.95047, 1.0, 1.08883 };
static CGFloat blackPoint[] = { 0, 0, 0 };
static CGFloat range[] = { -127, 127, -127, 127 };

struct CGImageFormat : vImage_CGImageFormat {
    CGImageFormat(uint32_t bitsPerComponent, uint32_t bitsPerPixel, CGColorSpaceRef _Nullable colorSpace CF_RELEASES_ARGUMENT, CGBitmapInfo bitmapInfo)
        : vImage_CGImageFormat({bitsPerComponent, bitsPerPixel, colorSpace, bitmapInfo, 0, NULL, kCGRenderingIntentDefault}) {}
    CGImageFormat() : CGImageFormat(0, 0, nullptr, 0) {}

    CGImageFormat(const CGImageFormat &r) = delete;
    CGImageFormat(CGImageFormat &&r) : vImage_CGImageFormat(r) {
        r.colorSpace = NULL;
    }

    ~CGImageFormat() {
        CGColorSpaceRelease(colorSpace);
    }

    CGImageFormat &operator =(const CGImageFormat &r) = delete;
    CGImageFormat &operator =(CGImageFormat &&r) {
        CGColorSpaceRelease(colorSpace);
        static_cast<vImage_CGImageFormat &>(*this) = r;
        r.colorSpace = NULL;
        return *this;
    }
};

static void flood_alpha(const vImage_Buffer *buffer, NSRect ROI, NSUInteger x, NSUInteger y) {
    using point_t = std::pair<NSUInteger, NSUInteger>;
    using pixel_t = simd::float4;

    const NSUInteger minX = NSMinX(ROI);
    const NSUInteger minY = NSMinY(ROI);
    const NSUInteger maxX = NSMaxX(ROI);
    const NSUInteger maxY = NSMaxY(ROI);

    NSCAssert(buffer->rowBytes % sizeof(pixel_t) == 0, @"incorrect row bytes");

    const NSUInteger pixelsPerRow = buffer->rowBytes / sizeof(pixel_t);

    std::queue<point_t> next;
    next.emplace(x, y);

    auto row = static_cast<pixel_t *>(buffer->data) + pixelsPerRow * y;

    auto do_color = [referencePixel = row[x]] (pixel_t pixel) -> bool {
        if (pixel.w < 0.95f) return false;
        if (simd::all(referencePixel.xyz == pixel.xyz)) return true;
        return simd::distance(pixel.xyz, referencePixel.xyz) < 10.0f;
    };

    while (!next.empty()) {
        std::tie(x, y) = next.front();
        next.pop();

        row = static_cast<pixel_t *>(buffer->data) + pixelsPerRow * y;

        if (row[x].w < 0.95f) continue;

        auto lo = x + 1, hi = x;

        while (lo > minX && do_color(row[lo - 1])) --lo;
        while (hi < maxX && do_color(row[hi])) ++hi;

        for (x = lo; x < hi; ++x) {
            row[x] = 0.0f;
        }

        if (y > minY) {
            --y;
            for (x = lo; x < hi; ++x) next.emplace(x, y);
            ++y;
        }

        if (++y < maxY) {
            for (x = lo; x < hi; ++x) next.emplace(x, y);
        }
    }
}

template <class Segment> static inline
NSArray<NSNumber *> *convert_segment(Segment &&segment) {
    using namespace std;

    auto &&a = get<0>(segment);
    auto &&b = get<1>(segment);

    return @[@(a.x), @(a.y), @(b.x), @(b.y)];
}

static auto find_segments(const vImage_Buffer *buffer, NSDictionary<NSString *, id> * _Nullable parameters) {
    ppht::state<> state{buffer->height, buffer->width};

    std::size_t rowSize = buffer->rowBytes / sizeof(float);

    for (std::size_t y = 0; y < buffer->height; ++y) {
        auto row = static_cast<float *>(buffer->data) + rowSize * y;
        for (std::size_t x = 0; x < buffer->width; ++x) {
            if (row[x] > 0.5f) {
                state.mark_pending({x, y});
            }
        }
    }

    __block ppht::parameters param;

    static_assert(sizeof(unsigned short) == sizeof(std::uint16_t),
                  "expected uint16_t to be alias of unsigned short");

    [parameters enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        if ([HoughMaxTheta isEqualToString:key]) {
            param.set_max_theta([obj unsignedShortValue]);
        }
        else if ([HoughMinTriggerPoints isEqualToString:key]) {
            param.set_min_trigger_points([obj unsignedShortValue]);
        }
        else if ([HoughThreshold isEqualToString:key]) {
            param.set_threshold([obj doubleValue]);
        }
        else if ([HoughChannelWidth isEqualToString:key]) {
            param.set_channel_width([obj unsignedShortValue]);
        }
        else if ([HoughMaxGap isEqualToString:key]) {
            param.set_max_gap([obj unsignedShortValue]);
        }
        else if ([HoughMinLength isEqualToString:key]) {
            param.set_min_length([obj unsignedShortValue]);
        }
    }];

    return ppht::find_segments(std::move(state), param);
}

@interface ImageBuffer ()

- (nullable instancetype)initPlanarBufferWithHeight:(NSUInteger)height width:(NSUInteger)width error:(NSError **)error NS_DESIGNATED_INITIALIZER;

@end

@implementation ImageBuffer {
    vImage_Buffer _buffer;
    CGImageFormat _format;
}

+ (void)initialize {
    [NSError setUserInfoValueProviderForDomain:VImageErrorDomain
                                      provider:^id (NSError *err, NSString *userInfoKey) {
        if ([NSLocalizedFailureReasonErrorKey isEqualToString:userInfoKey]) {
            switch (err.code) {
                case kvImageNoError:
                    return @"No error";
                case kvImageRoiLargerThanInputBuffer:
                    return @"The ROI was larger than input buffer.";
                case kvImageInvalidKernelSize:
                    return @"The kernel size was invalid.";
                case kvImageInvalidEdgeStyle:
                    return @"The edge style was invalid.";
                case kvImageInvalidOffset_X:
                    return @"The X offset was invalid.";
                case kvImageInvalidOffset_Y:
                    return @"The Y offset was invalid.";
                case kvImageMemoryAllocationError:
                    return @"There was an error during memory allocation.";
                case kvImageNullPointerArgument:
                    return @"A null pointer was supplied as an argument.";
                case kvImageInvalidParameter:
                    return @"A parameter was invalid.";
                case kvImageBufferSizeMismatch:
                    return @"The buffer sizes did not match.";
                case kvImageUnknownFlagsBit:
                    return @"An unknown flag was set.";
                case kvImageInternalError:
                    return @"An internal error occurred.";
                case kvImageInvalidRowBytes:
                    return @"The row bytes count was invalid.";
                case kvImageInvalidImageFormat:
                    return @"The image format was invalid.";
                case kvImageColorSyncIsAbsent:
                    return @"ColorSync is not available.";
                case kvImageOutOfPlaceOperationRequired:
                    return @"An out-of-place operation was required, but the operation requested it to be done in place.";
                case kvImageInvalidImageObject:
                    return @"The image object was invalid.";
                case kvImageInvalidCVImageFormat:
                    return @"The CVImage format was invalid.";
                case kvImageUnsupportedConversion:
                    return @"The requested conversion is not supported.";
                case kvImageCoreVideoIsAbsent:
                    return @"CoreVideo is not available.";
            }
        }

        return nil;
    }];
}

- (nullable instancetype)initPlanarBufferWithHeight:(NSUInteger)height width:(NSUInteger)width error:(NSError **)error {
    self = [super init];

    if (self) {
        vImage_Error code = vImageBuffer_Init(&_buffer, height, width, 32, kvImageNoFlags);
        if (code != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
            return nil;
        }

        _format = CGImageFormat{32, 32, CGColorSpaceCreateDeviceGray(), kCGImageAlphaNone | kCGBitmapFloatComponents | kCGBitmapByteOrder32Host};
    }

    return self;
}

- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    self = [super init];

    if (self) {
        CGImageSourceRef source = CGImageSourceCreateWithURL(static_cast<CFURLRef>(url), nullptr);

        if (source == NULL) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
            return nil;
        }

        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, nullptr);
        CFRelease(source);

        if (image == NULL) {
            if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil];
            return nil;
        }

        _format = CGImageFormat{
            32, 128, CGColorSpaceCreateWithName(kCGColorSpaceSRGB),
            kCGImageAlphaPremultipliedLast | kCGBitmapFloatComponents | kCGBitmapByteOrder32Host,
        };

        vImage_Error code = vImageBuffer_InitWithCGImage(&_buffer, &_format, NULL, image, kvImageNoFlags);

        CGImageRelease(image);

        if (code != kvImageNoError) {
            if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
            return nil;
        }
    }

    return self;
}

- (NSUInteger)width {
    return _buffer.width;
}

- (NSUInteger)height {
    return _buffer.height;
}

- (BOOL)flattenAgainstColor:(NSColor *)color error:(NSError **)error {
    CGFloat components[4];
    [color getComponents:components];

    float rgbaBackgroundColor[4];

    std::copy(std::begin(components), std::end(components), std::begin(rgbaBackgroundColor));

    vImage_Error code = vImageFlatten_RGBAFFFF(&_buffer, &_buffer, rgbaBackgroundColor, YES, kvImageNoFlags);
    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return NO;
    }

    return YES;
}

- (BOOL)convertToLabColorSpaceAndReturnError:(NSError **)error {
    if (CGColorSpaceGetModel(_format.colorSpace) == kCGColorSpaceModelLab) {
        return YES;
    }

    CGImageFormat format{32, 128, CGColorSpaceCreateLab(whitePoint, blackPoint, range), kCGImageAlphaLast | kCGBitmapFloatComponents | kCGBitmapByteOrder32Host};

    vImage_Error code;
    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&_format, &format, NULL, kvImageNoFlags, &code);
    if (converter == NULL) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return NO;
    }

    code = vImageConvert_AnyToAny(converter, &_buffer, &_buffer, NULL, kvImageNoFlags);
    vImageConverter_Release(converter);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return NO;
    }

    _format = std::move(format);

    return YES;
}

- (BOOL)convertToRGBColorSpaceAndReturnError:(NSError **)error {
    if (CGColorSpaceGetModel(_format.colorSpace) == kCGColorSpaceModelRGB) {
        return YES;
    }

    CGImageFormat format{32, 128, CGColorSpaceCreateWithName(kCGColorSpaceSRGB), kCGImageAlphaLast | kCGBitmapFloatComponents | kCGBitmapByteOrder32Host};

    vImage_Error code;
    vImageConverterRef converter = vImageConverter_CreateWithCGImageFormat(&_format, &format, NULL, kvImageNoFlags, &code);
    if (converter == NULL) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return NO;
    }

    code = vImageConvert_AnyToAny(converter, &_buffer, &_buffer, NULL, kvImageNoFlags);
    vImageConverter_Release(converter);

    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return NO;
    }

    _format = std::move(format);

    return YES;
}

- (BOOL)autoAlphaAndReturnError:(NSError **)error {
    return [self autoAlphaInROI:NSMakeRect(0, 0, _buffer.width, _buffer.height) error:error];
}

- (BOOL)autoAlphaInROI:(NSRect)ROI error:(NSError **)error {
    CGRect roi = CGRectIntegral(NSRectToCGRect(ROI));
    CGRect bounds = CGRectMake(0.0, 0.0, _buffer.width, _buffer.height);

    if (!CGRectContainsRect(bounds, roi)) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageRoiLargerThanInputBuffer userInfo:nil];
        return NO;
    }

    NSParameterAssert(NSWidth(ROI) > 0 && NSHeight(ROI) > 0);

    const NSUInteger minX = NSMinX(ROI);
    const NSUInteger minY = NSMinY(ROI);
    const NSUInteger maxX = NSMaxX(ROI);
    const NSUInteger maxY = NSMaxY(ROI);

    dispatch_apply(_buffer.height, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(std::size_t y) {
        auto row = static_cast<simd::float4 *>(_buffer.data) + (_buffer.rowBytes / sizeof(simd::float4)) * y;
        if (y < minY || y >= maxY) {
            auto end = row + _buffer.width;
            do row->w = 0.0; while (++row < end);
        }
        else {
            for (std::size_t x = 0; x < minX; ++x) {
                row[x].w = 0.0;
            }
            for (std::size_t x = maxX; x < _buffer.width; ++x) {
                row[x].w = 0.0;
            }
        }
    });

    flood_alpha(&_buffer, ROI, minX, minY);
    flood_alpha(&_buffer, ROI, maxX - 1, minY);
    flood_alpha(&_buffer, ROI, minX, maxY - 1);
    flood_alpha(&_buffer, ROI, maxX - 1, maxY - 1);

    return YES;
}

#define vImageExtractChannel_RGBAFFFF vImageExtractChannel_ARGBFFFF

- (nullable ImageBuffer *)extractAlphaChannelAndReturnError:(NSError **)error {
    ImageBuffer *result = [[ImageBuffer alloc] initPlanarBufferWithHeight:_buffer.height width:_buffer.width error:error];
    if (!result) return nil;

    vImage_Error code = vImageExtractChannel_RGBAFFFF(&_buffer, &result->_buffer, 3, kvImageNoFlags);
    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return nil;
    }

    return result;
}

- (nullable ImageBuffer *)bufferByDilatingWithKernelSize:(NSSize)kernelSize error:(NSError **)error {
    if (CGColorSpaceGetModel(_format.colorSpace) != kCGColorSpaceModelMonochrome) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidImageFormat userInfo:nil];
        return nil;
    }

    ImageBuffer *result = [[ImageBuffer alloc] initPlanarBufferWithHeight:_buffer.height width:_buffer.width error:error];
    if (!result) return nil;

    vImage_Error code = vImageMax_PlanarF(&_buffer, &result->_buffer, NULL, 0, 0, kernelSize.height, kernelSize.width, kvImageNoFlags);
    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return nil;
    }

    return result;
}

- (nullable ImageBuffer *)bufferByErodingWithKernelSize:(NSSize)kernelSize error:(NSError **)error {
    if (CGColorSpaceGetModel(_format.colorSpace) != kCGColorSpaceModelMonochrome) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageInvalidImageFormat userInfo:nil];
        return nil;
    }

    ImageBuffer *result = [[ImageBuffer alloc] initPlanarBufferWithHeight:_buffer.height width:_buffer.width error:error];
    if (!result) return nil;

    vImage_Error code = vImageMin_PlanarF(&_buffer, &result->_buffer, NULL, 0, 0, kernelSize.height, kernelSize.width, kvImageNoFlags);
    if (code != kvImageNoError) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
        return nil;
    }

    return result;
}

- (nullable ImageBuffer *)bufferBySubtractingBuffer:(ImageBuffer *)subtrahend error:(NSError **)error {
    const vImage_Buffer *m = &_buffer;
    const vImage_Buffer *s = &subtrahend->_buffer;

    if (m->height != s->height || m->width != s->width) {
        if (error) *error = [NSError errorWithDomain:VImageErrorDomain code:kvImageBufferSizeMismatch userInfo:nil];
        return nil;
    }

    ImageBuffer *result = [[ImageBuffer alloc] initPlanarBufferWithHeight:m->height width:m->width error:error];
    if (!result) return nil;

    const vImage_Buffer *d = &result->_buffer;

    using pixel_t = simd::float4;

    dispatch_apply(d->height, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(std::size_t y) {
        const pixel_t *mRow = static_cast<simd::float4 *>(m->data) + (m->rowBytes / sizeof(simd::float4)) * y;
        const pixel_t *sRow = static_cast<simd::float4 *>(s->data) + (s->rowBytes / sizeof(simd::float4)) * y;
        pixel_t       *dRow = static_cast<simd::float4 *>(d->data) + (d->rowBytes / sizeof(simd::float4)) * y;

        simd::float4 *const dEnd = dRow + (d->width + 3) / 4;

        do {
            *dRow = *mRow - *sRow;
        } while (++mRow, ++sRow, ++dRow != dEnd);
    });

    return result;
}

- (nullable NSArray<NSArray<NSNumber *> *> *)segmentsFromBufferWithParameters:(nullable NSDictionary<NSString *, id> *)parameters error:(NSError **)error {
    NSMutableArray<NSArray<NSNumber *> *> *result = [NSMutableArray array];

    for (auto &&segment : find_segments(&_buffer, parameters)) {
        [result addObject:convert_segment(segment)];
    }

    return result;
}

- (nullable NSArray<NSArray<NSNumber *> *> *)regionsFromBufferWithParameters:(nullable NSDictionary<NSString *, id> *)parameters error:(NSError **)error {
    return @[];
}

- (nullable CGImageRef)CGImageAndReturnError:(NSError **)error {
    vImage_Error code;

    CGImageRef image = vImageCreateCGImageFromBuffer(&_buffer, &_format, NULL, NULL, kvImageNoFlags, &code);

    if (!image && error) {
        *error = [NSError errorWithDomain:VImageErrorDomain code:code userInfo:nil];
    }

    return image;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error {
    CGImageRef image = [self CGImageAndReturnError:error];
    if (!image) return NO;

    NSMutableData *data = [NSMutableData data];

    CGImageDestinationRef destination = CGImageDestinationCreateWithData(static_cast<CFMutableDataRef>(data), kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);

    CFRelease(destination);
    CGImageRelease(image);

    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

@end

NS_ASSUME_NONNULL_END
