//
//  VImageBufferTests.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/22/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "VImageBuffer.h"

@import XCTest;
@import ObjectiveC.runtime;
@import simd;

#define CLS(X) objc_getClass(#X)

void __CGImageWriteDebug(CGImageRef image, NSString *fileName) {
    NSError * __autoreleasing error;

    NSURL *url = [[NSFileManager defaultManager] URLForDirectory:NSDesktopDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error];
    if (url == nil) @throw [NSException exceptionWithName:NSGenericException reason:error.localizedDescription userInfo:nil];

    url = [NSURL fileURLWithPath:fileName isDirectory:NO relativeToURL:url];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)(url), kUTTypePNG, 1, NULL);
    if (destination == NULL) @throw [NSException exceptionWithName:NSGenericException reason:@"CGImageDestinationCreateWithURL() failed" userInfo:nil];
    CGImageDestinationAddImage(destination, image, (CFDictionaryRef)@{(NSString *)(kCGImagePropertyHasAlpha):@YES});
    CGImageDestinationFinalize(destination);
    CFRelease(destination);
}

#define CGImageWriteDebug(IMAGE, ...) __CGImageWriteDebug((IMAGE),[NSString stringWithFormat:@"%s%s.png", sel_getName(_cmd), (#__VA_ARGS__)]);

#define VImageBufferWriteDebug(BUFFER, ...) do { \
    CGImageRef image = [(BUFFER) copyCGImageAndReturnError:NULL]; \
    CGImageWriteDebug(image, ## __VA_ARGS__); \
    CGImageRelease(image); \
} while (0)

@interface VImageBufferTests : XCTestCase

@end

@implementation VImageBufferTests {
    NSArray<NSURL *> *images;
}

- (void)setUp {
    [super setUp];

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSError * __autoreleasing error;

    NSURL *actionURL = [bundle URLForResource:@"Images to EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSBundle *actionBundle = [NSBundle bundleWithURL:actionURL];
    XCTAssertNotNil(actionBundle);

    XCTAssert([actionBundle loadAndReturnError:&error], @"%@", error);

    NSMutableArray<NSURL *> *foundImages = [NSMutableArray array];

    for (NSUInteger index = 1; index; ++index) {
        NSURL *foundImage = [bundle URLForImageResource:[NSString stringWithFormat:@"image%02lu", (unsigned long)index]];
        if (!foundImage) break;
        [foundImages addObject:foundImage];
    }

    images = foundImages;
}

- (void)tearDown {
    images = nil;

    [super tearDown];
}

- (void)testInitialization {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[0]];
    XCTAssertNotNil(image);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testInitializationNoBackground {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[0]];
    XCTAssertNotNil(image);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testInitializationGrayBackground {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[0]];
    XCTAssertNotNil(image);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testInitializationFailure {
    NSError * __autoreleasing error = nil;

    NSLog(@"Ignore the following mach_vm_map error; it is expected.");
    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:~0 height:~0 error:&error];
    XCTAssertNil(buffer);
    XCTAssertEqualObjects(error.localizedDescription, @"Memory allocation error");
}

- (void)testHough {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { B, B, B, W, B, B, B, B, B, B },
        { W, B, B, W, B, B, B, B, B, B },
        { B, W, B, W, B, B, B, B, B, B },
        { B, B, W, W, B, B, B, B, B, B },
        { B, B, B, W, B, B, B, B, B, B },
        { B, B, B, W, W, B, B, B, B, B },
        { B, B, B, W, B, W, B, B, B, B },
        { B, B, B, W, B, B, W, B, B, B },
        { W, W, W, W, W, W, W, W, W, W },
        { B, B, B, W, B, B, B, B, W, B },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    NSArray<NSArray<NSNumber *> *> *lines = [buffer findSegmentsWithSignificance:1E-4 error:&error];
    XCTAssertNotNil(lines, @"%@", error);
}

- (CGImageRef)createImageWithImage:(CGImageRef)image segments:(NSArray<NSArray<NSNumber *> *> *)segments  {
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(colorSpace);

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), image);

    CGContextTranslateCTM(ctx, 0, height);
    CGContextScaleCTM(ctx, 1, -1);

    for (NSArray<NSNumber *> *segment in segments) {
        double x0 = segment[0].doubleValue;
        double y0 = segment[1].doubleValue;
        double x1 = segment[2].doubleValue;
        double y1 = segment[3].doubleValue;

        CGContextMoveToPoint(ctx, x0, y0);
        CGContextAddLineToPoint(ctx, x1, y1);
    }

    CGContextSetRGBStrokeColor(ctx, 1, 0, 0, 1);
    CGContextStrokePath(ctx);

    for (NSArray<NSNumber *> *segment in segments) {
        double x0 = segment[0].doubleValue;
        double y0 = segment[1].doubleValue;
        double x1 = segment[2].doubleValue;
        double y1 = segment[3].doubleValue;

        CGContextAddEllipseInRect(ctx, CGRectMake(x0 - 3, y0 - 3, 6, 6));
        CGContextAddEllipseInRect(ctx, CGRectMake(x1 - 3, y1 - 3, 6, 6));
    }

    CGContextSetRGBFillColor(ctx, 0, 0, 1, 1);
    CGContextFillPath(ctx);

    image = CGBitmapContextCreateImage(ctx);

    CGContextRelease(ctx);

    return image;
}

