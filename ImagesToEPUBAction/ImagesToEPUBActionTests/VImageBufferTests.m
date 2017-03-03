//
//  VImageBufferTests.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/22/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "VImageBuffer.h"

@import XCTest;
@import Accelerate.vImage;
@import ObjectiveC.runtime;
@import simd;

#define CLS(X) objc_getClass(#X)

@interface VImageBufferTests : XCTestCase

@end

@implementation VImageBufferTests {
    NSArray<NSImage *> *images;
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

    NSMutableArray<NSImage *> *foundImages = [NSMutableArray array];

    for (NSUInteger index = 1; index; ++index) {
        NSImage *foundImage = [bundle imageForResource:[NSString stringWithFormat:@"image%02lu", (unsigned long)index]];
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
    CGImageRef imageRef = [images[0] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    NSError * __autoreleasing error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testInitializationFailure {
    NSError * __autoreleasing error = nil;

    NSLog(@"Ignore the following mach_vm_map error; it is expected.");
    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:~0 height:~0 error:&error];
    XCTAssertNil(buffer);
    XCTAssertEqual(error.code, kvImageMemoryAllocationError);
    XCTAssertEqualObjects(error.localizedDescription, @"Memory allocation error");
}

- (void)testEdgeDetection1 {
    NSError * __autoreleasing error;

    const float pixels[][10] = {
        { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
        { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
        { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
        { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
        { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
        { 0, 0, 1, 1, 1, 1, 1, 1, 0, 0 },
        { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    };

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:10 height:10 error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    for (NSUInteger y = 0; y < 10; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        float *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.width; ++x) {
            float expected;

            if (x == 0 || x == 9 || y == 0 || y == 9) expected = 0;
            else if (x <= 2 || x >= 7 || y <= 2 || y >= 7) expected = 1;
            else expected = 0;

            XCTAssertEqualWithAccuracy(row[x], expected, 1E-6, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection2 {
    NSError * __autoreleasing error;

    float pixels[][10] = {
        { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
        { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },
        { 0, 1, 0, 0, 0, 0, 0, 0, 1, 0 },
        { 0, 1, 0, 0, 0, 0, 0, 0, 1, 0 },
        { 0, 1, 0, 0, 0, 0, 0, 0, 1, 0 },
        { 0, 1, 0, 0, 0, 0, 0, 0, 1, 0 },
        { 0, 1, 0, 0, 0, 0, 0, 0, 1, 0 },
        { 0, 1, 0, 0, 0, 0, 0, 0, 1, 0 },
        { 0, 1, 1, 1, 1, 1, 1, 1, 1, 0 },
        { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    };

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:10 height:10 error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    for (NSUInteger y = 0; y < 10; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        float *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.height; ++x) {
            float expected;

            if (x <= 2 || x >= 7) expected = 1;
            else if (y <= 2 || y >= 7) expected = 1;
            else expected = 0;

            XCTAssertEqualWithAccuracy(row[x], expected, 1E-6, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection3 {
    NSError * __autoreleasing error;

    float pixels[][10] = {
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        { 1, 1, 0, 0, 0, 0, 0, 0, 1, 1 },
        { 1, 1, 0, 0, 0, 0, 0, 0, 1, 1 },
        { 1, 1, 0, 0, 0, 0, 0, 0, 1, 1 },
        { 1, 1, 0, 0, 0, 0, 0, 0, 1, 1 },
        { 1, 1, 0, 0, 0, 0, 0, 0, 1, 1 },
        { 1, 1, 0, 0, 0, 0, 0, 0, 1, 1 },
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:10 height:10 error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    for (NSUInteger y = 0; y < 10; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        float *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.height; ++x) {
            float expected;

            if (x == 0 || x == 9 || y == 0 || y == 9) expected = 0;
            else if (x <= 2 || x >= 7 || y <= 2 || y >= 7) expected = 1;
            else expected = 0;

            XCTAssertEqualWithAccuracy(row[x], expected, 1E-6, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection4 {
    NSError * __autoreleasing error;

    float pixels[][10] = {
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        { 1, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        { 1, 0, 1, 1, 1, 1, 1, 1, 0, 1 },
        { 1, 0, 1, 1, 1, 1, 1, 1, 0, 1 },
        { 1, 0, 1, 1, 1, 1, 1, 1, 0, 1 },
        { 1, 0, 1, 1, 1, 1, 1, 1, 0, 1 },
        { 1, 0, 1, 1, 1, 1, 1, 1, 0, 1 },
        { 1, 0, 1, 1, 1, 1, 1, 1, 0, 1 },
        { 1, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
    };

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:10 height:10 error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    for (NSUInteger y = 0; y < 10; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        float *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.height; ++x) {
            float expected;

            if (x <= 2 || x >= 7) expected = 1;
            else if (y <= 2 || y >= 7) expected = 1;
            else expected = 0;

            XCTAssertEqualWithAccuracy(row[x], expected, 1E-6, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetectionWithImage01 {
    CGImageRef imageRef = [images[0] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:YES forBlock:^{
        success = [buffer detectEdgesWithKernelSize:3 error:&error];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage02 {
    CGImageRef imageRef = [images[1] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:YES forBlock:^{
        success = [buffer detectEdgesWithKernelSize:3 error:&error];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage03 {
    CGImageRef imageRef = [images[2] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:YES forBlock:^{
        success = [buffer detectEdgesWithKernelSize:3 error:&error];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage04 {
    CGImageRef imageRef = [images[3] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:YES forBlock:^{
        success = [buffer detectEdgesWithKernelSize:3 error:&error];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage05 {
    CGImageRef imageRef = [images[4] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:YES forBlock:^{
        success = [buffer detectEdgesWithKernelSize:3 error:&error];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testHough {
    NSError * __autoreleasing error;

    float pixels[][10] = {
        { 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 },
        { 1, 0, 0, 1, 0, 0, 0, 0, 0, 0 },
        { 0, 1, 0, 1, 0, 0, 0, 0, 0, 0 },
        { 0, 0, 1, 1, 0, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 1, 0, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 1, 1, 0, 0, 0, 0, 0 },
        { 0, 0, 0, 1, 0, 1, 0, 0, 0, 0 },
        { 0, 0, 0, 1, 0, 0, 1, 0, 0, 0 },
        { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        { 0, 0, 0, 1, 0, 0, 0, 0, 1, 0 },
    };

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:10 height:10 error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    for (NSUInteger y = 0; y < 10; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    const NSUInteger margin = 20;

    VImageBuffer *hough = [buffer houghTransformWithMargin:margin error:&error];
    XCTAssertNotNil(hough, @"%@", error);
}

- (void)testHoughWithImage01 {
    CGImageRef imageRef = [images[0] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    __block VImageBuffer *hough;

    [self measureBlock:^{
        hough = [buffer houghTransformWithMargin:8 error:&error];
    }];

    XCTAssertNotNil(hough, @"%@", error);
}

- (void)testHoughWithImage02 {
    CGImageRef imageRef = [images[1] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    __block VImageBuffer *hough;

    [self measureBlock:^{
        hough = [buffer houghTransformWithMargin:8 error:&error];
    }];

    XCTAssertNotNil(hough, @"%@", error);
}

- (void)testHoughWithImage03 {
    CGImageRef imageRef = [images[2] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    __block VImageBuffer *hough;

    [self measureBlock:^{
        hough = [buffer houghTransformWithMargin:8 error:&error];
    }];

    XCTAssertNotNil(hough, @"%@", error);
}

- (void)testHoughWithImage04 {
    CGImageRef imageRef = [images[3] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    __block VImageBuffer *hough;

    [self measureBlock:^{
        hough = [buffer houghTransformWithMargin:8 error:&error];
    }];

    XCTAssertNotNil(hough, @"%@", error);
}

- (void)testHoughWithImage05 {
    CGImageRef imageRef = [images[4] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    __block VImageBuffer *hough;

    [self measureBlock:^{
        hough = [buffer houghTransformWithMargin:8 error:&error];
    }];

    XCTAssertNotNil(hough, @"%@", error);
}

- (void)testNormalizeContrast {
    float pixels[][5] = {
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

    buffer = [buffer normalizeContrast:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, cols);
    XCTAssertEqual(buffer.height, rows);

    for (NSUInteger y = 0; y < rows; ++y) {
        float *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < cols; ++x) {
            XCTAssertEqual(row[x], pixels[y][x] / 8.0f);
        }
    }
}

- (void)testCreateCGImage {
    float pixels[][5] = {
        { 0, 1, 0, 1, 0 },
        { 1, 1, 1, 1, 1 },
        { 0, 1, 0, 1, 0 },
        { 1, 1, 1, 1, 1 },
        { 0, 1, 0, 1, 0 },
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

    CGImageRef image = [buffer copyCGImage:&error];
    buffer = nil;

    XCTAssertNotEqual(image, NULL, @"returns valid CGImage");

    XCTAssertEqual(rows, CGImageGetHeight(image));
    XCTAssertEqual(cols, CGImageGetWidth(image));

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(NULL, cols, rows, 8, 0, cs, kCGBitmapByteOrderDefault|kCGImageAlphaNone);
    CGColorSpaceRelease(cs);

    CGContextDrawImage(ctx, CGRectMake(0, 0, cols, rows), image);

    for (NSUInteger y = 0; y < rows; ++y) {
        uint8_t *row = CGBitmapContextGetData(ctx) + CGBitmapContextGetBytesPerRow(ctx) * y;
        for (NSUInteger x = 0; x < cols; ++x) {
            XCTAssertEqualWithAccuracy(row[x], pixels[y][x] * 255.0, 1E-4);
        }
    }

    CGContextRelease(ctx);
    CGImageRelease(image);
}

@end
