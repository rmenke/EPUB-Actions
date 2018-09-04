//
//  VImageBufferTests.m
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/16/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

@import XCTest;

#include "VImageBuffer.h"

#define CLS(X) NSClassFromString(@#X)

NSURL *urlForTest(SEL _cmd, NSString *path) {
    path = [path.stringByDeletingPathExtension stringByAppendingPathExtension:@"png"];
    path = [[NSStringFromSelector(_cmd) stringByAppendingString:@"-"] stringByAppendingString:path];
    path = [NSHomeDirectory() stringByAppendingPathComponent:path];
    return [NSURL fileURLWithPath:path];
}

NSArray<NSNumber *> *twiddle(NSArray<NSNumber *> *array) {
    if (arc4random_uniform(2) == 0) {
        array = @[array[2], array[3], array[0], array[1]];
    }

    uint32_t dx, dy;

    dx = arc4random_uniform(3) - 1;
    dy = arc4random_uniform(3) - 1;

    NSNumber *x1 = @(array[0].shortValue + dx);
    NSNumber *y1 = @(array[1].shortValue + dy);
    NSNumber *x2 = @(array[2].shortValue + dx);
    NSNumber *y2 = @(array[3].shortValue + dy);

    return @[x1,y1,x2,y2];
}

NSArray *shuffle(NSArray *array) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
    NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];

    for (NSUInteger i = 0; i < array.count; ++i) {
        NSUInteger ix;

        do ix = arc4random_uniform((uint32_t)(array.count));
        while ([indexSet containsIndex:ix]);

        [result addObject:array[ix]];
        [indexSet addIndex:ix];
    }

    return result;
}

#define CF_URL_FOR_TEST(FILE) (__bridge CFURLRef)(urlForTest(_cmd, FILE))

@interface VImageBuffer (WhiteBoxTesting)

- (void *)row:(NSUInteger)row;

@end

@interface VImageBufferTests : XCTestCase

@property (nonatomic, readonly) NSArray<NSURL *> *imageURLs;
@property (nonatomic, readonly) NSDictionary<NSString *, id> *parameters;

@end

@implementation VImageBufferTests

- (void)setUp {
    [super setUp];

    NSError * __autoreleasing error = nil;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSURL *actionURL = [bundle URLForResource:@"Prepare Images for EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSBundle *actionBundle = [NSBundle bundleWithURL:actionURL];

    XCTAssert([actionBundle loadAndReturnError:&error], @"error - %@", error);

    NSMutableArray *imageURLs = [NSMutableArray array];

    for (NSUInteger ix = 1; ix < 100; ++ix) {
        NSURL *url = [bundle URLForImageResource:[NSString stringWithFormat:@"image%02lu", (unsigned long)(ix)]];
        if (!url) break;

        [imageURLs addObject:url];
    }

    _imageURLs = imageURLs;

    _parameters = @{@"sensitivity":@12, @"maxGap":@3, @"closeGap":@5};
}

- (void)tearDown {
    [super tearDown];
}

- (void)testInit {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[1] error:&error];

    XCTAssertNotNil(buffer, @"error - %@", error);

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testInitNoFile {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@"/not/a/file"] error:&error];

    XCTAssertNil(buffer, @"Unexpected success");
    XCTAssertNotNil(error, @"Error object not populated");
}

- (void)testInitBadFile {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:[NSURL fileURLWithPath:@"/etc/passwd"] error:&error];

    XCTAssertNil(buffer, @"Unexpected success");
    XCTAssertNotNil(error, @"Error object not populated");
}

- (void)testExtractAlpha {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[0] error:&error];
    __block VImageBuffer *result;

    [self measureBlock:^{
        NSError * __autoreleasing error = nil;
        result = [buffer extractBorderMaskInRect:CGRectMake(0, 0, buffer.width, buffer.height) error:&error];
        XCTAssertNotNil(result, @"error - %@", error);
    }];

    CGImageRef image = [result newGrayscaleImageFromBufferAndReturnError:&error];
    XCTAssertNotEqual(image, NULL, @"error - %@", error);

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(@"out.png"), kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);

    CGImageRelease(image);
    CFRelease(destination);
}

