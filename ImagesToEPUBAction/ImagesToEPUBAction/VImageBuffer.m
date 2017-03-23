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

_Static_assert(sizeof(vector_float4) == 16, "size incorrect");
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

    dispatch_apply(buffer.height, UTILITY_QUEUE, ^(size_t row) {
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

- (nullable NSSet<NSValue *> *)findLinesWithThreshold:(NSUInteger)threshold kernelSize:(NSUInteger)kernelSize error:(NSError **)error {
    VImageBuffer *maxima = [self maximizeWithKernelSize:kernelSize error:error];
    if (!maxima) return nil;

    dispatch_queue_t queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    dispatch_group_t group = dispatch_group_create();

    NSMutableSet<NSValue *> *points = [NSMutableSet setWithCapacity:256];

    dispatch_apply(buffer.height, UTILITY_QUEUE, ^(size_t r) {
        const float * const srcRow = buffer.data + buffer.rowBytes * r;
        const float * const maxRow = maxima->buffer.data + maxima->buffer.rowBytes * r;

        NSMutableSet<NSValue *> *rowPoints = [NSMutableSet set];

        for (int theta = 0; theta < buffer.width; ++theta) {
            if (srcRow[theta] >= threshold && srcRow[theta] == maxRow[theta]) {
                [rowPoints addObject:[NSValue valueWithPoint:NSMakePoint(r, theta)]];
            }
        }

        dispatch_group_async(group, queue, ^{
            [points unionSet:rowPoints];
        });
    });

    dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

    return points;
}

- (NSArray<NSDictionary<NSString *, NSValue *> *> *)findSegmentsWithLines:(NSSet<NSValue *> *)lines margin:(NSUInteger)margin minLength:(NSUInteger)minLength {
    NSUInteger thresholdSquared = minLength * minLength;

    NSMutableSet<NSDictionary<NSString *, NSValue *> *> *segments = [NSMutableSet set];

    for (NSValue *value in lines) {
        NSPoint point = value.pointValue;
        CGFloat r = (point.x - margin) / kRScale;
        NSInteger theta = ((NSInteger)(point.y) + kMaxTheta - margin) % kMaxTheta;

        CGFloat cs = Cosine[theta], sn = Sine[theta];

        const CGFloat x0 = r * cs;
        const CGFloat y0 = r * sn;

        const CGFloat w = buffer.width;
        const CGFloat h = buffer.height;

        // The line is defined parametrically:
        //   x = x0 + sn * z
        //   y = y0 - cs * z
        // Calculate the values for z where the line intersects the buffer frame.  Some of these values may be infinite/NaN if the line parallels an axis.

        const CGFloat z0 = (0 - x0) / sn;
        const CGFloat z1 = (w - x0) / sn;
        const CGFloat z2 = (y0 - 0) / cs;
        const CGFloat z3 = (y0 - h) / cs;

        // For all z ∈ [zMin, zMax], the point generated by the parametric equation should be contained in the buffer frame (within reasonable rounding limits).

        CGFloat zMin = +INFINITY, zMax = -INFINITY;

        if (isfinite(z0)) {
            CGFloat y = round(y0 - cs * z0);
            if (y >= 0 && y <= h) {
                if (zMin > z0) zMin = z0;
                if (zMax < z0) zMax = z0;
            }
        }
        if (isfinite(z1)) {
            CGFloat y = round(y0 - cs * z1);
            if (y >= 0 && y <= h) {
                if (zMin > z1) zMin = z1;
                if (zMax < z1) zMax = z1;
            }
        }
        if (isfinite(z2)) {
            CGFloat x = round(x0 + sn * z2);
            if (x >= 0 && x <= w) {
                if (zMin > z2) zMin = z2;
                if (zMax < z2) zMax = z2;
            }
        };
        if (isfinite(z3)) {
            CGFloat x = round(x0 + sn * z3);
            if (x >= 0 && x <= w) {
                if (zMin > z3) zMin = z3;
                if (zMax < z3) zMax = z3;
            }
        };

        // At least two of {z0, z1, z2, z3} should be finite, so z_min and z_max should be defined.  If the line fails to intersect the bounding rectangle at more than one point, this will not hold.  The Hough scanner should not produce these degenerate values, but there may be pathological cases.

        if (!isfinite(zMin) || !isfinite(zMax)) continue;

        vector_long2 segStart = { 0, 0 };
        vector_long2 lastPoint = { -1, -1 };

        // Cheat by assuming that the layout of NSPoint matches that of vector_cgfloat2.  Otherwise we would have to use NSMakePoint() which generates a lot of unnecessary transfer/stores.  Objective-C documentation says that SIMD vector types are supported by @encode() but it lies.

        _Static_assert(sizeof(vector_cgfloat2) == sizeof(NSPoint), "Incorrect sizing");

        BOOL wasInSegment = NO;

        vector_ulong2 bound = vector2(buffer.width, buffer.height);

        for (CGFloat z = zMin; z <= zMax; z += 0.5) {
            vector_long2 currentPoint = { lround(x0 + sn * z), lround(y0 - cs * z) };

            if (vector_all(currentPoint == lastPoint)) continue;
            if (vector_any(currentPoint < 0) || vector_any(currentPoint >= bound)) continue;

            float *row = buffer.data + buffer.rowBytes * currentPoint.y;

            BOOL nowInSegment = row[currentPoint.x] > kGrayscaleThreshold;

            if (!wasInSegment && nowInSegment) { // start a new segment
                segStart = currentPoint;
            } else if (wasInSegment && !nowInSegment) { // end the current segment
                const vector_long2 delta = lastPoint - segStart;
                const long length = vector_reduce_add(delta * delta);

                if (length >= thresholdSquared) {
                    NSValue *p1 = [NSValue valueWithPoint:NSMakePoint(segStart.x, segStart.y)];
                    NSValue *p2 = [NSValue valueWithPoint:NSMakePoint(lastPoint.x, lastPoint.y)];

                    [segments addObject:@{@"p1":p1, @"p2":p2, @"orthogonality":@(fabs(cs * sn))}];
                }
            }

            wasInSegment = nowInSegment;
            lastPoint = currentPoint;
        }
    }

    NSSortDescriptor *descriptor = [NSSortDescriptor sortDescriptorWithKey:@"orthogonality" ascending:YES];
    return [segments.allObjects sortedArrayUsingDescriptors:@[descriptor]];
}

+ (NSArray<NSArray<NSValue *> *> *)convertSegmentsToPolylines:(NSArray<NSDictionary<NSString *, NSValue *> *> *)segments {
    NSMutableArray<NSMutableArray<NSValue *> *> *polylines = [NSMutableArray array];

    for (NSDictionary<NSString *, NSValue *> *segment in segments) {
        NSValue *p1 = segment[@"p1"];
        NSValue *p2 = segment[@"p2"];

        [polylines addObject:[NSMutableArray arrayWithObjects:p1, p2, nil]];
    }

    NSSortDescriptor *usingDistance = [NSSortDescriptor sortDescriptorWithKey:@"distance" ascending:YES];
    NSSortDescriptor *usingCosine   = [NSSortDescriptor sortDescriptorWithKey:@"cosine" ascending:YES];
    NSSortDescriptor *usingClosing  = [NSSortDescriptor sortDescriptorWithKey:@"closing" ascending:YES];
    NSSortDescriptor *usingLength   = [NSSortDescriptor sortDescriptorWithKey:@"length" ascending:NO];
    NSSortDescriptor *usingPrepend  = [NSSortDescriptor sortDescriptorWithKey:@"prepend" ascending:YES];

    for (NSInteger i = 0; i < polylines.count; ++i) {
        NSMutableArray<NSValue *> *polyline = polylines[i];
        vector_cgfloat2 p0; [polyline.firstObject getValue:&p0];
        vector_cgfloat2 p1; [polyline.lastObject getValue:&p1];

        NSDictionary *candidate = nil;

        for (NSUInteger j = i + 1; j < polylines.count; ++j) {
            NSMutableArray<NSValue *> *segment = polylines[j];

            vector_cgfloat2 q0; [segment.firstObject getValue:&q0];
            vector_cgfloat2 q1; [segment.lastObject getValue:&q1];

            CGFloat d00 = vector_distance_squared(p0, q0);
            CGFloat d01 = vector_distance_squared(p0, q1);
            CGFloat d10 = vector_distance_squared(p1, q0);
            CGFloat d11 = vector_distance_squared(p1, q1);

            CGFloat dmin = fmin(fmin(d00, d01), fmin(d10, d11));
            if (dmin > 4.0) continue;

            vector_cgfloat2 a; // the point to add
            vector_cgfloat2 b; // the new endpoint (average of px and qx
            vector_cgfloat2 c; // the other point on the polyline

            CGFloat closing; // Can we close the path?
            NSNumber *prepend; // prepending or appending? Prefer the latter

            if (d10 == dmin) { // p1 is close to q0
                a = q1;
                b = (p1 + q0) / 2.0;
                [polyline[polyline.count - 2] getValue:&c];
                closing = vector_distance_squared(a, p0);
                prepend = @NO;
            }
            else if (d11 == dmin) { // p1 is close to q1
                a = q0;
                b = (p1 + q1) / 2.0;
                [polyline[polyline.count - 2] getValue:&c];
                closing = vector_distance_squared(a, p0);
                prepend = @NO;
            }
            else if (d00 == dmin) { // p0 is close to q0
                a = q1;
                b = (p0 + q0) / 2.0;
                [polyline[1] getValue:&c];
                closing = vector_distance_squared(a, p1);
                prepend = @YES;
            }
            else { // p0 is close to q1
                a = q0;
                b = (p0 + q1) / 2.0;
                [polyline[1] getValue:&c];
                closing = vector_distance_squared(a, p1);
                prepend = @YES;
            }

            CGFloat cosine = cosineOfAngle(a, b, c);

            NSDictionary *nominee = @{@"newPoint":[NSValue value:&a withObjCType:@encode(NSPoint)], @"endPoint":[NSValue value:&b withObjCType:@encode(NSPoint)], @"prepend":prepend, @"cosine":@(fabs(cosine)), @"distance":@(dmin), @"closing":@(closing), @"length":@(vector_distance_squared(a, b)), @"index":@(j)};

            NSComparisonResult result = candidate == nil ? NSOrderedDescending : NSOrderedSame;
            if (result == NSOrderedSame) result = [usingCosine compareObject:candidate toObject:nominee];
            if (result == NSOrderedSame) result = [usingDistance compareObject:candidate toObject:nominee];
            if (result == NSOrderedSame) result = [usingLength compareObject:candidate toObject:nominee];
            if (result == NSOrderedSame) result = [usingClosing compareObject:candidate toObject:nominee];
            if (result == NSOrderedSame) result = [usingPrepend compareObject:candidate toObject:nominee];
            if (result == NSOrderedDescending) candidate = nominee;
        }

        if (candidate == nil) continue; // No candidate found

        NSValue *newPoint = [candidate valueForKey:@"newPoint"];
        NSValue *endPoint = [candidate valueForKey:@"endPoint"];
        NSNumber *prepend = [candidate valueForKey:@"prepend"];
        NSNumber *index   = [candidate valueForKey:@"index"];

        if (prepend.boolValue) {
            polyline[0] = endPoint;
            [polyline insertObject:newPoint atIndex:0];
        }
        else {
            polyline[polyline.count - 1] = endPoint;
            [polyline addObject:newPoint];
        }

        [polylines removeObjectAtIndex:index.unsignedIntegerValue];

        vector_cgfloat2 q0; [polyline.firstObject getValue:&q0];
        vector_cgfloat2 q1; [polyline.lastObject getValue:&q1];

        if (vector_distance_squared(q0, q1) <= 4.0) {
            q0 = (q0 + q1) / 2.0;
            polyline[0] = [NSValue value:&q0 withObjCType:@encode(NSPoint)];
            [polyline removeLastObject];
        } else {
            --i;
        }
    }

    return [polylines filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF[SIZE] > 2"]];
}

+ (NSArray<NSValue *> *)convertPolylinesToRegions:(NSArray<NSArray<NSValue *> *> *)polylines {
    NSMutableArray<NSValue *> *regions = [NSMutableArray arrayWithCapacity:polylines.count];

    for (NSArray<NSValue *> *polyline in polylines) {
        CGRect region = CGRectNull;
        for (NSValue *value in polyline) {
            CGPoint p = NSPointToCGPoint(value.pointValue);
            if (!CGRectContainsPoint(region, p)) {
                region = CGRectUnion(region, (CGRect) { .origin = p, .size.width = 0, .size.height = 0 });
            }
        }
        [regions addObject:[NSValue valueWithRect:NSRectFromCGRect(region)]];
    }

    for (NSUInteger i = 0; i < regions.count; ++i) {
        CGRect a = NSRectToCGRect(regions[i].rectValue);
        for (NSUInteger j = i + 1; j < regions.count; ++j) {
            CGRect b = NSRectToCGRect(regions[j].rectValue);

            if (CGRectEqualToRect(a, CGRectIntersection(a, CGRectInset(b, -2.0, -2.0))) ||
                CGRectEqualToRect(b, CGRectIntersection(b, CGRectInset(a, -2.0, -2.0)))) {
                CGRect c = CGRectUnion(a, b);
                [regions removeObjectAtIndex:j];
                if (CGRectEqualToRect(a, c)) {
                    j--;
                }
                else {
                    regions[i] = [NSValue valueWithRect:NSRectFromCGRect(a = c)];
                    j = i;
                }
            }
        }
    }

    [regions sortUsingComparator:^NSComparisonResult(NSValue *obj1, NSValue *obj2) {
        CGRect a = NSRectToCGRect(obj1.rectValue);
        CGRect b = NSRectToCGRect(obj2.rectValue);

        CGFloat aMin = CGRectGetMinY(a);
        CGFloat bMin = CGRectGetMinY(b);
        CGFloat aMax = CGRectGetMaxY(a);
        CGFloat bMax = CGRectGetMaxY(b);

        if ((aMin > bMin || aMax < bMax) && (aMin < bMin || aMax > bMax)) {
            return aMin < bMin ? NSOrderedAscending : NSOrderedDescending;
        }

        aMin = CGRectGetMinX(a);
        bMin = CGRectGetMinX(b);
        aMax = CGRectGetMaxX(a);
        bMax = CGRectGetMaxX(b);

        if ((aMin > bMin || aMax < bMax) && (aMin < bMin || aMax > bMax)) {
            return aMin < bMin ? NSOrderedAscending : NSOrderedDescending;
        }

        return NSOrderedSame;
    }];

    return regions;
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
