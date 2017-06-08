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

#define CLS(X) objc_getClass(#X)

#define XCTAssertEqualFileURLs(expression1, expression2, ...) \
    XCTAssertEqualObjects((expression1).URLByStandardizingPath.absoluteString, (expression2).URLByStandardizingPath.absoluteString, ## __VA_ARGS__);

// TODO: Use XCT primitives to produce better diagnostics for this
#define XCTAssertPredicate(OBJECT, FORMAT, ...) ({ \
    __typeof__((OBJECT)) obj = (OBJECT); \
    NSPredicate *pred = [NSPredicate predicateWithFormat:(FORMAT), ## __VA_ARGS__]; \
    XCTAssertTrue([pred evaluateWithObject:obj], @"%@ did not satisfy \"%@\"", obj, pred); \
})

@protocol WhiteBoxTesting

- (nonnull instancetype)initWithTitle:(nonnull NSString *)title wrapper:(nullable NSFileWrapper *)wrapper;

@end

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

@implementation NSString (NSHTMLGeometryExtension)

static NSRegularExpression *expr = NULL;

- (NSDictionary<NSString *, NSString *> *)htmlStyle {
    if (!expr) expr = [NSRegularExpression regularExpressionWithPattern:@"(\\w+)\\s*:\\s*([^;]*[^;\\s])" options:0 error:NULL];

    NSMutableDictionary<NSString *, NSString *> *dictionary = [NSMutableDictionary dictionary];

    [expr enumerateMatchesInString:self options:0 range:NSMakeRange(0, self.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        NSString *name  = [self substringWithRange:[result rangeAtIndex:1]];
        NSString *value = [[self substringWithRange:[result rangeAtIndex:2]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        dictionary[name] = value;
    }];

    return dictionary;
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
        [bundle URLForImageResource:@"image04"],
        [bundle URLForImageResource:@"image05"]
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

- (void)testParameters {
    NSDictionary<NSString *, id> *parameters = [_action parameters];

    objc_property_t *properties = class_copyPropertyList([_action class], NULL);
    for (objc_property_t *p = properties; *p; ++p) {
        NSString *propertyName = @(property_getName(*p));
        if (parameters[propertyName] && ![propertyName isEqualToString:@"backgroundColor"]) {
            XCTAssertEqualObjects([_action valueForKey:propertyName], parameters[propertyName]);
        }
    }
    free(properties);

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(255.00,255.00,255.00,1.0000)");
}

- (void)testParametersWithColor {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = [NSArchiver archivedDataWithRootObject:[NSColor colorWithSRGBRed:1.0 green:0.5 blue:0.5 alpha:1.0]];

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(255.00,127.50,127.50,1.0000)");
}

- (void)testParametersWithColorNonRGBA {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = [NSArchiver archivedDataWithRootObject:[NSColor colorWithWhite:0.5 alpha:1.0]];

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(127.50,127.50,127.50,1.0000)");
}

- (void)testLoadParametersWithColorMissing {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = nil;

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(255.00,255.00,255.00,1.0000)");
}

- (void)testOutputURL {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = @"/foo/bar";
    parameters[@"title"] = @"baz";

    XCTAssertEqualObjects([[_action valueForKey:@"outputURL"] path], @"/foo/bar/baz.epub");
}

- (void)testEPUBOddTitle {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = NSTemporaryDirectory();
    parameters[@"title"] = @"The annoying conjuction: And/Or";

    NSURL *outputURL = [_action valueForKey:@"outputURL"];

    XCTAssertNotEqualObjects(outputURL.lastPathComponent, @"Or.epub", @"expected slash to be removed from path, but got %@", outputURL.absoluteString);

    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"The annoying conjuction: And.Or" options:0 error:NULL];
    XCTAssertEqual([re numberOfMatchesInString:outputURL.lastPathComponent options:NSMatchingAnchored range:NSMakeRange(0, outputURL.lastPathComponent.length)], 1);
    XCTAssertEqualObjects([_action valueForKey:@"title"], @"The annoying conjuction: And/Or");
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

    NSArray<NSFileWrapper *> *result = [_action createChaptersFromPaths:paths error:&error];

    // Verify a warning was created for the ignored file.
    XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file56.txt'");

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects([result valueForKey:@"preferredFilename"], (@[[@"01." stringByAppendingString:tmpDirectory.lastPathComponent.lowercaseString]]));
    XCTAssertEqual(result[0].fileWrappers.count, 2);
    XCTAssertEqualObjects([result[0].fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"im0001.png", @"im0002.jpeg"]));
}

- (void)testCopyItemsChaptering {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

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

    NSArray<NSFileWrapper *> *result = [_action createChaptersFromPaths:paths error:&error];

    // Verify a warning was created for the ignored file.
    XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file78.txt'");

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 2);
    XCTAssertEqualObjects(([result valueForKeyPath:@"preferredFilename"]), (@[@"01.alpha-one", @"02.beta-two"]));
    XCTAssertEqual(result[0].fileWrappers.count, 2);
    XCTAssertEqualObjects([result[0].fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"im0001.png", @"im0002.jpeg"]));
    XCTAssertEqual(result[1].fileWrappers.count, 1);
    XCTAssertEqualObjects([result[1].fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"im0001.jpeg"]));

    for (NSURL *url in chapters) {
        [fileManager removeItemAtURL:url error:NULL];
    }
}