- (void)testExtractNoAlpha {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[1] error:&error];
    __block VImageBuffer *result;

    [self measureBlock:^{
        NSError * __autoreleasing error = nil;
        result = [buffer extractBorderMaskInRect:CGRectMake(0, 0, buffer.width, buffer.height) error:&error];
        XCTAssertNotNil(result, @"error - %@", error);
    }];

    CGImageRef image = [result newGrayscaleImageFromBufferAndReturnError:&error];
    XCTAssertNotEqual(image, NULL, @"error - %@", error);

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(@"out.png"), kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);

    CGImageRelease(image);
    CFRelease(destination);
}

- (void)testOpen {
    const uint8_t W = 0xff;
    const uint8_t B = 0x00;

    uint8_t original[][16] = {
        { W, B, W, W, W, W, B, W, W, W },
        { W, W, B, W, W, W, W, W, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, B, W, W, W, W, W, W, W },
        { W, W, B, W, W, W, W, W, W, W },
        { W, W, B, W, W, W, W, W, W, W },
        { W, W, B, W, W, W, W, W, W, W },
    };

    uint8_t expected[][16] = {
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, B, B, B, W, W },
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, W, W, W, W, W },
    };

    NSError * __autoreleasing error;

    VImageBuffer *buffer = [CLS(VImageBuffer) bufferWithWidth:10 height:10 bitsPerPixel:8 error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = [buffer row:y];
        for (NSUInteger x = 0; x < buffer.width; ++x) {
            row[x] = original[y][x];
        }
    }

    VImageBuffer *openedBuffer = [buffer openWithWidth:3 height:3 error:&error];

    for (NSUInteger y = 0; y < openedBuffer.height; ++y) {
        uint8_t *actualRow = [openedBuffer row:y];
        uint8_t *expectedRow = expected[y];
        for (NSUInteger x = 0; x < openedBuffer.width; ++x) {
            NSUInteger actual = actualRow[x];
            NSUInteger expected = expectedRow[x];
            XCTAssertEqual(actual, expected, "(%lu,%lu)", x, y);
        }
    }
}

- (void)testEdgeDetection {
    NSError * __autoreleasing error = nil;

    for (NSURL *url in self.imageURLs) {
        @autoreleasepool {
            VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:url error:&error];
            XCTAssertNotNil(buffer, @"error - %@", error);

            VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectMake(0, 0, buffer.width, buffer.height) error:&error];
            XCTAssertNotNil(border, @"error - %@", error);

            XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

            CGImageRef image = [border newGrayscaleImageFromBufferAndReturnError:&error];
            XCTAssertNotEqual(image, NULL, @"error - %@", error);

            CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(url.lastPathComponent), kUTTypePNG, 1, NULL);
            CGImageDestinationAddImage(destination, image, NULL);
            CGImageDestinationFinalize(destination);

            CGImageRelease(image);
            CFRelease(destination);
        }
    }
}

- (void)testEdgeDetectionWithCrop {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:_imageURLs[4] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    CGRect rect = CGRectMake(0, 0, buffer.width, buffer.height);

    VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectInset(rect, 12, 12) error:&error];
    XCTAssertNotNil(border, @"error - %@", error);

    XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

    CGImageRef image = [border newGrayscaleImageFromBufferAndReturnError:&error];
    XCTAssertNotEqual(image, NULL, @"error - %@", error);

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(@"out.png"), kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageDestinationFinalize(destination);

    CGImageRelease(image);
    CFRelease(destination);
}

- (void)testSegmentDetection {
    NSError * __autoreleasing error = nil;

    for (NSURL *url in self.imageURLs) {
        @autoreleasepool {
            VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:url error:&error];
            XCTAssertNotNil(buffer, @"error - %@", error);

            VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectMake(0, 0, buffer.width, buffer.height) error:&error];
            XCTAssertNotNil(border, @"error - %@", error);

            XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

            NSArray<NSArray<NSNumber *> *> *segments = [border detectSegmentsWithOptions:_parameters error:&error];
            XCTAssertNotNil(segments, @"error - %@", error);

            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(cs);

            CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
            CFRelease(source);

            CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);
            CGImageRelease(image);

            CGContextTranslateCTM(context, 0, buffer.height);
            CGContextScaleCTM(context, 1, -1);

            CGContextSetRGBStrokeColor(context, 1, 0, 0, 1);

            for (NSArray<NSNumber *> *segment in segments) {
                CGContextMoveToPoint(context, segment[0].doubleValue, segment[1].doubleValue);
                CGContextAddLineToPoint(context, segment[2].doubleValue, segment[3].doubleValue);
            }

            CGContextStrokePath(context);

            CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(url.lastPathComponent), kUTTypePNG, 1, NULL);

            image = CGBitmapContextCreateImage(context);
            CGImageDestinationAddImage(destination, image, NULL);
            CGImageRelease(image);

            CGImageDestinationFinalize(destination);
            CFRelease(destination);
        }
    }
}

