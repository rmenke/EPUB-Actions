//
//  OPFPackageDocumentTests.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/16/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import XCTest;

#import "OPFPackageDocument.h"

@interface OPFPackageDocumentTests : XCTestCase

@end

@implementation OPFPackageDocumentTests {
    NSFileManager *fileManager;
    NSURL *packageURL;
}

- (void)setUp {
    [super setUp];

    fileManager  = [NSFileManager defaultManager];

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSURL *actionURL = [bundle URLForResource:@"Images to EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSBundle *actionBundle = [NSBundle bundleWithURL:actionURL];
    XCTAssertNotNil(actionBundle);

    packageURL = [actionBundle URLForResource:@"package" withExtension:@"opf"];
    XCTAssertNotNil(packageURL);
}

- (void)tearDown {
    [super tearDown];
}

- (void)testInit {
    NSError * __autoreleasing error;
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:&error];

    XCTAssertNotNil(package, "%@", error);
}

- (void)testIdentifier {
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];

    XCTAssertEqualObjects(package.identifier, @"");

    package.identifier = @"urn:uuid:8EE125F8-BCA8-4B9A-B418-E9722D77F234";

    XCTAssertEqualObjects(package.identifier, @"urn:uuid:8EE125F8-BCA8-4B9A-B418-E9722D77F234");

    NSArray *array = [package.document nodesForXPath:@"//*:identifier/text()" error:NULL];
    XCTAssertEqualObjects([array[0] stringValue], @"urn:uuid:8EE125F8-BCA8-4B9A-B418-E9722D77F234");
}

- (void)testTitle {
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];

    XCTAssertEqualObjects(package.title, @"");

    package.title = @"The Apes of Wrath";

    XCTAssertEqualObjects(package.title, @"The Apes of Wrath");

    NSArray *array = [package.document nodesForXPath:@"//*:title/text()" error:NULL];
    XCTAssertEqualObjects([array[0] stringValue], @"The Apes of Wrath");
}

- (void)testModified {
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];

    XCTAssertNil(package.modified);

    NSDate *now = [NSDate dateWithTimeIntervalSince1970:time(NULL)];

    package.modified = now;

    XCTAssertEqual(package.modified.timeIntervalSince1970, now.timeIntervalSince1970);
}

- (void)testManifest {
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];
    NSMutableSet<NSString *> *manifest = [package mutableSetValueForKey:@"manifest"];

    [manifest addObjectsFromArray:@[@"ch0001/pg0001.xhtml", @"ch0001/pg0001.xhtml", @"ch0001/pg0002.xhtml", @"ch0002/pg0001.xhtml"]];

    XCTAssertEqualObjects(manifest, ([NSSet setWithObjects:@"contents.css", @"nav.xhtml", @"ch0001/pg0001.xhtml", @"ch0001/pg0002.xhtml", @"ch0002/pg0001.xhtml", nil]));

    [manifest removeObject:@"ch0002/pg0001.xhtml"];
    [manifest removeObject:@"ch0002/pg0001.xhtml"];
    [manifest removeObject:@"ch0002/pg0002.xhtml"];

    XCTAssertEqual([package.document nodesForXPath:@"//*[@href='ch0001/pg0001.xhtml']" error:NULL].count, 1);
    XCTAssertEqual([package.document nodesForXPath:@"//*[@href='ch0001/pg0002.xhtml']" error:NULL].count, 1);
}

- (void)testSpine {
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];
    NSMutableSet<NSString *> *manifest = [package mutableSetValueForKey:@"manifest"];
    NSMutableArray<NSString *> *spine  = [package mutableArrayValueForKey:@"spine"];

    XCTAssertEqual(manifest.count, 2);
    XCTAssertEqual(spine.count, 0);

    [spine addObject:@"ch0001/pg0001.xhtml"];
    [spine addObject:@"ch0001/pg0002.xhtml"];
    [spine addObject:@"ch0002/pg0001.xhtml"];
    [spine insertObject:@"ch0002/pg0000.xhtml" atIndex:(spine.count - 1)];

    XCTAssertEqual(manifest.count, 6);
    XCTAssertEqual(spine.count, 4);

    [manifest removeObject:@"ch0001/pg0002.xhtml"];

    XCTAssertEqual(manifest.count, 5);
    XCTAssertEqual(spine.count, 3);

    [spine removeObject:@"ch0001/pg0001.xhtml"];

    XCTAssertEqual(manifest.count, 5);
    XCTAssertEqual(spine.count, 2);

    XCTAssert([manifest containsObject:@"ch0001/pg0001.xhtml"]);

    [spine addObject:@"ch0003/extra.xhtml"];
    [spine addObject:@"ch0003/extra.xhtml"];
    [spine addObject:@"ch0003/extra.xhtml"];

    XCTAssertEqual(manifest.count, 6);
    XCTAssertEqual(spine.count, 5);

    [manifest removeObject:@"ch0003/extra.xhtml"];

    XCTAssertEqual(manifest.count, 5);
    XCTAssertEqual(spine.count, 2);

    spine[1] = @"ch0004/epilogue.xhtml";

    XCTAssertEqual(manifest.count, 6);
    XCTAssertEqual(spine.count, 2);
}

@end
