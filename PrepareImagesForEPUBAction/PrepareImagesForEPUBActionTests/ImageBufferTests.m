//
//  ImageBufferTests.m
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 12/14/20.
//  Copyright © 2020 Rob Menke. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "PrepareImagesForEPUBAction.h"
#import "ImageBuffer.h"

#include <sys/sysctl.h>

@interface ImageBufferTests : XCTestCase

@property (nonatomic) NSArray<NSURL *> *images;

@end

@implementation ImageBufferTests

- (void)setUp {
    [super setUp];

    NSError * __autoreleasing error;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSURL *actionURL = [bundle URLForResource:@"Prepare Images for EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSBundle *actionBundle = [NSBundle bundleWithURL:actionURL];
    XCTAssertTrue([actionBundle loadAndReturnError:&error], @"error - %@", error);

    NSMutableArray<NSURL *> *images = [NSMutableArray array];

    for (NSUInteger i = 1; i < 100; ++i) {
        NSURL *imageURL = [bundle URLForImageResource:[NSString stringWithFormat:@"image%02lu", (unsigned long)(i)]];
        if (!imageURL) break;
        [images addObject:imageURL];
    }

    _images = images;
}

- (void)tearDown {
    _images = nil;

    [super tearDown];
}

- (void)testLoad {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[0] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);
}

- (void)testFlatten {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[0] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    XCTAssertTrue([buffer flattenAgainstColor:NSColor.purpleColor error:&error], @"error - %@", error);

    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);
}

- (void)testConversion {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[0] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);

    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);
}

- (void)testAlphaCreation {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[1] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);
    XCTAssertTrue([buffer autoAlphaInROI:NSMakeRect(0, 0, buffer.width, buffer.height) error:&error], @"error - %@", error);
    XCTAssertTrue([buffer convertToRGBColorSpaceAndReturnError:&error], @"error - %@", error);

    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);

    output = [NSURL fileURLWithPath:@"~/Desktop/output-mask.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([[buffer extractAlphaChannelAndReturnError:&error] writeToURL:output error:&error], @"error - %@", error);

}

- (void)testAlphaExtraction {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[0] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([[buffer extractAlphaChannelAndReturnError:&error] writeToURL:output error:&error], @"error - %@", error);
}

- (void)testAlphaCreationCleanup {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[1] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);
    XCTAssertTrue([buffer autoAlphaInROI:NSMakeRect(0, 0, buffer.width, buffer.height) error:&error], @"error - %@", error);
    XCTAssertTrue([buffer convertToRGBColorSpaceAndReturnError:&error], @"error - %@", error);

    buffer = [buffer extractAlphaChannelAndReturnError:&error];

    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output-mask.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);

    buffer = [buffer bufferByErodingWithKernelSize:NSMakeSize(3, 3) error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    buffer = [buffer bufferByDilatingWithKernelSize:NSMakeSize(5, 5) error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    buffer = [buffer bufferByErodingWithKernelSize:NSMakeSize(3, 3) error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    output = [NSURL fileURLWithPath:@"~/Desktop/output-closed.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);
}

- (void)testEdgeLocation {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[1] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);
    XCTAssertTrue([buffer autoAlphaInROI:NSMakeRect(0, 0, buffer.width, buffer.height) error:&error], @"error - %@", error);
    XCTAssertTrue([buffer convertToRGBColorSpaceAndReturnError:&error], @"error - %@", error);

    buffer = [buffer extractAlphaChannelAndReturnError:&error];
    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output-mask.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);

    buffer = [[buffer bufferByDilatingWithKernelSize:NSMakeSize(3, 3) error:&error] bufferBySubtractingBuffer:buffer error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    output = [NSURL fileURLWithPath:@"~/Desktop/output-edge.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);
}

- (void)testEdgeLocationROI {
    NSError * __autoreleasing error;

    ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
    buffer = [buffer initWithContentsOfURL:_images[0] error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    NSRect ROI = NSMakeRect(100, 0, buffer.width - 100, buffer.height);

    XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);
    XCTAssertTrue([buffer autoAlphaInROI:ROI error:&error], @"error - %@", error);
    XCTAssertTrue([buffer convertToRGBColorSpaceAndReturnError:&error], @"error - %@", error);

    buffer = [buffer extractAlphaChannelAndReturnError:&error];
    NSURL *output = [NSURL fileURLWithPath:@"~/Desktop/output-mask.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);

    buffer = [[buffer bufferByDilatingWithKernelSize:NSMakeSize(3, 3) error:&error] bufferBySubtractingBuffer:buffer error:&error];
    XCTAssertNotNil(buffer, @"error - %@", error);

    output = [NSURL fileURLWithPath:@"~/Desktop/output-edge.png".stringByExpandingTildeInPath isDirectory:NO];
    XCTAssertTrue([buffer writeToURL:output error:&error], @"error - %@", error);
}

- (void)testSegmentation {
    NSError * __autoreleasing error;

    id rgbColorSpace = CFBridgingRelease(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));

    for (NSURL *url in _images) {
        ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
        buffer = [buffer initWithContentsOfURL:url error:&error];
        XCTAssertNotNil(buffer, @"error - %@", error);

        XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);
        XCTAssertTrue([buffer autoAlphaAndReturnError:&error], @"error - %@", error);
        XCTAssertTrue([buffer convertToRGBColorSpaceAndReturnError:&error], @"error - %@", error);

        buffer = [buffer extractAlphaChannelAndReturnError:&error];
        buffer = [[buffer bufferByDilatingWithKernelSize:NSMakeSize(3, 3) error:&error] bufferBySubtractingBuffer:buffer error:&error];

        NSArray<NSArray<NSNumber *> *> *segments = [buffer segmentsFromBufferWithParameters:nil error:&error];

        CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, (CGColorSpaceRef)rgbColorSpace, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedLast);

        CGImageRef image = [buffer CGImageAndReturnError:&error];
        XCTAssertNotNil((__bridge id)image, @"error - %@", error);

        CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);

        CGImageRelease(image);

        CGContextSetRGBStrokeColor(context, 1.0, 0.0, 0.0, 0.5);
        CGContextSetLineWidth(context, 2.0);

        CGContextTranslateCTM(context, 0, buffer.height);
        CGContextScaleCTM(context, 1.0, -1.0);

        for (NSArray<NSNumber *> *segment in segments) {
            CGFloat x0 = segment[0].doubleValue;
            CGFloat y0 = segment[1].doubleValue;
            CGFloat x1 = segment[2].doubleValue;
            CGFloat y1 = segment[3].doubleValue;

            CGContextMoveToPoint(context, x0, y0);
            CGContextAddLineToPoint(context, x1, y1);
        }

        CGContextStrokePath(context);

        image = CGBitmapContextCreateImage(context);

        NSURL *output = [[[NSURL fileURLWithPath:@"~/Desktop".stringByExpandingTildeInPath isDirectory:YES] URLByAppendingPathComponent:url.lastPathComponent isDirectory:NO].URLByDeletingPathExtension URLByAppendingPathExtension:@"png"];

        NSLog(@"output: %@", output);

        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)output, kUTTypePNG, 1, NULL);
        XCTAssertNotEqual(destination, NULL);

        CGImageDestinationAddImage(destination, image, NULL);
        CGImageDestinationFinalize(destination);

        CFRelease(destination);
        CGImageRelease(image);

        CGContextRelease(context);
    }
}