- (void)testHoughWithImage01 {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[0]];

    CIColor *backgroundColor = [[CIColor alloc] initWithColor:[NSColor whiteColor]];

    CGRect extent = image.extent;

    image = [image imageByCompositingOverImage:[CIImage imageWithColor:backgroundColor]];
    image = [image imageByApplyingFilter:@"CIEdges" withInputParameters:nil];
    image = [image imageByApplyingFilter:@"CIMaximumComponent" withInputParameters:nil];
    image = [image imageByCroppingToRect:extent];

    XCTAssertNotNil(image, @"image filter chain failed");

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block NSArray<NSArray<NSNumber *> *> *segments;

    [self measureMetrics:XCTestCase.defaultPerformanceMetrics automaticallyStartMeasuring:NO forBlock:^{
        NSError * __autoreleasing error;

        [self startMeasuring];
        segments = [buffer findSegmentsWithSignificance:1E-15 error:&error];
        [self stopMeasuring];

        XCTAssertNotNil(segments, @"%@", error);
    }];

    CGImageRef imageRef = [buffer copyCGImageAndReturnError:&error];
    CGImageRef result = [self createImageWithImage:imageRef segments:segments];
    CGImageRelease(imageRef);

    CGImageWriteDebug(result);
    CGImageRelease(result);
}

- (void)testHoughWithImage02 {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[1]];

    CIColor *backgroundColor = [[CIColor alloc] initWithColor:[NSColor whiteColor]];

    CGRect extent = image.extent;

    image = [image imageByCompositingOverImage:[CIImage imageWithColor:backgroundColor]];
    image = [image imageByApplyingFilter:@"CIEdges" withInputParameters:nil];
    image = [image imageByApplyingFilter:@"CIMaximumComponent" withInputParameters:nil];
    image = [image imageByCroppingToRect:extent];

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block NSArray<NSArray<NSNumber *> *> *segments;

    [self measureMetrics:XCTestCase.defaultPerformanceMetrics automaticallyStartMeasuring:NO forBlock:^{
        NSError * __autoreleasing error;

        [self startMeasuring];
        segments = [buffer findSegmentsWithSignificance:1E-15 error:&error];
        [self stopMeasuring];

        XCTAssertNotNil(segments, @"%@", error);
    }];

    CGImageRef imageRef = [buffer copyCGImageAndReturnError:&error];
    CGImageRef result = [self createImageWithImage:imageRef segments:segments];
    CGImageRelease(imageRef);

    CGImageWriteDebug(result);
    CGImageRelease(result);
}

- (void)testHoughWithImage03 {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[2]];

    CIColor *backgroundColor = [[CIColor alloc] initWithColor:[NSColor whiteColor]];

    CGRect extent = image.extent;

    image = [image imageByCompositingOverImage:[CIImage imageWithColor:backgroundColor]];
    image = [image imageByApplyingFilter:@"CIEdges" withInputParameters:nil];
    image = [image imageByApplyingFilter:@"CIMaximumComponent" withInputParameters:nil];
    image = [image imageByCroppingToRect:extent];

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block NSArray<NSArray<NSNumber *> *> *segments;

    [self measureMetrics:XCTestCase.defaultPerformanceMetrics automaticallyStartMeasuring:NO forBlock:^{
        NSError * __autoreleasing error;

        [self startMeasuring];
        segments = [buffer findSegmentsWithSignificance:1E-15 error:&error];
        [self stopMeasuring];

        XCTAssertNotNil(segments, @"%@", error);
    }];

    CGImageRef imageRef = [buffer copyCGImageAndReturnError:&error];
    CGImageRef result = [self createImageWithImage:imageRef segments:segments];
    CGImageRelease(imageRef);

    CGImageWriteDebug(result);
    CGImageRelease(result);
}

