//
//  ImagesToEPUBActionTests.m
//  ImagesToEPUBActionTests
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#include "ImagesToEPUBAction.h"

@import XCTest;
@import Automator;
@import ObjectiveC.runtime;

#define XCTAssertEqualFileURLs(expression1, expression2, ...) \
    XCTAssertEqualObjects((expression1).URLByStandardizingPath.absoluteString, (expression2).URLByStandardizingPath.absoluteString, ## __VA_ARGS__);

// TODO: Use XCT primitives to produce better diagnostics for this
#define XCTAssertPredicate(OBJECT, FORMAT, ...) ({ \
    __typeof__((OBJECT)) obj = (OBJECT); \
    NSPredicate *pred = [NSPredicate predicateWithFormat:(FORMAT), ## __VA_ARGS__]; \
    XCTAssertTrue([pred evaluateWithObject:obj], @"%@ did not satisfy \"%@\"", obj, pred); \
})

@implementation NSURL (FilePropertyAccess)

- (BOOL)isDirectoryOnFileSystem {
    NSNumber *isDirectory;
    NSError *error;

    if (![self getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]) {
        [NSException raise:NSGenericException format:@"error - %@", error];
    }

    return isDirectory.boolValue;
}

- (BOOL)isRegularFileOnFileSystem {
    NSNumber *isRegularFile;
    NSError *error;

    if (![self getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error]) {
        [NSException raise:NSGenericException format:@"error - %@", error];
    }

    return isRegularFile.boolValue;
}

@end

@interface ImagesToEPUBActionTests : XCTestCase

@property (strong, nonatomic) id action;
@property (strong, nonatomic) NSArray<NSURL *> *images;
@property (strong, nonatomic) NSArray<NSDictionary<NSString *, id> *> *messages;

@end

@implementation ImagesToEPUBActionTests {
    NSFileManager *fileManager;
    NSURL *tmpDirectory;
    NSURL *inDirectory, *outDirectory;
}

- (void)setUp {
    [super setUp];

    NSError * __autoreleasing error;

    fileManager  = [NSFileManager defaultManager];
    tmpDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    inDirectory  = [NSURL fileURLWithPath:NSUUID.UUID.UUIDString isDirectory:YES relativeToURL:tmpDirectory];
    outDirectory = [NSURL fileURLWithPath:NSUUID.UUID.UUIDString isDirectory:YES relativeToURL:tmpDirectory];

    XCTAssert([fileManager createDirectoryAtURL:inDirectory withIntermediateDirectories:YES attributes:nil error:&error]);
    XCTAssert([fileManager createDirectoryAtURL:outDirectory withIntermediateDirectories:YES attributes:nil error:&error]);

    NSBundle *bundle = [NSBundle bundleForClass:self.class];

    NSURL *actionURL = [bundle URLForResource:@"Images to EPUB" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    _action = [[AMBundleAction alloc] initWithContentsOfURL:actionURL error:&error];
    XCTAssertNotNil(_action, @"Error loading action: %@", error.localizedDescription);

    NSMutableArray<NSDictionary<NSString *, id> *> *messages = [NSMutableArray array];

    _messages = messages;

    Class c = [_action class];
    SEL s = @selector(logMessageWithLevel:format:);
    Method m = class_getInstanceMethod(c, s);
    IMP imp = imp_implementationWithBlock(^(id _self, AMLogLevel level, NSString *format, ...) {
        va_list ap;

        va_start(ap, format);
        NSDictionary<NSString *, id> *message = @{@"level":@(level), @"message":[[NSString alloc] initWithFormat:format arguments:ap]};
        va_end(ap);

        [messages addObject:message];
    });

    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));

    _images = @[
        [bundle URLForImageResource:@"image01"],
        [bundle URLForImageResource:@"image02"],
        [bundle URLForImageResource:@"image03"],
        [bundle URLForImageResource:@"image04"]
    ];
}

