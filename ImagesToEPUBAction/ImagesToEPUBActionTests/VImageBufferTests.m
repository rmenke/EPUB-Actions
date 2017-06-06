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

#define CGImageWriteDebug(IMAGE, ...) do { \
    NSError * __autoreleasing error; \
    NSURL *url = [[NSFileManager defaultManager] URLForDirectory:NSDesktopDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:&error]; \
    if (url == nil) @throw [NSException exceptionWithName:NSGenericException reason:error.localizedDescription userInfo:nil]; \
    url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%s%s.png", sel_getName(_cmd), (#__VA_ARGS__)] isDirectory:NO relativeToURL:url]; \
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)(url), kUTTypePNG, 1, NULL); \
    if (destination == NULL) @throw [NSException exceptionWithName:NSGenericException reason:@"CGImageDestinationCreateWithURL() failed" userInfo:nil]; \
    CGImageDestinationAddImage(destination, (IMAGE), (CFDictionaryRef)@{(NSString *)(kCGImagePropertyHasAlpha):@YES}); \
    CGImageDestinationFinalize(destination); \
    CFRelease(destination); \
} while (0)

#define VImageBufferWriteDebug(BUFFER, ...) do { \
    CGImageRef image = [(BUFFER) copyCGImageAndReturnError:NULL]; \
    CGImageWriteDebug(image, ## __VA_ARGS__); \
    CGImageRelease(image); \
} while (0)

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

- (void)testInitializationNoBackground {
    CGImageRef imageRef = [images[0] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    NSError * __autoreleasing error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:nil error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);
}

- (void)testInitializationGrayBackground {
    CGImageRef imageRef = [images[0] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    NSError * __autoreleasing error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor grayColor] error:&error];
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

