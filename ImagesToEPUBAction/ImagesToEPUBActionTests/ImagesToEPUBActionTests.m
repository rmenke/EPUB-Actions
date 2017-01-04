//
//  ImagesToEPUBActionTests.m
//  ImagesToEPUBActionTests
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import XCTest;
@import Automator.AMBundleAction;

@interface ImagesToEPUBActionTests : XCTestCase

@property (strong, nonatomic) AMBundleAction *action;

@end

@implementation ImagesToEPUBActionTests

- (void)setUp {
    [super setUp];

    self.continueAfterFailure = NO;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *actionURL = [bundle URLForResource:@"Images to EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSError * __autoreleasing error;
    _action = [[AMBundleAction alloc] initWithContentsOfURL:actionURL error:&error];
    XCTAssertNotNil(_action, @"Error loading action: %@", error.localizedDescription);
}

- (void)tearDown {
    _action = nil;

    [super tearDown];
}

@end