- (void)testRegions {
    NSError * __autoreleasing error;

    id rgbColorSpace = CFBridgingRelease(CGColorSpaceCreateWithName(kCGColorSpaceSRGB));

    for (NSURL *url in _images) {
        ImageBuffer *buffer = [NSClassFromString(@"ImageBuffer") alloc];
        buffer = [buffer initWithContentsOfURL:url error:&error];
        XCTAssertNotNil(buffer, @"error - %@", error);

        XCTAssertTrue([buffer convertToLabColorSpaceAndReturnError:&error], @"error - %@", error);
        XCTAssertTrue([buffer autoAlphaAndReturnError:&error], @"error - %@", error);
        XCTAssertTrue([buffer convertToRGBColorSpaceAndReturnError:&error], @"error - %@", error);

        buffer = [buffer extractAlphaChannelAndReturnError:&error];
        buffer = [[buffer bufferByDilatingWithKernelSize:NSMakeSize(3, 3) error:&error] bufferBySubtractingBuffer:buffer error:&error];

        NSArray<NSArray<NSNumber *> *> *regions = [buffer regionsFromBufferWithParameters:nil error:&error];

        CGContextRef context = CGBitmapContextCreate(NULL, buffer.width, buffer.height, 8, 0, (CGColorSpaceRef)rgbColorSpace, kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedLast);

        CGImageRef image = [buffer CGImageAndReturnError:&error];
        XCTAssertNotNil((__bridge id)image, @"error - %@", error);

        CGContextDrawImage(context, CGRectMake(0, 0, buffer.width, buffer.height), image);

        CGImageRelease(image);

        CGContextSetRGBStrokeColor(context, 1.0, 0.0, 0.0, 0.5);
        CGContextSetLineWidth(context, 2.0);

        CGContextTranslateCTM(context, 0, buffer.height);
        CGContextScaleCTM(context, 1.0, -1.0);

        for (NSArray<NSNumber *> *region in regions) {
            CGRect rect = CGRectMake(region[0].doubleValue, region[1].doubleValue, region[2].doubleValue, region[3].doubleValue);
            CGContextAddRect(context, rect);
        }

        CGContextStrokePath(context);

        image = CGBitmapContextCreateImage(context);

        NSURL *output = [[[NSURL fileURLWithPath:@"~/Desktop".stringByExpandingTildeInPath isDirectory:YES] URLByAppendingPathComponent:url.lastPathComponent isDirectory:NO].URLByDeletingPathExtension URLByAppendingPathExtension:@"png"];

        NSLog(@"output: %@", output);

        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((CFURLRef)output, kUTTypePNG, 1, NULL);
        XCTAssertNotEqual(destination, NULL);

        CGImageDestinationAddImage(destination, image, NULL);
        CGImageDestinationFinalize(destination);

        CFRelease(destination);
        CGImageRelease(image);

        CGContextRelease(context);
    }
}

@end
