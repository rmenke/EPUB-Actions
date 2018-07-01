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

#define CF_URL_FOR_TEST(FILE) (__bridge CFURLRef)(urlForTest(_cmd, FILE))

@interface VImageBufferTests : XCTestCase

@property (nonatomic, readonly) NSArray<NSURL *> *imageURLs;

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

    XCTAssertEqual(buffer.ROI.origin.x, 0.0);
    XCTAssertEqual(buffer.ROI.origin.y, 0.0);
    XCTAssertEqual(buffer.ROI.size.width, 680.0);
    XCTAssertEqual(buffer.ROI.size.height, 240.0);
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

- (void)testCrop {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[0] error:&error];
    [buffer cropTop:5 bottom:10 left:15 right:20];

    XCTAssertEqual(buffer.width, 680);
    XCTAssertEqual(buffer.height, 240);

    XCTAssertEqual(buffer.ROI.origin.x, 15.0);
    XCTAssertEqual(buffer.ROI.origin.y, 5.0);
    XCTAssertEqual(buffer.ROI.size.width, 645.0);
    XCTAssertEqual(buffer.ROI.size.height, 225.0);
}

- (void)testExtractAlpha {
    NSError * __autoreleasing error = nil;

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:self.imageURLs[0] error:&error];
    __block VImageBuffer *result;

    [self measureBlock:^{
        NSError * __autoreleasing error = nil;
        result = [buffer extractBorderMaskAndReturnError:&error];
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
        result = [buffer extractBorderMaskAndReturnError:&error];
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

- (void)testEdgeDetection {
    NSError * __autoreleasing error = nil;

    for (NSURL *url in self.imageURLs) {
        @autoreleasepool {
            VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:url error:&error];
            XCTAssertNotNil(buffer, @"error - %@", error);

            VImageBuffer *border = [buffer extractBorderMaskAndReturnError:&error];
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

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:_imageURLs[5] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    [buffer cropTop:12 bottom:12 left:12 right:12];

    VImageBuffer *border = [buffer extractBorderMaskAndReturnError:&error];
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

            VImageBuffer *border = [buffer extractBorderMaskAndReturnError:&error];
            XCTAssertNotNil(border, @"error - %@", error);

            XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);
            
            NSArray<NSArray<NSNumber *> *> *segments = [border detectSegmentsAndReturnError:&error];
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

    VImageBuffer *buffer = [[CLS(VImageBuffer) alloc] initWithContentsOfURL:_imageURLs[5] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    [buffer cropTop:12 bottom:12 left:12 right:12];

    VImageBuffer *border = [buffer extractBorderMaskAndReturnError:&error];
    XCTAssertNotNil(border, @"error - %@", error);

    XCTAssert([border detectEdgesAndReturnError:&error], @"error - %@", error);

    NSArray<NSArray<NSNumber *> *> *segments = [border detectSegmentsAndReturnError:&error];
    XCTAssertNotNil(segments, @"error - %@", error);

    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, cs, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(cs);

    CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)_imageURLs[5], NULL);
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

@end