- (void)testCopyItemsCoverImage {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

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

    [_action parameters][@"firstIsCover"] = @YES;

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:0 error:&error];
    XCTAssertNotNil(wrapper, @"%@", error);

    NSArray<NSFileWrapper *> *result = [_action createChaptersFromPaths:paths error:&error];

    XCTAssert([wrapper writeToURL:outDirectory options:NSFileWrapperWritingAtomic originalContentsURL:outDirectory error:&error], @"%@", error);

    // Verify a warning was created for the ignored file.
    XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file78.txt'");

    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 2);
    XCTAssertEqualObjects(([result valueForKeyPath:@"preferredFilename"]), (@[@"01.alpha-one", @"02.beta-two"]));
    XCTAssertEqual(result[0].fileWrappers.count, 1);
    XCTAssertEqualObjects([result[0].fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"im0001.jpeg"]));
    XCTAssertEqual(result[1].fileWrappers.count, 1);
    XCTAssertEqualObjects([result[1].fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"im0001.jpeg"]));

    for (NSURL *url in chapters) {
        XCTAssert([fileManager removeItemAtURL:url error:&error], @"%@", error);
    }
}

- (void)testCreatePages {
    NSError * __autoreleasing error = nil;

    NSFileWrapper *epubWrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:0 error:&error];
    XCTAssertNotNil(epubWrapper, @"%@", error);

    NSFileWrapper *image1 = [[NSFileWrapper alloc] initWithURL:_images[0] options:0 error:&error];
    image1.preferredFilename = @"im0001.png";
    XCTAssertNotNil(image1, @"%@", error);

    NSFileWrapper *image2 = [[NSFileWrapper alloc] initWithURL:_images[1] options:0 error:&error];
    image2.preferredFilename = @"im0002.jpg";
    XCTAssertNotNil(image2, @"%@", error);

    NSFileWrapper *image3 = [[NSFileWrapper alloc] initWithURL:_images[2] options:0 error:&error];
    image3.preferredFilename = @"im0001.gif";
    XCTAssertNotNil(image3, @"%@", error);

    NSFileWrapper *image4 = [[NSFileWrapper alloc] initWithURL:_images[3] options:0 error:&error];
    image4.preferredFilename = @"im0002.png";
    XCTAssertNotNil(image4, @"%@", error);

    NSFileWrapper *ch1 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.png":image1, @"im0002.jpg":image2}];
    NSFileWrapper *ch2 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.gif":image3, @"im0002.png":image4}];

    NSFileWrapper *contentsWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"01.Alpha":ch1, @"02.Beta":ch2}];
    contentsWrapper.preferredFilename = @"Contents";
    [epubWrapper addFileWrapper:contentsWrapper];

    NSArray<NSString *> *result = [_action createPagesForChapters:@[ch1, ch2] error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 3);

    XCTAssert([epubWrapper writeToURL:outDirectory options:NSFileWrapperWritingAtomic originalContentsURL:outDirectory error:&error], @"%@", error);

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:outDirectory includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSArray<NSURL *> *items = [enumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
        return [obj1.absoluteString compare:obj2.absoluteString];
    }];

    XCTAssertEqual(items.count, 10);
    XCTAssertTrue(items[0].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[0], [outDirectory URLByAppendingPathComponent:@"Contents"]);
    XCTAssertTrue(items[1].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[1], [outDirectory URLByAppendingPathComponent:@"Contents/01.Alpha"]);
    XCTAssertTrue(items[4].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[4], [outDirectory URLByAppendingPathComponent:@"Contents/01.Alpha/pg0001.xhtml"]);
    XCTAssertTrue(items[5].isDirectoryOnFileSystem);
    XCTAssertEqualFileURLs(items[5], [outDirectory URLByAppendingPathComponent:@"Contents/02.Beta"]);
    XCTAssertTrue(items[8].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[8], [outDirectory URLByAppendingPathComponent:@"Contents/02.Beta/pg0001.xhtml"]);
    XCTAssertTrue(items[9].isRegularFileOnFileSystem);
    XCTAssertEqualFileURLs(items[9], [outDirectory URLByAppendingPathComponent:@"Contents/02.Beta/pg0002.xhtml"]);

    NSXMLDocument *document;
    NSArray<NSXMLNode *> *nodes;

    document = [[NSXMLDocument alloc] initWithContentsOfURL:items[4] options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    nodes = [document nodesForXPath:@"//img/@src" error:&error];
    XCTAssertNotNil(nodes, @"%@", error);
    XCTAssertEqual(nodes.count, 2);
    XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[@"im0001.png", @"im0002.jpg"]));

    document = [[NSXMLDocument alloc] initWithContentsOfURL:items[8] options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    nodes = [document nodesForXPath:@"//img/@src" error:&error];
    XCTAssertNotNil(nodes, @"%@", error);
    XCTAssertEqual(nodes.count, 1);
    XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[@"im0001.gif"]));

    document = [[NSXMLDocument alloc] initWithContentsOfURL:items[9] options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    nodes = [document nodesForXPath:@"//img/@src" error:&error];
    XCTAssertNotNil(nodes, @"%@", error);
    XCTAssertEqual(nodes.count, 1);
    XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[@"im0002.png"]));
}

