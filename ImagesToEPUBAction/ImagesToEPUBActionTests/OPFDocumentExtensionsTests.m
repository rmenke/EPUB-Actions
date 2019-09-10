//
//  OPFDocumentExtensionsTests.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 6/12/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import XCTest;

#import "NSXMLDocument+OPFDocumentExtensions.h"

#define NS_OPF @"http://www.idpf.org/2007/opf"
#define NS_DC @"http://purl.org/dc/elements/1.1/"

#define Q(QUERY) @"declare default element namespace \"" NS_OPF "\";\ndeclare namespace dc = \"" NS_DC "\";\n\n" QUERY

@interface OPFDocumentExtensionsTests : XCTestCase

@end

@implementation OPFDocumentExtensionsTests {
    NSXMLDocument *packageDocument;
}

- (void)setUp {
    [super setUp];

    NSError * __autoreleasing error;

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSURL *actionURL = [bundle URLForResource:@"Images to EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSBundle *actionBundle = [NSBundle bundleWithURL:actionURL];
    XCTAssertNotNil(actionBundle);

    XCTAssert([actionBundle loadAndReturnError:&error], @"%@", error);

    NSURL *packageURL = [actionBundle URLForResource:@"package" withExtension:@"opf"];
    XCTAssertNotNil(packageURL);

    packageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:packageURL options:0 error:&error];
    XCTAssertNotNil(packageDocument, @"Error loading document - %@", error);
}

- (void)tearDown {
    packageDocument = nil;

    [super tearDown];
}

- (void)testIdentifier {
    NSError * __autoreleasing error;

    XCTAssertNotNil(packageDocument.identifier);
    XCTAssertEqualObjects(packageDocument.identifier, @"");

    packageDocument.identifier = @"urn:uuid:AFCCD852-14A2-4945-8010-695F9E87F57E";

    XCTAssertEqualObjects(packageDocument.identifier, @"urn:uuid:AFCCD852-14A2-4945-8010-695F9E87F57E");

    NSString *identifier = [packageDocument objectsForXQuery:Q("data(/package/metadata/dc:identifier)") constants:nil error:&error].firstObject;
    XCTAssertNotNil(identifier, @"xquery - %@", error);
    XCTAssertEqualObjects(identifier, @"urn:uuid:AFCCD852-14A2-4945-8010-695F9E87F57E");
}

- (void)testTitle {
    NSError * __autoreleasing error;

    XCTAssertNotNil(packageDocument.title);
    XCTAssertEqualObjects(packageDocument.title, @"");

    packageDocument.title = @"My Great Comic Book";

    XCTAssertEqualObjects(packageDocument.title, @"My Great Comic Book");

    NSString *title = [packageDocument objectsForXQuery:Q("data(/package/metadata/dc:title)") constants:nil error:&error].firstObject;
    XCTAssertNotNil(title, @"xquery - %@", error);
    XCTAssertEqualObjects(title, @"My Great Comic Book");
}

- (void)testSubject {
    NSError * __autoreleasing error;

    XCTAssertNil(packageDocument.subject);

    NSArray<NSString *> *subjects = [packageDocument objectsForXQuery:Q("data(/package/metadata/dc:subject)") constants:nil error:&error];
    XCTAssertNotNil(subjects, @"xquery - %@", error);
    XCTAssertEqualObjects(subjects, @[]);

    packageDocument.subject = @"Test EPUB";
    XCTAssertEqualObjects(packageDocument.subject, @"Test EPUB");

    subjects = [packageDocument objectsForXQuery:Q("data(/package/metadata/dc:subject)") constants:nil error:&error];
    XCTAssertNotNil(subjects, @"xquery - %@", error);
    XCTAssertEqualObjects(subjects, @[@"Test EPUB"]);

    packageDocument.subject = @"Test EPUB 2";
    XCTAssertEqualObjects(packageDocument.subject, @"Test EPUB 2");

    subjects = [packageDocument objectsForXQuery:Q("data(/package/metadata/dc:subject)") constants:nil error:&error];
    XCTAssertNotNil(subjects, @"xquery - %@", error);
    XCTAssertEqualObjects(subjects, @[@"Test EPUB 2"]);

    packageDocument.subject = nil;
    XCTAssertNil(packageDocument.subject);

    subjects = [packageDocument objectsForXQuery:Q("data(/package/metadata/dc:subject)") constants:nil error:&error];
    XCTAssertNotNil(subjects, @"xquery - %@", error);
    XCTAssertEqualObjects(subjects, @[]);
}

