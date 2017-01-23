//
//  ImagesToEPUBActionTests.m
//  ImagesToEPUBActionTests
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#include "ImagesToEPUBAction.h"

@import XCTest;
@import Automator.AMBundleAction;
@import ObjectiveC.runtime;

@interface ImagesToEPUBActionTests : XCTestCase

@property (strong, nonatomic) id action;

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

- (void)testLoadParametersFailure {
    [[_action parameters] removeAllObjects];

    NSLog(@"The following assertion failure is expected:");
    XCTAssertThrows([_action loadParameters]);
}

- (void)testLoadParameters {
    XCTAssertNoThrow([_action loadParameters]);

    NSDictionary<NSString *, id> *parameters = [_action parameters];

    objc_property_t *properties = class_copyPropertyList([_action class], NULL);
    for (objc_property_t *p = properties; *p; ++p) {
        NSString *propertyName = @(property_getName(*p));
        if (parameters[propertyName]) {
            XCTAssertEqualObjects([_action valueForKey:propertyName], parameters[propertyName]);
        }
    }
    free(properties);

    XCTAssertEqualObjects([_action valueForKey:@"pageColor"], @"#ffffff");
}

- (void)testLoadParametersWithColor {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = [NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedRed:1.0 green:0.5 blue:0.5 alpha:1.0]];

    XCTAssertNoThrow([_action loadParameters]);

    objc_property_t *properties = class_copyPropertyList([_action class], NULL);
    for (objc_property_t *p = properties; *p; ++p) {
        NSString *propertyName = @(property_getName(*p));
        if (parameters[propertyName]) {
            XCTAssertEqualObjects([_action valueForKey:propertyName], parameters[propertyName]);
        }
    }
    free(properties);

    XCTAssertEqualObjects([_action valueForKey:@"pageColor"], @"#ff7f7f");
}

- (void)testLoadParametersWithColorNonRGBA {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = [NSArchiver archivedDataWithRootObject:[NSColor colorWithCalibratedWhite:0.5 alpha:1.0]];

    XCTAssertNoThrow([_action loadParameters]);

    objc_property_t *properties = class_copyPropertyList([_action class], NULL);
    for (objc_property_t *p = properties; *p; ++p) {
        NSString *propertyName = @(property_getName(*p));
        if (parameters[propertyName]) {
            XCTAssertEqualObjects([_action valueForKey:propertyName], parameters[propertyName]);
        }
    }
    free(properties);

    XCTAssertEqualObjects([_action valueForKey:@"pageColor"], @"#7f7f7f");
}

- (void)testLoadParametersWithColorMissing {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = nil;

    XCTAssertNoThrow([_action loadParameters]);

    objc_property_t *properties = class_copyPropertyList([_action class], NULL);
    for (objc_property_t *p = properties; *p; ++p) {
        NSString *propertyName = @(property_getName(*p));
        if (parameters[propertyName]) {
            XCTAssertEqualObjects([_action valueForKey:propertyName], parameters[propertyName]);
        }
    }
    free(properties);

    XCTAssertEqualObjects([_action valueForKey:@"pageColor"], @"#ffffff");
}

- (void)testBadOutputFolder {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = @"/foo/bar";
    parameters[@"title"] = @"baz";

    [_action loadParameters];

    XCTAssertEqualObjects([[_action valueForKey:@"outputURL"] path], @"/foo/bar/baz.epub");
}

- (void)testCreateWorkingDirectory {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"Unit Testing";

    [_action loadParameters];

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    XCTAssertNil([_action valueForKey:@"workingURL"]);

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;
    XCTAssert([_action createWorkingDirectory:&error], @"failed to create working directory: %@", error);

    NSURL *workingURL = [_action valueForKey:@"workingURL"];

    XCTAssertNotNil(workingURL);

    XCTAssertFalse([[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL]);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:workingURL error:&error], @"%@", error);
}

- (void)testCopyWorkingDirectory {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"Unit Testing";

    [_action loadParameters];

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    XCTAssertNil([_action valueForKey:@"workingURL"]);

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;
    XCTAssert([_action createWorkingDirectory:&error], @"failed to create working directory: %@", error);

    NSURL *workingURL = [_action valueForKey:@"workingURL"];

    NSURL *finalURL = [_action copyTemporaryToOutput:&error];

    XCTAssertEqualObjects(finalURL.absoluteString, outputURL.absoluteString);

    XCTAssertFalse([[NSFileManager defaultManager] removeItemAtURL:workingURL error:NULL]);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error], @"%@", error);
}

- (void)testCreateWorkingDirectoryOddTitle {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"The annoying conjuction: And/Or";

    [_action loadParameters];

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    XCTAssertNotEqualObjects(outputURL.lastPathComponent, @"Or.epub", @"expected slash to be removed from path, but got %@", outputURL.absoluteString);

    XCTAssertNil([_action valueForKey:@"workingURL"]);

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;
    XCTAssert([_action createWorkingDirectory:&error], @"failed to create working directory: %@", error);

    NSURL *workingURL = [_action valueForKey:@"workingURL"];

    NSURL *finalURL = [_action copyTemporaryToOutput:&error];

    XCTAssertEqualObjects(finalURL.absoluteString, outputURL.absoluteString);

    XCTAssertFalse([[NSFileManager defaultManager] removeItemAtURL:workingURL error:NULL]);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error], @"%@", error);
}

@end