- (void)testCreatePagesNoScaling {
    NSError * __autoreleasing error = nil;

    [_action parameters][@"disableUpscaling"] = @YES;

    NSFileWrapper *epubWrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:0 error:&error];
    XCTAssertNotNil(epubWrapper, @"%@", error);

    NSFileWrapper *image1 = [[NSFileWrapper alloc] initWithURL:_images[0] options:0 error:&error];
    image1.preferredFilename = @"im0001.png";
    XCTAssertNotNil(image1, @"%@", error);

    NSFileWrapper *image2 = [[NSFileWrapper alloc] initWithURL:_images[1] options:0 error:&error];
    image2.preferredFilename = @"im0002.jpg";
    XCTAssertNotNil(image2, @"%@", error);

    NSFileWrapper *image3 = [[NSFileWrapper alloc] initWithURL:_images[2] options:0 error:&error];
    image3.preferredFilename = @"im0001.gif";
    XCTAssertNotNil(image3, @"%@", error);

    NSFileWrapper *image4 = [[NSFileWrapper alloc] initWithURL:_images[3] options:0 error:&error];
    image4.preferredFilename = @"im0002.png";
    XCTAssertNotNil(image4, @"%@", error);

    NSFileWrapper *ch1 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.png":image1, @"im0002.jpg":image2}];
    NSFileWrapper *ch2 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.gif":image3, @"im0002.png":image4}];

    NSFileWrapper *contentsWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"01.Alpha":ch1, @"02.Beta":ch2}];
    contentsWrapper.preferredFilename = @"Contents";
    [epubWrapper addFileWrapper:contentsWrapper];

    NSArray *result = [_action createPagesForChapters:@[ch1, ch2] error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 2);
}