- (void)testDate {
    NSError * __autoreleasing error;

    NSDate *date = [NSDate dateWithTimeIntervalSince1970:1497287345.0];

    packageDocument.modified = date;

    XCTAssertEqualObjects(packageDocument.modified, date);

    NSString *identifier = [packageDocument objectsForXQuery:Q("data(/package/metadata/meta[@property='dcterms:modified'])") constants:nil error:&error].firstObject;
    XCTAssertNotNil(identifier, @"xquery - %@", error);
    XCTAssertEqualObjects(identifier, @"2017-06-12T17:09:05Z");
}

- (void)testAddAuthor {
    NSError * __autoreleasing error;

    [packageDocument addCreator:@"Bob Smith" fileAs:nil role:@"aut"];
    [packageDocument addCreator:@"Jane Doe" fileAs:nil role:nil];

    NSArray<NSXMLElement *> *elements = [packageDocument objectsForXQuery:Q("/package/metadata/dc:creator") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 2, @"Expected two creators.");
    XCTAssertEqualObjects(elements[0].stringValue, @"Bob Smith");
    XCTAssertEqualObjects(elements[1].stringValue, @"Jane Doe");

    elements = [packageDocument objectsForXQuery:Q("/package/metadata/meta[@refines='#creator-1']") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 1, @"Expected single refinement of first creator.");

    elements = [packageDocument objectsForXQuery:Q("/package/metadata/meta[@refines='#creator-1' and @property='role']") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 1);
    XCTAssertEqualObjects(elements.firstObject.stringValue, @"aut", @"Expected role of first creator");

    elements = [packageDocument objectsForXQuery:Q("/package/metadata/meta[@refines='#creator-2' and @property='role']") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 0, @"Expected no role of second creator");
}

- (void)testAddManifest {
    NSError * __autoreleasing error;

    [packageDocument addManifestItem:@"foo/foo.xhtml" properties:nil];
    [packageDocument addManifestItem:@"foo/bar.xhtml" properties:nil];
    [packageDocument addManifestItem:@"foo/baz.xhtml" properties:nil];
    [packageDocument addManifestItem:@"cover.png" properties:@"cover-page"];

    NSArray<NSXMLElement *> *elements = [packageDocument objectsForXQuery:Q("/package/manifest/item") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 7);
}

- (void)testAddSpine {
    NSError * __autoreleasing error;

    NSString *ident = [packageDocument addManifestItem:@"foo.xhtml" properties:@"cover-page"];

    NSArray<NSXMLElement *> *elements = [packageDocument objectsForXQuery:Q("/package/manifest/item") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 4);

    [packageDocument addSpineItem:@"foo.xhtml" properties:nil];
    [packageDocument addSpineItem:@"bar.xhtml" properties:@"double-spread"];

    elements = [packageDocument objectsForXQuery:Q("/package/manifest/item") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 5);

    elements = [packageDocument objectsForXQuery:Q("/package/spine/itemref") error:&error];
    XCTAssertNotNil(elements, @"xquery - %@", error);
    XCTAssertEqual(elements.count, 2);

    XCTAssertEqualObjects([elements[0] attributeForName:@"idref"].stringValue, ident);
    XCTAssertNil([elements[0] attributeForName:@"properties"]);
    XCTAssertEqualObjects([elements[1] attributeForName:@"properties"].stringValue, @"double-spread");
}

@end
