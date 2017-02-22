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

    XCTAssertThrows(spine[999]);
}

- (void)testProperties {
    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];
    NSMutableSet<NSString *> *manifest = [package mutableSetValueForKey:@"manifest"];
    NSMutableArray<NSString *> *spine  = [package mutableArrayValueForKey:@"spine"];

    XCTAssertEqualObjects([package propertiesForManifest:@"nav.xhtml"], @"nav");
    XCTAssertNil([package propertiesForManifest:@"contents.css"]);
    XCTAssertNil([package propertiesForManifest:@"random.object"]);

    [manifest addObject:@"ch0001/pg0001.xhtml"];

    [package setProperties:@"first-page" forManifest:@"ch0001/pg0001.xhtml"];

    NSError * __autoreleasing error;

    NSArray *result = [package.document objectsForXQuery:@"string(//manifest/item[@href='ch0001/pg0001.xhtml']/@properties)" error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqualObjects(result, @[@"first-page"]);

    // NOTE: not a mistake
    [spine addObjectsFromArray:@[@"page1.xhtml", @"page2.xhtml", @"page2.xhtml"]];

    [package setProperties:@"first-copy" forSpineAtIndex:1];
    [package setProperties:@"second-copy" forSpineAtIndex:2];

    result = [package.document objectsForXQuery:@"//spine/itemref" error:&error];
    NSArray<NSArray<NSString *> *> *names = [result valueForKeyPath:@"attributes.name"];
    XCTAssertEqual(names.count, 3);

    XCTAssertFalse([names[0] containsObject:@"properties"]);
    XCTAssertTrue([names[1] containsObject:@"properties"]);
    XCTAssertTrue([names[2] containsObject:@"properties"]);

    NSArray<NSArray<NSString *> *> *values = [result valueForKeyPath:@"attributes.stringValue"];
    XCTAssertEqual(values.count, 3);

    NSDictionary *dictionary;

    dictionary = [NSDictionary dictionaryWithObjects:values[1] forKeys:names[1]];
    XCTAssertEqual(dictionary[@"properties"], @"first-copy");

    dictionary = [NSDictionary dictionaryWithObjects:values[2] forKeys:names[2]];
    XCTAssertEqual(dictionary[@"properties"], @"second-copy");

    result = [package.document objectsForXQuery:@"count(//manifest/item[@href='page1.xhtml']/@properties)" error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqualObjects(result, @[@0]);

    result = [package.document objectsForXQuery:@"count(//manifest/item[@href='page2.xhtml']/@properties)" error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqualObjects(result, @[@0]);
}

- (void)testAuthors {
    NSError * __autoreleasing error;

    OPFPackageDocument *package = [[OPFPackageDocument alloc] initWithContentsOfURL:packageURL error:NULL];
    NSMutableArray<NSString *> *authors = [package mutableArrayValueForKey:@"authors"];

    XCTAssertNotNil(authors);
    XCTAssertEqual(authors.count, 0);

    NSData *data = [@"<elements xmlns:dc='http://purl.org/dc/elements/1.1/'><dc:creator id='creator-2'>Jack Brown</dc:creator><meta refines='#creator-2' property='role' scheme='marc:relators'>ill</meta><meta refines='#creator-2' property='display-seq'>2</meta><dc:creator id='creator-3'>Jack Brown</dc:creator><meta refines='#creator-3' property='display-seq'>3</meta><dc:creator id='creator-1'>Bob Smith</dc:creator><meta refines='#creator-1' property='role' scheme='marc:relators'>aut</meta><meta refines='#creator-1' property='display-seq'>1</meta></elements>" dataUsingEncoding:NSUTF8StringEncoding];

    NSXMLDocument *fragment = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
    XCTAssertNotNil(fragment, @"xml - %@", error);

    NSXMLElement *metadataElement = [package.document.rootElement elementsForName:@"metadata"].firstObject;

    for (NSXMLElement *element in fragment.rootElement.children) {
        [element detach];
        [metadataElement addChild:element];
    }

    XCTAssertEqual(authors.count, 3);
    XCTAssertEqualObjects(authors[0], @"Bob Smith");
    XCTAssertEqualObjects(authors[1], @"Jack Brown");
    XCTAssertEqualObjects(authors[2], @"Jack Brown");

    XCTAssertEqualObjects([package roleForAuthorAtIndex:0], @"aut");
    XCTAssertEqualObjects([package roleForAuthorAtIndex:1], @"ill");
    XCTAssertEqualObjects([package roleForAuthorAtIndex:2], nil);

    authors[0] = @"John Doe";

    XCTAssertEqualObjects(authors[0], @"John Doe");
    XCTAssertEqualObjects(authors[1], @"Jack Brown");
    XCTAssertEqualObjects(authors[2], @"Jack Brown");

    XCTAssertEqualObjects([package roleForAuthorAtIndex:0], nil);
    [package setRole:@"ann" forAuthorAtIndex:0];
    XCTAssertEqualObjects([package roleForAuthorAtIndex:0], @"ann");
    [package setRole:@"aut" forAuthorAtIndex:0];
    XCTAssertEqualObjects([package roleForAuthorAtIndex:0], @"aut");

    XCTAssertEqual(authors.count, 3);

    [authors removeObject:@"Jack Brown"];

    XCTAssertEqual(authors.count, 1);

    XCTAssertThrows(authors[5]);
}

@end