- (void)testSegmentDetectionWithCrop {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:_imageURLs[4] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    CGRect rect = CGRectMake(0, 0, buffer.width, buffer.height);

    VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectInset(rect, 12, 12) error:&error];
    XCTAssertNotNil(border, @"error - %@", error);

    XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

    NSArray<NSArray<NSNumber *> *> *segments = [border detectSegmentsWithOptions:_parameters error:&error];
    XCTAssertNotNil(segments, @"error - %@", error);

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);

    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)_imageURLs[4], NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);

    CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);
    CGImageRelease(image);

    CGContextTranslateCTM(context, 0, buffer.height);
    CGContextScaleCTM(context, 1, -1);

    CGContextSetRGBStrokeColor(context, 1, 0, 0, 1);

    for (NSArray<NSNumber *> *segment in segments) {
        CGContextMoveToPoint(context, segment[0].doubleValue, segment[1].doubleValue);
        CGContextAddLineToPoint(context, segment[2].doubleValue, segment[3].doubleValue);
    }

    CGContextStrokePath(context);

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(@"out.png"), kUTTypePNG, 1, NULL);

    image = CGBitmapContextCreateImage(context);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageRelease(image);

    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

- (void)testPolylineDetection {
    NSError * __autoreleasing error = nil;

    NSUInteger _expected[] = { 3, 4, 2, 1, 1, 7 };
    NSUInteger *expected = _expected;

    for (NSURL *url in self.imageURLs) {
        @autoreleasepool {
            VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:url error:&error];
            XCTAssertNotNil(buffer, @"error - %@", error);

            VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectMake(0, 0, buffer.width, buffer.height) error:&error];
            XCTAssertNotNil(border, @"error - %@", error);

            XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

            NSArray<NSArray<NSNumber *> *> *polylines = [border detectPolylinesWithOptions:_parameters error:&error];
            XCTAssertNotNil(polylines, @"error - %@", error);

            XCTAssertEqual(polylines.count, *(expected++));

            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(cs);

            CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
            CFRelease(source);

            CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);
            CGImageRelease(image);

            CGContextTranslateCTM(context, 0, buffer.height);
            CGContextScaleCTM(context, 1, -1);

            CGContextSetRGBStrokeColor(context, 1, 0, 0, 1);

            CGContextSetLineWidth(context, 3.0);
            CGContextSetLineCap(context, kCGLineCapButt);
            CGContextSetLineJoin(context, kCGLineJoinMiter);
            CGContextSetMiterLimit(context, 5.0);

            for (NSArray<NSNumber *> *polyline in polylines) {
                double x0 = polyline[0].doubleValue;
                double y0 = polyline[1].doubleValue;

                CGContextMoveToPoint(context, x0, y0);

                double x1, y1;

                for (NSUInteger i = 2; i < polyline.count; i += 2) {
                    CGContextAddLineToPoint(context, x1 = polyline[i].doubleValue, y1 = polyline[i + 1].doubleValue);
                }

                if (x0 == x1 && y0 == y1) CGContextClosePath(context);
            }

            CGContextStrokePath(context);

            CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(url.lastPathComponent), kUTTypePNG, 1, NULL);

            image = CGBitmapContextCreateImage(context);
            CGImageDestinationAddImage(destination, image, NULL);
            CGImageRelease(image);

            CGImageDestinationFinalize(destination);
            CFRelease(destination);
        }
    }
}

