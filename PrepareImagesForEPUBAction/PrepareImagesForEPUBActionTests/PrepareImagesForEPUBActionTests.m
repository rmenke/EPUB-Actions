//
//  PrepareImagesForEPUBActionTests.m
//  PrepareImagesForEPUBActionTests
//
//  Created by Rob Menke on 6/13/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#import "PrepareImagesForEPUBAction.h"

@import XCTest;

NSMutableArray<NSString *> *messages = nil;

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

    _action.parameters[@"ignoreAlpha"] = @YES;

    id result = [_action runWithInput:_images error:&error];

    XCTAssertNotNil(result, @"error - %@", error);
    XCTAssertEqualObjects(result, _images);
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

@end