- (void)testHoughWithImage04 {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[3]];

    CIColor *backgroundColor = [[CIColor alloc] initWithColor:[NSColor whiteColor]];

    CGRect extent = image.extent;

    image = [image imageByCompositingOverImage:[CIImage imageWithColor:backgroundColor]];
    image = [image imageByApplyingFilter:@"CIEdges" withInputParameters:nil];
    image = [image imageByApplyingFilter:@"CIMaximumComponent" withInputParameters:nil];
    image = [image imageByCroppingToRect:extent];

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block NSArray<NSArray<NSNumber *> *> *segments;

    [self measureMetrics:XCTestCase.defaultPerformanceMetrics automaticallyStartMeasuring:NO forBlock:^{
        NSError * __autoreleasing error;

        [self startMeasuring];
        segments = [buffer findSegmentsWithSignificance:1E-15 error:&error];
        [self stopMeasuring];

        XCTAssertNotNil(segments, @"%@", error);
    }];

    CGImageRef imageRef = [buffer copyCGImageAndReturnError:&error];
    CGImageRef result = [self createImageWithImage:imageRef segments:segments];
    CGImageRelease(imageRef);

    CGImageWriteDebug(result);
    CGImageRelease(result);
}

- (void)testHoughWithImage05 {
    NSError * __autoreleasing error;

    CIImage *image = [CIImage imageWithContentsOfURL:images[4]];

    CIColor *backgroundColor = [[CIColor alloc] initWithColor:[NSColor whiteColor]];

    CGRect extent = image.extent;

    image = [image imageByCompositingOverImage:[CIImage imageWithColor:backgroundColor]];
    image = [image imageByApplyingFilter:@"CIEdges" withInputParameters:nil];
    image = [image imageByApplyingFilter:@"CIMaximumComponent" withInputParameters:nil];
    image = [image imageByCroppingToRect:extent];

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithCIImage:image error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block NSArray<NSArray<NSNumber *> *> *segments;

    [self measureMetrics:XCTestCase.defaultPerformanceMetrics automaticallyStartMeasuring:NO forBlock:^{
        NSError * __autoreleasing error;

        [self startMeasuring];
        segments = [buffer findSegmentsWithSignificance:1E-15 error:&error];
        [self stopMeasuring];

        XCTAssertNotNil(segments, @"%@", error);
    }];

    CGImageRef imageRef = [buffer copyCGImageAndReturnError:&error];
    CGImageRef result = [self createImageWithImage:imageRef segments:segments];
    CGImageRelease(imageRef);

    CGImageWriteDebug(result);
    CGImageRelease(result);
}

- (void)testNormalizeContrast {
    uint8_t pixels[][5] = {
        { 8, 3, 3, 8, 5 },
        { 1, 0, 0, 7, 7 },
        { 2, 5, 0, 7, 1 },
        { 6, 6, 1, 1, 0 },
        { 8, 1, 6, 3, 4 },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    NSError * __autoreleasing error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    buffer = [buffer normalizeContrastAndReturnError:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, cols);
    XCTAssertEqual(buffer.height, rows);

    for (NSUInteger y = 0; y < rows; ++y) {
        uint8_t *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < cols; ++x) {
            unsigned actual = row[x];
            unsigned expected = (float)pixels[y][x] / 8.0f * 255;

            XCTAssertEqual(actual, expected);
        }
    }
}

- (void)testCreateCGImage {
    uint8_t pixels[5][5];

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    for (NSUInteger y = 0; y < rows; ++y) {
        for (NSUInteger x = 0; x < cols; ++x) {
            pixels[y][x] = random() & 1 ? UINT8_C(0) : UINT8_C(255);
        }
    }

    NSError * __autoreleasing error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    CGImageRef image = [buffer copyCGImageAndReturnError:&error];

    XCTAssertNotEqual(image, NULL, @"returns valid CGImage");

    XCTAssertEqual(rows, CGImageGetHeight(image));
    XCTAssertEqual(cols, CGImageGetWidth(image));

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, cols, rows, 8, 0, cs, kCGBitmapByteOrderDefault|kCGImageAlphaNone);
    CGColorSpaceRelease(cs);

    CGContextDrawImage(ctx, CGRectMake(0, 0, cols, rows), image);

    for (unsigned y = 0; y < rows; ++y) {
        uint8_t *row = CGBitmapContextGetData(ctx) + CGBitmapContextGetBytesPerRow(ctx) * y;
        for (unsigned x = 0; x < cols; ++x) {
            unsigned expected = pixels[y][x];
            unsigned actual = row[x];
            XCTAssertEqual(actual, expected, "row %u, col %u", y, x);
        }
    }

    CGContextRelease(ctx);
    CGImageRelease(image);
}

@end