- (void)testPolylineDetectionWithCrop {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[4] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    CGRect rect = CGRectMake(0, 0, buffer.width, buffer.height);

    VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectInset(rect, 12, 12) error:&error];
    XCTAssertNotNil(border, @"error - %@", error);

    XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

    __block NSArray<NSArray<NSNumber *> *> *polylines;

    [self measureBlock:^{
        NSError * __autoreleasing error = nil;

        polylines = [border detectPolylinesWithOptions:_parameters error:&error];
        XCTAssertNotNil(polylines, @"error - %@", error);
    }];

    XCTAssertEqual(polylines.count, 3);

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);

    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)_imageURLs[4], NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);

    CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);
    CGImageRelease(image);

    CGContextTranslateCTM(context, 0, buffer.height);
    CGContextScaleCTM(context, 1, -1);

    CGContextSetRGBStrokeColor(context, 1, 0, 0, 1);

    for (NSArray<NSNumber *> *polyline in polylines) {
        double x0 = polyline[0].doubleValue;
        double y0 = polyline[1].doubleValue;

        CGContextMoveToPoint(context, x0, y0);

        double x1, y1;

        for (NSUInteger i = 2; i < polyline.count; i += 2) {
            CGContextAddLineToPoint(context, x1 = polyline[i].doubleValue, y1 = polyline[i + 1].doubleValue);
        }

        if (x0 == x1 && y0 == y1) CGContextClosePath(context);
    }

    CGContextStrokePath(context);

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(@"out.png"), kUTTypePNG, 1, NULL);

    image = CGBitmapContextCreateImage(context);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageRelease(image);

    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

- (void)testRegionDetection {
    NSError * __autoreleasing error = nil;

    NSUInteger _expected[] = { 3, 4, 2, 1, 1, 7 };
    NSUInteger *expected = _expected;

    for (NSURL *url in self.imageURLs) {
        @autoreleasepool {
            VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:url error:&error];
            XCTAssertNotNil(buffer, @"error - %@", error);

            VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectMake(0, 0, buffer.width, buffer.height) error:&error];
            XCTAssertNotNil(border, @"error - %@", error);

            XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

            NSArray<NSArray<NSNumber *> *> *regions = [border detectRegionsWithOptions:_parameters error:&error];
            XCTAssertNotNil(regions, @"error - %@", error);

            XCTAssertEqual(regions.count, *(expected++));

            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
            CGColorSpaceRelease(cs);

            CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
            CFRelease(source);

            CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);
            CGImageRelease(image);

            CGContextTranslateCTM(context, 0, buffer.height);
            CGContextScaleCTM(context, 1, -1);

            CGContextSetRGBStrokeColor(context, 0, 0, 1, 1.00);
            CGContextSetRGBFillColor(context, 1, 0, 0, 0.10);

            for (NSArray<NSNumber *> *region in regions) {
                CGRect rect = CGRectMake(region[0].doubleValue, region[1].doubleValue, region[2].doubleValue, region[3].doubleValue);
                CGContextAddRect(context, rect);
                CGContextFillPath(context);
                CGContextAddRect(context, rect);
                CGContextStrokePath(context);
            }

            CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(url.lastPathComponent), kUTTypePNG, 1, NULL);

            image = CGBitmapContextCreateImage(context);
            CGImageDestinationAddImage(destination, image, NULL);
            CGImageRelease(image);

            CGImageDestinationFinalize(destination);
            CFRelease(destination);
        }
    }
}

- (void)testRegionDetectionWithCrop {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[4] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    CGRect rect = CGRectMake(0, 0, buffer.width, buffer.height);

    VImageBuffer *border = [buffer extractBorderMaskInRect:CGRectInset(rect, 12, 12) error:&error];
    XCTAssertNotNil(border, @"error - %@", error);

    XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

    __block NSArray<NSArray<NSNumber *> *> *regions;

    [self measureBlock:^{
        NSError * __autoreleasing error = nil;

        regions = [border detectRegionsWithOptions:_parameters error:&error];
        XCTAssertNotNil(regions, @"error - %@", error);
    }];

    XCTAssertEqual(regions.count, 3);

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);

    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)_imageURLs[4], NULL);
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);

    CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);
    CGImageRelease(image);

    CGContextTranslateCTM(context, 0, buffer.height);
    CGContextScaleCTM(context, 1, -1);

    CGContextSetRGBFillColor(context, 1, 0, 0, 0.25);

    for (NSArray<NSNumber *> *region in regions) {
        CGRect rect = CGRectMake(region[0].doubleValue, region[1].doubleValue, region[2].doubleValue, region[3].doubleValue);
        CGContextAddRect(context, rect);
        CGContextFillPath(context);
    }

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(CF_URL_FOR_TEST(@"out.png"), kUTTypePNG, 1, NULL);

    image = CGBitmapContextCreateImage(context);
    CGImageDestinationAddImage(destination, image, NULL);
    CGImageRelease(image);

    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

@end
