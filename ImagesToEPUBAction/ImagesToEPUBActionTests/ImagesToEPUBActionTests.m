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

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;
    NSURL *workingURL = [_action createWorkingDirectory:&error];

    XCTAssertNotNil(workingURL, @"failed to create working directory: %@", error);

    XCTAssertFalse([[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL]);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:workingURL error:&error], @"%@", error);
}

- (void)testCopyWorkingDirectory {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"Unit Testing";

    [_action loadParameters];

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;

    NSURL *workingURL = [_action createWorkingDirectory:&error];
    XCTAssertNotNil(workingURL, @"failed to create working directory: %@", error);

    NSURL *finalURL = [_action finalizeWorkingDirectory:workingURL error:&error];

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

    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;

    NSURL *workingURL = [_action createWorkingDirectory:&error];
    XCTAssertNotNil(workingURL, @"failed to create working directory: %@", error);

    NSURL *finalURL = [_action finalizeWorkingDirectory:workingURL error:&error];

    XCTAssertEqualObjects(finalURL.absoluteString, outputURL.absoluteString);

    XCTAssertFalse([[NSFileManager defaultManager] removeItemAtURL:workingURL error:NULL]);
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtURL:outputURL error:&error], @"%@", error);
}

/*!
 * This is not a proper test, but more of an exploration into binding progress objects to AMBundleAction instances.
 * Consider it a spike, as it demonstrates the approach used within @c runWithInput:error: in the action.
 */
- (void)testProgressMonitor {
    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];

    [self keyValueObservingExpectationForObject:_action keyPath:@"progressValue" expectedValue:@(0.00)];
    [self keyValueObservingExpectationForObject:_action keyPath:@"progressValue" expectedValue:@(0.25)];
    [self keyValueObservingExpectationForObject:_action keyPath:@"progressValue" expectedValue:@(0.50)];
    [self keyValueObservingExpectationForObject:_action keyPath:@"progressValue" expectedValue:@(1.00)];

    [_action bind:@"progressValue" toObject:progress withKeyPath:@"fractionCompleted" options:nil];

    progress.completedUnitCount += 25;
    progress.completedUnitCount += 25;
    progress.completedUnitCount += 50;

    [self waitForExpectationsWithTimeout:0.0 handler:NULL];
}

- (void)testCopyItems {
    NSURL *tmpDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *outDirectory = [NSURL fileURLWithPath:NSUUID.UUID.UUIDString isDirectory:YES relativeToURL:tmpDirectory];

    NSError * __autoreleasing error = nil;

    XCTAssert([[NSFileManager defaultManager] createDirectoryAtURL:outDirectory withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);

    NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:tmpDirectory];
    NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:tmpDirectory];
    NSURL *file3 = [NSURL fileURLWithPath:@"file56.txt" relativeToURL:tmpDirectory];

    NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path];

    for (NSString *path in paths) {
        XCTAssert([[NSData data] writeToFile:path options:NSDataWritingAtomic error:&error], @"%@", error);
    }

    NSArray<NSDictionary *> *result = [_action copyItemsFromPaths:paths toDirectory:outDirectory error:&error];

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects([result.firstObject valueForKeyPath:@"pages.@count"], @2);
    XCTAssertEqualObjects(([result.firstObject valueForKeyPath:@"pages.lastPathComponent"]), (@[@"im0001.png", @"im0002.jpeg"]));

    XCTAssert([[NSFileManager defaultManager] removeItemAtURL:outDirectory error:&error], @"%@", error);

    for (NSString *path in paths) {
        XCTAssert([[NSFileManager defaultManager] removeItemAtPath:path error:&error], @"%@", error);
    }
}

- (void)testCopyItemsChaptering {
    NSURL *tmpDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *outDirectory = [NSURL fileURLWithPath:NSUUID.UUID.UUIDString isDirectory:YES relativeToURL:tmpDirectory];

    NSError * __autoreleasing error = nil;

    XCTAssert([[NSFileManager defaultManager] createDirectoryAtURL:outDirectory withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);

    NSString *title1 = @"alpha";
    NSString *title2 = @"beta";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    NSArray<NSURL *> *chapters = @[ch1, ch2];

    for (NSURL *url in chapters) {
        [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:NULL];
    }

    NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:ch1];
    NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:ch1];
    NSURL *file3 = [NSURL fileURLWithPath:@"img56.jpg" relativeToURL:ch2];
    NSURL *file4 = [NSURL fileURLWithPath:@"file78.txt" relativeToURL:ch2];

    NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

    for (NSString *path in paths) {
        XCTAssert([[NSData data] writeToFile:path options:NSDataWritingAtomic error:&error], @"%@", error);
    }

    NSArray<NSDictionary *> *result = [_action copyItemsFromPaths:paths toDirectory:outDirectory error:&error];

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 2);
    XCTAssertEqualObjects(([result valueForKeyPath:@"title"]), (@[title1, title2]));
    XCTAssertEqualObjects(([result[0] valueForKeyPath:@"pages.@count"]), @2);
    XCTAssertEqualObjects(([result[0] valueForKeyPath:@"pages.lastPathComponent"]), (@[@"im0001.png", @"im0002.jpeg"]));
    XCTAssertEqualObjects(([result[1] valueForKeyPath:@"pages.@count"]), @1);
    XCTAssertEqualObjects(([result[1] valueForKeyPath:@"pages.lastPathComponent"]), (@[@"im0001.jpeg"]));

    XCTAssert([[NSFileManager defaultManager] removeItemAtURL:outDirectory error:&error], @"%@", error);

    for (NSURL *url in chapters) {
        XCTAssert([[NSFileManager defaultManager] removeItemAtURL:url error:&error], @"%@", error);
    }
}

@end