- (void)testCreatePagesFixImageExtensions {
    [_action parameters][@"publicationID"] = @"urn:uuid:48E1C7E3-B9D7-43C4-BFBC-FF78E9E50EC4";

    NSError * __autoreleasing error = nil;

    NSFileWrapper *epubWrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:0 error:&error];
    XCTAssertNotNil(epubWrapper, @"%@", error);

    NSFileWrapper *image1 = [[NSFileWrapper alloc] initWithURL:_images[0] options:0 error:&error];
    image1.preferredFilename = @"im0001.bmp";
    XCTAssertNotNil(image1, @"%@", error);

    NSFileWrapper *image2 = [[NSFileWrapper alloc] initWithURL:_images[1] options:0 error:&error];
    image2.preferredFilename = @"im0002.bmp";
    XCTAssertNotNil(image2, @"%@", error);

    NSFileWrapper *image3 = [[NSFileWrapper alloc] initWithURL:_images[2] options:0 error:&error];
    image3.preferredFilename = @"im0001.bmp";
    XCTAssertNotNil(image3, @"%@", error);

    NSFileWrapper *image4 = [[NSFileWrapper alloc] initWithURL:_images[3] options:0 error:&error];
    image4.preferredFilename = @"im0002.bmp";
    XCTAssertNotNil(image4, @"%@", error);

    NSFileWrapper *ch1 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.bmp":image1, @"im0002.bmp":image2}];
    NSFileWrapper *ch2 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.bmp":image3, @"im0002.bmp":image4}];

    NSFileWrapper *contentsWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"01.Alpha":ch1, @"02.Beta":ch2}];
    contentsWrapper.preferredFilename = @"Contents";
    [epubWrapper addFileWrapper:contentsWrapper];

    NSArray *result = [_action createPagesForChapters:@[ch1, ch2] error:&error];
    XCTAssertNotNil(result, @"%@", error);
    XCTAssertEqual(result.count, 3);

    for (NSUInteger ix = 0; ix < 4; ++ix) {
        NSString *extension = @[@"png", @"jpeg", @"gif", @"png"][ix];

        // Verify warnings were created for the incorrect file extensions
        NSString *target = [NSString stringWithFormat:@"im%04lu.%@", (unsigned long)(ix) % 2 + 1, extension];
        XCTAssertPredicate(_messages, @"level[%d] == 2 AND message[%d] CONTAINS %@", ix, ix, target);
    }
}

- (void)testAddMetadata {
    [_action parameters][@"authors"] = @"Bob  Smith (aut) ;; ; Jack Brown  (ill);Bill Jones ";

    NSError * __autoreleasing error;

    NSFileWrapper *epubWrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:0 error:&error];
    XCTAssertNotNil(epubWrapper, @"%@", error);

    NSFileWrapper *contents = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
    contents.preferredFilename = @"Contents";

    [epubWrapper addFileWrapper:contents];

    NSFileWrapper *image1 = [[NSFileWrapper alloc] initWithURL:_images[0] options:0 error:&error];
    image1.preferredFilename = @"im0001.png";
    XCTAssertNotNil(image1, @"%@", error);

    NSFileWrapper *image2 = [[NSFileWrapper alloc] initWithURL:_images[1] options:0 error:&error];
    image2.preferredFilename = @"im0002.jpg";
    XCTAssertNotNil(image2, @"%@", error);

    NSFileWrapper *ch1 = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"im0001.png":image1, @"im0002.jpg":image2}];
    NSFileWrapper *contentsWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"01.Alpha":ch1}];
    NSFileWrapper *metainfoWrapper = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];

    contentsWrapper.preferredFilename = @"Contents";
    [epubWrapper addFileWrapper:contentsWrapper];

    metainfoWrapper.preferredFilename = @"META-INF";
    [epubWrapper addFileWrapper:metainfoWrapper];

    XCTAssertTrue([_action addMetadataToDirectory:epubWrapper chapters:@[ch1] spineItems:@[@"pg01.xhtml"] error:&error], @"%@", error);

    XCTAssert([epubWrapper writeToURL:outDirectory options:NSFileWrapperWritingAtomic originalContentsURL:nil error:&error], @"%@", error);

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

    elements = [package objectsForXQuery:@"for $creator in /package/metadata/*:creator let $display-seq := number(/package/metadata/meta[@refines = concat('#', $creator/@id) and @property = 'display-seq']) order by $display-seq return $creator" error:&error];
    XCTAssertNotNil(elements, @"%@", error);

    XCTAssertEqualObjects(([elements valueForKey:@"stringValue"]), (@[@"Bob Smith", @"Jack Brown", @"Bill Jones"]));
}

