//
//  PrepareImagesForEPUBActionTests.m
//  PrepareImagesForEPUBActionTests
//
//  Created by Rob Menke on 6/13/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#import "PrepareImagesForEPUBAction.h"

@import XCTest;
@import Darwin.POSIX.sys.xattr;

NSMutableArray<NSString *> *messages = nil;

@interface AMBundleAction (WhiteBoxTesting)

- (CGRect)cropRectangle:(CGRect)rectangle;

@end

@interface PrepareImagesForEPUBActionTests : XCTestCase

@property (nonatomic) AMBundleAction *action;
@property (nonatomic) NSArray<NSString *> *images;

@end

@implementation PrepareImagesForEPUBActionTests

- (void)setUp {
    [super setUp];

    NSError * __autoreleasing error;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSURL *actionURL = [bundle URLForResource:@"Prepare Images for EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    _action = [[AMBundleAction alloc] initWithContentsOfURL:actionURL error:&error];
    XCTAssertNotNil(_action, @"Error loading action: %@", error.localizedDescription);
    XCTAssertTrue([[_action bundle] loadAndReturnError:&error], @"error - %@", error);

    XCTAssertNotNil(NSClassFromString(@"PrepareImagesForEPUBAction"));

    NSMutableArray<NSString *> *images = [NSMutableArray array];

    for (NSUInteger i = 1; i < 100; ++i) {
        NSString *imagePath = [bundle pathForImageResource:[NSString stringWithFormat:@"image%02lu", (unsigned long)(i)]];
        if (!imagePath) break;
        [images addObject:imagePath];
    }

    _images = images;
}

- (void)tearDown {
    _images = nil;
    _action = nil;

    [super tearDown];
}

- (void)testRunActionEmpty {
    NSError * __autoreleasing error;
    id result = [_action runWithInput:@[] error:&error];

    XCTAssertEqualObjects(result, @[]);
}

- (void)testRunActionImagesOnly {
    NSError * __autoreleasing error;

    id result = [_action runWithInput:_images error:&error];

    XCTAssertNotNil(result, @"error - %@", error);
    XCTAssertEqualObjects(result, _images);

    for (NSString *path in _images) {
        char buffer[1024];
        size_t bytesRead = getxattr(path.fileSystemRepresentation, EPUB_REGION_XATTR, buffer, sizeof(buffer), 0, 0);
        XCTAssertGreaterThanOrEqual(bytesRead, 0, @"%@", [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
        NSData *data = [NSData dataWithBytesNoCopy:buffer length:bytesRead freeWhenDone:NO];
        id region = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
        XCTAssertNotNil(region, "%@", error);
        XCTAssert([region isKindOfClass:NSArray.class]);
    }
}

- (void)testRunActionBadInputPassthru {
    NSError * __autoreleasing error;
    id result = [_action runWithInput:@[@"/etc/passwd"] error:&error];

    XCTAssertNotNil(result, @"error - %@", error);
    XCTAssertEqualObjects(result, @[@"/etc/passwd"]);
}

- (void)testRunActionBadInputError {
    NSError * __autoreleasing error = nil;
    id result = [_action runWithInput:@[@"/not/a/file/babydoll"] error:&error];

    XCTAssertNil(result, @"unexpected success");
}

- (void)testOpenKernel {
    _action.parameters[@"openKernel"] = @5;
    XCTAssertEqual([[_action valueForKey:@"openKernelSize"] unsignedIntegerValue], 5);
    XCTAssertEqualObjects(_action.parameters[@"openKernel"], @5);

    _action.parameters[@"openKernel"] = @0;
    XCTAssertEqual([[_action valueForKey:@"openKernelSize"] unsignedIntegerValue], 1);
    XCTAssertEqualObjects(_action.parameters[@"openKernel"], @1);

    _action.parameters[@"openKernel"] = @10;
    XCTAssertEqual([[_action valueForKey:@"openKernelSize"] unsignedIntegerValue], 9);
    XCTAssertEqualObjects(_action.parameters[@"openKernel"], @9);

    _action.parameters[@"openKernel"] = @6;
    XCTAssertEqual([[_action valueForKey:@"openKernelSize"] unsignedIntegerValue], 7);
    XCTAssertEqualObjects(_action.parameters[@"openKernel"], @7);
}

- (void)testCropping {
    _action.parameters[@"cropTop"] = @2;
    _action.parameters[@"cropLeft"] = @3;
    _action.parameters[@"cropBottom"] = @4;
    _action.parameters[@"cropRight"] = @5;

    CGRect expected = CGRectMake(3, 2, 92, 94);
    CGRect actual = [_action cropRectangle:CGRectMake(0, 0, 100, 100)];

    XCTAssertTrue(CGRectEqualToRect(expected, actual), @"expected %@ but got %@", NSStringFromRect(expected), NSStringFromRect(actual));
}

@end