- (void)testMinimize {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, B, B, B, B, B, B, B, B },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    VImageBuffer *minimum = [buffer minimizeWithKernelSize:3 error:&error];
    XCTAssertNotNil(minimum, @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = minimum.data + minimum.bytesPerRow * y;

        for (NSUInteger x = 0; x < buffer.width; ++x) {
            unsigned actual   = row[x];
            unsigned expected = (x > 2 && x < 7 && y > 2 && y < 7) ? W : B;

            XCTAssertEqual(actual, expected, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testMaximize {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, B, B, B, B, B, B, B, B },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    VImageBuffer *maximum = [buffer maximizeWithKernelSize:3 error:&error];
    XCTAssertNotNil(maximum, @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = maximum.data + maximum.bytesPerRow * y;

        for (NSUInteger x = 0; x < buffer.width; ++x) {
            unsigned actual   = row[x];
            unsigned expected = (x > 0 && x < 9 && y > 0 && y < 9) ? W : B;

            XCTAssertEqual(actual, expected, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection1 {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, W, W, W, W, W, W, B, B },
        { B, B, B, B, B, B, B, B, B, B },
        { B, B, B, B, B, B, B, B, B, B },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = buffer.data + buffer.bytesPerRow * y;

        for (NSUInteger x = 0; x < buffer.width; ++x) {
            unsigned actual = row[x];
            unsigned expected =
                x == 0 || x == 9 || y == 0 || y == 9 ? B :
                x == 1 || x == 8 || y == 1 || y == 8 ? W : B;

            XCTAssertEqual(actual, expected, "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection2 {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { W, W, W, W, W, W, W, W, W, W },
        { W, B, B, B, B, B, B, B, B, W },
        { W, B, W, W, W, W, W, W, B, W },
        { W, B, W, W, W, W, W, W, B, W },
        { W, B, W, W, W, W, W, W, B, W },
        { W, B, W, W, W, W, W, W, B, W },
        { W, B, W, W, W, W, W, W, B, W },
        { W, B, W, W, W, W, W, W, B, W },
        { W, B, B, B, B, B, B, B, B, W },
        { W, W, W, W, W, W, W, W, W, W },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.height; ++x) {
            uint8_t expected =
            x == 0 || x == 9 || y == 0 || y == 9 ? B :
            x == 1 || x == 8 || y == 1 || y == 8 ? W : B;

            XCTAssertEqual((unsigned)(row[x]), (unsigned)(expected), "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection3 {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, B, B, B, B, B, B, W, W },
        { W, W, B, B, B, B, B, B, W, W },
        { W, W, B, B, B, B, B, B, W, W },
        { W, W, B, B, B, B, B, B, W, W },
        { W, W, B, B, B, B, B, B, W, W },
        { W, W, B, B, B, B, B, B, W, W },
        { W, W, W, W, W, W, W, W, W, W },
        { W, W, W, W, W, W, W, W, W, W },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.height; ++x) {
            uint8_t expected =
                x < 2 || x > 7 || y < 2 || y > 7 ? B :
                x == 2 || x == 7 || y == 2 || y == 7 ? W : B;

            XCTAssertEqual((unsigned)(row[x]), (unsigned)(expected), "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetection4 {
    NSError * __autoreleasing error;

    const uint8_t B =  0;
    const uint8_t W = ~0;

    const uint8_t pixels[][10] = {
        { B, B, B, B, B, B, B, B, B, B },
        { B, W, W, W, W, W, W, W, W, B },
        { B, W, B, B, B, B, B, B, W, B },
        { B, W, B, B, B, B, B, B, W, B },
        { B, W, B, B, B, B, B, B, W, B },
        { B, W, B, B, B, B, B, B, W, B },
        { B, W, B, B, B, B, B, B, W, B },
        { B, W, B, B, B, B, B, B, W, B },
        { B, W, W, W, W, W, W, W, W, B },
        { B, B, B, B, B, B, B, B, B, B },
    };

    const NSUInteger rows = sizeof(pixels) / sizeof(pixels[0]);
    const NSUInteger cols = sizeof(pixels[0]) / sizeof(pixels[0][0]);

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithWidth:cols height:rows error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    XCTAssertGreaterThanOrEqual(buffer.bytesPerRow, sizeof(pixels[0]));

    for (NSUInteger y = 0; y < rows; ++y) {
        memcpy(buffer.data + buffer.bytesPerRow * y, pixels[y], sizeof(pixels[0]));
    }

    XCTAssert([buffer detectEdgesWithKernelSize:3 error:&error], @"%@", error);

    for (NSUInteger y = 0; y < buffer.height; ++y) {
        uint8_t *row = buffer.data + buffer.bytesPerRow * y;
        for (NSUInteger x = 0; x < buffer.height; ++x) {
            uint8_t expected =
                x == 0 || x == 9 || y == 0 || y == 9 ? W :
                x == 1 || x == 8 || y == 1 || y == 8 ? B :
                x == 2 || x == 7 || y == 2 || y == 7 ? W : B;

            XCTAssertEqual((unsigned)(row[x]), (unsigned)(expected), "row %lu, col %lu", (unsigned long)y, (unsigned long)x);
        }
    }
}

- (void)testEdgeDetectionWithImage01 {
    CGImageRef imageRef = [images[0] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block VImageBuffer *edges;

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{
        edges = buffer.copy;
        [self startMeasuring];
        success = [edges detectEdgesWithKernelSize:3 error:&error];
        [self stopMeasuring];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage02 {
    CGImageRef imageRef = [images[1] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block VImageBuffer *edges;

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{
        edges = buffer.copy;
        [self startMeasuring];
        success = [edges detectEdgesWithKernelSize:3 error:&error];
        [self stopMeasuring];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage03 {
    CGImageRef imageRef = [images[2] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block VImageBuffer *edges;

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{
        edges = buffer.copy;
        [self startMeasuring];
        success = [edges detectEdgesWithKernelSize:3 error:&error];
        [self stopMeasuring];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage04 {
    CGImageRef imageRef = [images[3] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block VImageBuffer *edges;

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{
        edges = buffer.copy;
        [self startMeasuring];
        success = [edges detectEdgesWithKernelSize:3 error:&error];
        [self stopMeasuring];
    }];

    XCTAssertTrue(success, @"%@", error);
}

- (void)testEdgeDetectionWithImage05 {
    CGImageRef imageRef = [images[4] CGImageForProposedRect:NULL context:NULL hints:NULL];
    XCTAssertNotEqual(imageRef, NULL);

    __block NSError *error;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithImage:imageRef backgroundColor:[NSColor whiteColor] error:&error];
    XCTAssertNotNil(buffer, @"%@", error);

    __block VImageBuffer *edges;

    __block BOOL success;

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{
        edges = buffer.copy;
        [self startMeasuring];
        success = [edges detectEdgesWithKernelSize:3 error:&error];
        [self stopMeasuring];
    }];

    XCTAssertTrue(success, @"%@", error);
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

    NSArray<NSValue *> *lines = [buffer findSegmentsAndReturnError:&error];
    XCTAssertNotNil(lines, @"%@", error);
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