- (void)testLayoutDistribute {
    NSError * __autoreleasing error;

    XCTAssertEqual([_action layoutStyle], distributeInternalSpace);

    NSMutableArray *page = [NSMutableArray arrayWithCapacity:2];

    for (NSURL *url in [_images subarrayWithRange:NSMakeRange(0, 2)]) {
        NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:url];
        NSUInteger height = imageRep.pixelsHigh;
        NSUInteger width = imageRep.pixelsWide;

        NSDictionary<NSString *, id> *dictionary = @{@"url":url, @"width":@(width), @"height":@(height)};
        [page addObject:dictionary];
    }

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:NSFileWrapperReadingImmediate error:&error];
    XCTAssertNotNil(wrapper, @"%@", error);

    NSString *path = [_action createPage:page number:1 inDirectory:wrapper error:&error];
    XCTAssertNotNil(path, @"%@", error);

    XCTAssert([wrapper writeToURL:outDirectory options:NSFileWrapperWritingAtomic originalContentsURL:outDirectory error:&error], @"%@", error);

    NSURL *url = [NSURL fileURLWithPath:path relativeToURL:[outDirectory URLByDeletingLastPathComponent]];

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    NSArray<NSDictionary *> *result = [[document objectsForXQuery:@"data(//div[@class='panel-group']/@style)" error:&error] valueForKey:@"htmlStyle"];

    double top = [result[0][@"top"] doubleValue];
    double middleTop = top + [result[0][@"height"] doubleValue];
    double middleBottom = [result[1][@"top"] doubleValue];
    double bottom = middleBottom + [result[1][@"height"] doubleValue];

    XCTAssertGreaterThan(top, 0.0);
    XCTAssertLessThan(middleTop, middleBottom);
    XCTAssertLessThan(bottom, 100.0);
}

- (void)testLayoutMinimize {
    NSError * __autoreleasing error;

    [_action parameters][@"layoutStyle"] = @(minimizeInternalSpace);

    XCTAssertEqual([_action layoutStyle], minimizeInternalSpace);

    NSMutableArray *page = [NSMutableArray arrayWithCapacity:2];

    for (NSURL *url in [_images subarrayWithRange:NSMakeRange(0, 2)]) {
        NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:url];
        NSUInteger height = imageRep.pixelsHigh;
        NSUInteger width = imageRep.pixelsWide;

        NSDictionary<NSString *, id> *dictionary = @{@"url":url, @"width":@(width), @"height":@(height)};
        [page addObject:dictionary];
    }

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:NSFileWrapperReadingImmediate error:&error];
    XCTAssertNotNil(wrapper, @"%@", error);

    NSString *path = [_action createPage:page number:1 inDirectory:wrapper error:&error];
    XCTAssertNotNil(path, @"%@", error);

    XCTAssert([wrapper writeToURL:outDirectory options:NSFileWrapperWritingAtomic originalContentsURL:outDirectory error:&error], @"%@", error);

    NSURL *url = [NSURL fileURLWithPath:path relativeToURL:[outDirectory URLByDeletingLastPathComponent]];

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    NSArray<NSDictionary *> *result = [[document objectsForXQuery:@"data(//div[@class='panel-group']/@style)" error:&error] valueForKey:@"htmlStyle"];

    double top = [result[0][@"top"] doubleValue];
    double middleTop = top + [result[0][@"height"] doubleValue];
    double middleBottom = [result[1][@"top"] doubleValue];
    double bottom = middleBottom + [result[1][@"height"] doubleValue];

    XCTAssertGreaterThan(top, 0.0);
    XCTAssertEqualWithAccuracy(middleTop, middleBottom, 0.001);
    XCTAssertLessThan(bottom, 100.0);
}