- (void)tearDown {
    Class c = [_action class];
    SEL s = @selector(logMessageWithLevel:format:);
    Method m = class_getInstanceMethod(c, s);

    class_replaceMethod(c, s, nil, method_getTypeEncoding(m));

    _messages = nil;
    _action = nil;

    NSError * __autoreleasing error;
    XCTAssert([fileManager removeItemAtURL:outDirectory error:&error], @"%@", error);
    XCTAssert([fileManager removeItemAtURL:inDirectory error:&error], @"%@", error);

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

    [fileManager removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;
    NSURL *workingURL = [_action createWorkingDirectory:&error];

    XCTAssertNotNil(workingURL, @"failed to create working directory: %@", error);

    XCTAssertFalse([fileManager removeItemAtURL:outputURL error:NULL]);
    XCTAssertTrue([fileManager removeItemAtURL:workingURL error:&error], @"%@", error);
}

- (void)testCopyWorkingDirectory {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"Unit Testing";

    [_action loadParameters];

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    [fileManager removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;

    NSURL *workingURL = [_action createWorkingDirectory:&error];
    XCTAssertNotNil(workingURL, @"failed to create working directory: %@", error);

    NSURL *finalURL = [_action finalizeWorkingDirectory:workingURL error:&error];

    XCTAssertEqualObjects(finalURL.absoluteString, outputURL.absoluteString);

    XCTAssertFalse([fileManager removeItemAtURL:workingURL error:NULL]);
    XCTAssertTrue([fileManager removeItemAtURL:outputURL error:&error], @"%@", error);
}

- (void)testCreateWorkingDirectoryOddTitle {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"The annoying conjuction: And/Or";

    [_action loadParameters];

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    XCTAssertNotEqualObjects(outputURL.lastPathComponent, @"Or.epub", @"expected slash to be removed from path, but got %@", outputURL.absoluteString);

    [fileManager removeItemAtURL:outputURL error:NULL];

    NSError * __autoreleasing error;

    NSURL *workingURL = [_action createWorkingDirectory:&error];
    XCTAssertNotNil(workingURL, @"failed to create working directory: %@", error);

    NSURL *finalURL = [_action finalizeWorkingDirectory:workingURL error:&error];

    XCTAssertEqualObjects(finalURL.absoluteString, outputURL.absoluteString);

    XCTAssertFalse([fileManager removeItemAtURL:workingURL error:NULL]);
    XCTAssertTrue([fileManager removeItemAtURL:outputURL error:&error], @"%@", error);
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
    NSError * __autoreleasing error = nil;

    NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:tmpDirectory];
    NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:tmpDirectory];
    NSURL *file3 = [NSURL fileURLWithPath:@"file56.txt" relativeToURL:tmpDirectory];

    NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path];

    for (NSString *path in paths) {
        XCTAssert([[NSData data] writeToFile:path options:NSDataWritingAtomic error:&error], @"%@", error);
    }

    NSArray<NSDictionary *> *result = [_action copyItemsFromPaths:paths toDirectory:outDirectory error:&error];

    // Verify all URLs are relative to the Contents subdirectory
    NSArray<NSURL *> *baseURLs = [result valueForKeyPath:@"@distinctUnionOfArrays.images.baseURL"];
    XCTAssertEqual(baseURLs.count, 1, @"expected one base URL");
    NSURL *expected = [outDirectory URLByAppendingPathComponent:@"Contents" isDirectory:YES].URLByStandardizingPath;
    NSURL *actual   = baseURLs.firstObject.URLByStandardizingPath;
    XCTAssertEqualObjects(actual, expected);

    // Verify a warning was created for the ignored file.
    XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file56.txt'");

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects([result.firstObject valueForKeyPath:@"images.@count"], @2);
    XCTAssertEqualObjects(([result.firstObject valueForKeyPath:@"images.lastPathComponent"]), (@[@"im0001.png", @"im0002.jpeg"]));

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:outDirectory includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSArray<NSURL *> *items = [enumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
        return [obj1.absoluteString compare:obj2.absoluteString];
    }];

    XCTAssertEqual(items.count, 4);
    XCTAssertTrue(items[0].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[0], [outDirectory URLByAppendingPathComponent:@"Contents"]);
    XCTAssertTrue(items[1].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[1], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001"]);
    XCTAssertTrue(items[2].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[2], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001/im0001.png"]);
    XCTAssertTrue(items[3].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[3], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001/im0002.jpeg"]);

    for (NSString *path in paths) {
        XCTAssert([fileManager removeItemAtPath:path error:&error], @"%@", error);
    }
}

- (void)testCopyItemsChaptering {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"alpha";
    NSString *title2 = @"beta";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    NSArray<NSURL *> *chapters = @[ch1, ch2];

    for (NSURL *url in chapters) {
        [fileManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:NULL];
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

    // Verify all URLs are relative to the Contents subdirectory
    NSArray<NSURL *> *baseURLs = [result valueForKeyPath:@"@distinctUnionOfArrays.images.baseURL"];
    XCTAssertEqual(baseURLs.count, 1, @"expected one base URL");
    XCTAssertEqualObjects(baseURLs.firstObject.URLByStandardizingPath, [outDirectory URLByAppendingPathComponent:@"Contents" isDirectory:YES].URLByStandardizingPath);

    // Verify a warning was created for the ignored file.
    XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file78.txt'");

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 2);
    XCTAssertEqualObjects(([result valueForKeyPath:@"title"]), (@[title1, title2]));
    XCTAssertEqualObjects(([result[0] valueForKeyPath:@"images.@count"]), @2);
    XCTAssertEqualObjects(([result[0] valueForKeyPath:@"images.lastPathComponent"]), (@[@"im0001.png", @"im0002.jpeg"]));
    XCTAssertEqualObjects(([result[1] valueForKeyPath:@"images.@count"]), @1);
    XCTAssertEqualObjects(([result[1] valueForKeyPath:@"images.lastPathComponent"]), (@[@"im0001.jpeg"]));

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:outDirectory includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSArray<NSURL *> *items = [enumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
        return [obj1.absoluteString compare:obj2.absoluteString];
    }];

    XCTAssertEqual(items.count, 6);
    XCTAssertTrue(items[0].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[0], [outDirectory URLByAppendingPathComponent:@"Contents"]);
    XCTAssertTrue(items[1].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[1], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001"]);
    XCTAssertTrue(items[2].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[2], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001/im0001.png"]);
    XCTAssertTrue(items[3].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[3], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001/im0002.jpeg"]);
    XCTAssertTrue(items[4].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[4], [outDirectory URLByAppendingPathComponent:@"Contents/ch0002"]);
    XCTAssertTrue(items[5].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[5], [outDirectory URLByAppendingPathComponent:@"Contents/ch0002/im0001.jpeg"]);

    for (NSURL *url in chapters) {
        XCTAssert([fileManager removeItemAtURL:url error:&error], @"%@", error);
    }
}

- (void)testCreatePages {
    [_action loadParameters];

    NSURL *contentsURL = [outDirectory URLByAppendingPathComponent:@"Contents" isDirectory:YES];

    NSURL *ch1 = [NSURL fileURLWithPath:@"ch0001" isDirectory:YES relativeToURL:contentsURL];
    NSURL *ch2 = [NSURL fileURLWithPath:@"ch0002" isDirectory:YES relativeToURL:contentsURL];

    NSError * __autoreleasing error = nil;

    XCTAssert([fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    XCTAssert([fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);

    NSArray<NSDictionary<NSString *, id> *> *chapters = @[@{@"title":@"alpha", @"images":@[_images[0], _images[1]], @"url":ch1}, @{@"title":@"beta", @"images":@[_images[2], _images[3]], @"url":ch2}];

    NSArray *result = [_action createChapters:chapters error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 3);

    // Verify all URLs are relative to Contents subdirectory
    NSArray<NSURL *> *baseURLs = [result valueForKeyPath:@"@distinctUnionOfObjects.baseURL"];
    XCTAssertEqual(baseURLs.count, 1, @"expected exactly one base URL");
    XCTAssertEqualObjects(baseURLs.firstObject.URLByStandardizingPath, contentsURL.URLByStandardizingPath);

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:outDirectory includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSArray<NSURL *> *items = [enumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
        return [obj1.absoluteString compare:obj2.absoluteString];
    }];

    XCTAssertEqual(items.count, 6);
    XCTAssertTrue(items[0].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[0], [outDirectory URLByAppendingPathComponent:@"Contents"]);
    XCTAssertTrue(items[1].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[1], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001"]);
    XCTAssertTrue(items[2].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[2], [outDirectory URLByAppendingPathComponent:@"Contents/ch0001/pg0001.xhtml"]);
    XCTAssertTrue(items[3].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[3], [outDirectory URLByAppendingPathComponent:@"Contents/ch0002"]);
    XCTAssertTrue(items[4].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[4], [outDirectory URLByAppendingPathComponent:@"Contents/ch0002/pg0001.xhtml"]);
    XCTAssertTrue(items[5].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[5], [outDirectory URLByAppendingPathComponent:@"Contents/ch0002/pg0002.xhtml"]);

    NSXMLDocument *document;
    NSArray<NSXMLNode *> *nodes;

    document = [[NSXMLDocument alloc] initWithContentsOfURL:items[2] options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    nodes = [document nodesForXPath:@"//img/@src" error:&error];
    XCTAssertNotNil(nodes, @"%@", error);
    XCTAssertEqual(nodes.count, 2);
    XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[_images[0].lastPathComponent, _images[1].lastPathComponent]));

    document = [[NSXMLDocument alloc] initWithContentsOfURL:items[4] options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    nodes = [document nodesForXPath:@"//img/@src" error:&error];
    XCTAssertNotNil(nodes, @"%@", error);
    XCTAssertEqual(nodes.count, 1);
    XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[_images[2].lastPathComponent]));

    document = [[NSXMLDocument alloc] initWithContentsOfURL:items[5] options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    nodes = [document nodesForXPath:@"//img/@src" error:&error];
    XCTAssertNotNil(nodes, @"%@", error);
    XCTAssertEqual(nodes.count, 1);
    XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[_images[3].lastPathComponent]));
}

- (void)testCreatePagesNoScaling {
    [[_action parameters] setObject:@YES forKey:@"disableUpscaling"];

    [_action loadParameters];

    NSURL *ch1 = [NSURL fileURLWithPath:@"ch0001" isDirectory:YES relativeToURL:outDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:@"ch0002" isDirectory:YES relativeToURL:outDirectory];

    NSError * __autoreleasing error = nil;

    XCTAssert([fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    XCTAssert([fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);

    NSArray<NSDictionary<NSString *, id> *> *chapters = @[@{@"title":@"alpha", @"images":@[_images[0], _images[1]], @"url":ch1}, @{@"title":@"beta", @"images":@[_images[2], _images[3]], @"url":ch2}];

    NSArray *result = [_action createChapters:chapters error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 2);
}

- (void)testCreatePagesFixImageExtensions {
    [_action loadParameters];

    NSError * __autoreleasing error = nil;

    XCTAssertEqual(_images.count, 4);
    NSMutableArray<NSURL *> *images = [NSMutableArray arrayWithCapacity:_images.count];

    for (NSURL *url in _images) {
        NSURL *newURL = [[NSURL fileURLWithPath:url.lastPathComponent relativeToURL:inDirectory].URLByDeletingPathExtension URLByAppendingPathExtension:@"bmp"];
        XCTAssert([fileManager copyItemAtURL:url toURL:newURL error:&error], @"%@", error);
        [images addObject:newURL];
    }

    NSURL *ch1 = [NSURL fileURLWithPath:@"ch0001" isDirectory:YES relativeToURL:outDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:@"ch0002" isDirectory:YES relativeToURL:outDirectory];

    XCTAssert([fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    XCTAssert([fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);

    NSArray<NSDictionary<NSString *, id> *> *chapters = @[@{@"title":@"alpha", @"images": @[images[0], images[1]], @"url":ch1}, @{@"title":@"beta", @"images":@[images[2], images[3]], @"url":ch2}];

    NSArray *result = [_action createChapters:chapters error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 3);

    for (NSUInteger ix = 0; ix < 4; ++ix) {
        NSString *extension = @[@"png", @"jpeg", @"gif", @"tiff"][ix];

        // Verify warnings were created for the incorrect file extensions
        NSString *target = [NSString stringWithFormat:@"image%02lu.%@", (unsigned long)(ix + 1), extension];
        XCTAssertPredicate(_messages, @"level[%d] == 2 AND message[%d] CONTAINS %@", ix, ix, target);

        XCTAssertFalse([fileManager removeItemAtURL:images[ix] error:NULL]);
        NSURL *newURL = [images[ix].URLByDeletingPathExtension URLByAppendingPathExtension:extension];
        XCTAssertTrue([fileManager removeItemAtURL:newURL error:&error], @"%@", error);
    }
}

- (void)testAddMetadata {
    [_action loadParameters];

    NSError * __autoreleasing error;

    NSArray<NSDictionary<NSString *, id> *> *chapters = @[@{@"images":@[[NSURL fileURLWithPath:@"img1.gif"], [NSURL fileURLWithPath:@"img2.jpeg"]]}];

    XCTAssertTrue(([_action addMetadataToDirectory:outDirectory chapters:chapters spineItems:@[@"pg01.xhtml"] error:&error]), @"%@", error);

    XCTAssertTrue([outDirectory URLByAppendingPathComponent:@"mimetype"].isRegularFileOnFileSystem);
    XCTAssertTrue([outDirectory URLByAppendingPathComponent:@"META-INF/"].isDirectoryOnFileSystem);
    XCTAssertTrue([outDirectory URLByAppendingPathComponent:@"META-INF/container.xml"].isRegularFileOnFileSystem);
    XCTAssertTrue([outDirectory URLByAppendingPathComponent:@"Contents/package.opf"].isRegularFileOnFileSystem);
    XCTAssertTrue([outDirectory URLByAppendingPathComponent:@"Contents/contents.css"].isRegularFileOnFileSystem);

    NSXMLDocument *package = [[NSXMLDocument alloc] initWithContentsOfURL:[outDirectory URLByAppendingPathComponent:@"Contents/package.opf"] options:0 error:&error];
    XCTAssertNotNil(package, @"%@", error);

    NSArray<NSXMLElement *> *elements = [package nodesForXPath:@"//*:identifier" error:&error];
    XCTAssertNotNil(elements, @"%@", error);
    XCTAssertEqual(elements.count, 1);
    XCTAssertGreaterThan(elements[0].stringValue.length, 0);

    NSArray<NSNumber *> *values = [package objectsForXQuery:@"count(//manifest/item), count(//manifest/item/@media-type)" error:&error];
    XCTAssertNotNil(values, @"%@", error);
    NSUInteger itemsInManifest = values[0].unsignedIntegerValue;
    NSUInteger itemsWithMediaType = values[1].unsignedIntegerValue;
    XCTAssertEqual(itemsInManifest, itemsWithMediaType, @"items in manifest are missing the media-type attribute");
}

- (void)testAction {
    NSError * __autoreleasing error;

    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = outDirectory.URLByDeletingLastPathComponent.path;
    parameters[@"title"] = outDirectory.lastPathComponent;
    parameters[@"authors"] = @"Anonymous";
    parameters[@"publicationID"] = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
    parameters[@"doPanelAnalysis"] = @YES;
    
    XCTAssert([fileManager removeItemAtURL:outDirectory error:&error], @"%@", error);
    outDirectory = [outDirectory URLByAppendingPathExtension:@"epub"];

    NSMutableArray<NSString *> *input = [NSMutableArray arrayWithCapacity:_images.count];

    for (NSURL *image in _images) {
        [input addObject:image.absoluteURL.path];
    }

    NSArray<NSString *> *result = [_action runWithInput:input error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqualObjects(result[0], outDirectory.path);
}

@end