- (void)testLayoutMaximize {
    NSError * __autoreleasing error;

    [_action parameters][@"layoutStyle"] = @(maximizeInternalSpace);

    XCTAssertEqual([_action layoutStyle], maximizeInternalSpace);

    NSMutableArray *page = [NSMutableArray arrayWithCapacity:2];

    for (NSURL *url in [_images subarrayWithRange:NSMakeRange(0, 2)]) {
        NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:url];
        NSUInteger height = imageRep.pixelsHigh;
        NSUInteger width = imageRep.pixelsWide;

        NSDictionary<NSString *, id> *dictionary = @{@"url":url, @"width":@(width), @"height":@(height)};
        [page addObject:dictionary];
    }

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:outDirectory options:NSFileWrapperReadingImmediate error:&error];
    XCTAssertNotNil(wrapper, @"%@", error);

    NSString *path = [_action createPage:page number:1 inDirectory:wrapper error:&error];
    XCTAssertNotNil(path, @"%@", error);

    XCTAssert([wrapper writeToURL:outDirectory options:NSFileWrapperWritingAtomic originalContentsURL:outDirectory error:&error], @"%@", error);

    NSURL *url = [NSURL fileURLWithPath:path relativeToURL:[outDirectory URLByDeletingLastPathComponent]];

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
    XCTAssertNotNil(document, @"%@", error);

    NSArray<NSDictionary *> *result = [[document objectsForXQuery:@"data(//div[@class='panel-group']/@style)" error:&error] valueForKey:@"htmlStyle"];

    double top = [result[0][@"top"] doubleValue];
    double middleTop = top + [result[0][@"height"] doubleValue];
    double middleBottom = [result[1][@"top"] doubleValue];
    double bottom = middleBottom + [result[1][@"height"] doubleValue];

    XCTAssertEqualWithAccuracy(top, 0.0, 0.001);
    XCTAssertLessThan(middleTop, middleBottom);
    XCTAssertEqualWithAccuracy(bottom, 100.0, 0.001);
}

- (void)testAction {
    NSError * __autoreleasing error;

    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = outDirectory.URLByDeletingLastPathComponent.path;
    parameters[@"title"] = outDirectory.lastPathComponent;
    parameters[@"authors"] = @"Anonymous";
    parameters[@"publicationID"] = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
    parameters[@"doPanelAnalysis"] = @NO;
    parameters[@"firstIsCover"] = @NO;

    XCTAssert([fileManager removeItemAtURL:outDirectory error:&error], @"%@", error);
    outDirectory = [outDirectory URLByAppendingPathExtension:@"epub"];

    NSMutableArray<NSString *> *input = [NSMutableArray arrayWithCapacity:_images.count];

    for (NSURL *image in _images) {
        [input addObject:image.absoluteURL.path];
    }

    [self measureMetrics:@[XCTPerformanceMetric_WallClockTime] automaticallyStartMeasuring:NO forBlock:^{
        NSError * __autoreleasing error = nil;

        [self startMeasuring];
        NSArray<NSString *> *result = [_action runWithInput:input error:&error];
        [self stopMeasuring];

        XCTAssertNotNil(result, @"%@", error);
        XCTAssertEqualObjects(result[0], outDirectory.path);
    }];
}

@end
