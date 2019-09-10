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
@import Darwin.POSIX.sys.xattr;

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

@implementation NSURL (ExtendedFileAttributeExtension)

- (BOOL)setData:(NSData *)data forAttribute:(NSString *)attribute error:(NSError **)error {
    if (setxattr(self.fileSystemRepresentation, attribute.UTF8String, data.bytes, data.length, 0, 0) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSURLErrorKey:self}];
        return NO;
    }
    return YES;
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

    XCTAssert([_images[0] setData:[@"((20,20,200,200),(240,20,200,200),(460,20,200,200))" dataUsingEncoding:NSUTF8StringEncoding] forAttribute:@(EPUB_REGION_XATTR) error:&error], @"%@", error);
    XCTAssert([_images[1] setData:[@"((20,20,200,200),(240,20,200,90),(240,130,200,90),(460,20,200,200))" dataUsingEncoding:NSUTF8StringEncoding] forAttribute:@(EPUB_REGION_XATTR) error:&error], @"%@", error);
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

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(255,255,255,1.00)");
}

- (void)testParametersWithColor {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = [NSArchiver archivedDataWithRootObject:[NSColor colorWithSRGBRed:1.0 green:0.5 blue:0.5 alpha:1.0]];

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(255,127,128,1.00)");
}

- (void)testParametersWithColorNonRGBA {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = [NSArchiver archivedDataWithRootObject:[NSColor colorWithWhite:0.5 alpha:1.0]];

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(128,128,128,1.00)");
}

- (void)testLoadParametersWithColorMissing {
    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"backgroundColor"] = nil;

    XCTAssertEqualObjects([_action valueForKeyPath:@"backgroundColor.webColor"], @"rgba(255,255,255,1.00)");
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

    [fileManager removeItemAtURL:file1 error:NULL];
    [fileManager removeItemAtURL:file2 error:NULL];
    [fileManager removeItemAtURL:file3 error:NULL];

    @try {
        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([@"not an image" writeToURL:file3 atomically:YES encoding:NSASCIIStringEncoding error:&error], "%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path];

        XCTAssert([_action prepareDestinationDirectoryForURL:outDirectory error:&error], @"%@", error);

        NSDictionary<NSString *, NSArray<Frame *> *> *result = [_action createChaptersFromPaths:paths error:&error];

        XCTAssertNotNil(result, @"%@", error);
        XCTAssertEqual(result.count, 1);
        XCTAssertEqualObjects(result.allKeys, (@[[@"01." stringByAppendingString:tmpDirectory.lastPathComponent.lowercaseString]]));
        XCTAssertEqual(result.allValues.firstObject.count, 2);
        XCTAssertEqualObjects([result.allValues.firstObject valueForKey:@"name"], (@[@"im0001.png", @"im0002.jpeg"]));

        // Verify a warning was created for the ignored file.
        XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file56.txt'");
    }
    @finally {
        [fileManager removeItemAtURL:file1 error:NULL];
        [fileManager removeItemAtURL:file2 error:NULL];
        [fileManager removeItemAtURL:file3 error:NULL];
    }
}

- (void)testCopyItemsChaptering {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    [fileManager removeItemAtURL:ch1 error:NULL];
    [fileManager removeItemAtURL:ch2 error:NULL];

    [fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:NULL];

    @try {
        NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:ch1];
        NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:ch1];
        NSURL *file3 = [NSURL fileURLWithPath:@"img56.jpg" relativeToURL:ch2];
        NSURL *file4 = [NSURL fileURLWithPath:@"file78.txt" relativeToURL:ch2];

        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file3 error:&error], "%@", error);
        XCTAssert([@"not an image" writeToURL:file4 atomically:YES encoding:NSASCIIStringEncoding error:&error], "%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

        XCTAssert([_action prepareDestinationDirectoryForURL:outDirectory error:&error], @"%@", error);

        NSDictionary<NSString *, NSArray<Frame *> *> *result = [_action createChaptersFromPaths:paths error:&error];

        XCTAssertNotNil(result, @"%@", error);
        XCTAssertEqual(result.count, 2);
        XCTAssertEqualObjects([result.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"01.alpha-one", @"02.beta-two"]));
        XCTAssertEqual(result[@"01.alpha-one"].count, 2);
        XCTAssertEqualObjects([result[@"01.alpha-one"] valueForKey:@"name"], (@[@"im0001.png", @"im0002.jpeg"]));
        XCTAssertEqual(result[@"02.beta-two"].count, 1);
        XCTAssertEqualObjects([result[@"02.beta-two"] valueForKey:@"name"], (@[@"im0001.jpeg"]));

        // Verify a warning was created for the ignored file.
        XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file78.txt'");
    }
    @finally {
        [fileManager removeItemAtURL:ch1 error:NULL];
        [fileManager removeItemAtURL:ch2 error:NULL];
    }
}

- (void)testCopyItemsChapteringWithColon {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha: One";
    NSString *title2 = @"Beta  Two";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    [fileManager removeItemAtURL:ch1 error:NULL];
    [fileManager removeItemAtURL:ch2 error:NULL];

    [fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:NULL];

    @try {
        NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:ch1];
        NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:ch1];
        NSURL *file3 = [NSURL fileURLWithPath:@"img56.jpg" relativeToURL:ch2];
        NSURL *file4 = [NSURL fileURLWithPath:@"file78.txt" relativeToURL:ch2];

        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file3 error:&error], "%@", error);
        XCTAssert([@"not an image" writeToURL:file4 atomically:YES encoding:NSASCIIStringEncoding error:&error], "%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

        XCTAssert([_action prepareDestinationDirectoryForURL:outDirectory error:&error], @"%@", error);

        NSDictionary<NSString *, NSArray<Frame *> *> *result = [_action createChaptersFromPaths:paths error:&error];

        XCTAssertNotNil(result, @"%@", error);
        XCTAssertEqual(result.count, 2);
        XCTAssertEqualObjects([result.allKeys sortedArrayUsingSelector:@selector(compare:)], (@[@"01.alpha-one", @"02.beta-two"]));
        XCTAssertEqual(result[@"01.alpha-one"].count, 2);
        XCTAssertEqualObjects([result[@"01.alpha-one"] valueForKey:@"name"], (@[@"im0001.png", @"im0002.jpeg"]));
        XCTAssertEqual(result[@"02.beta-two"].count, 1);
        XCTAssertEqualObjects([result[@"02.beta-two"] valueForKey:@"name"], (@[@"im0001.jpeg"]));

        // Verify a warning was created for the ignored file.
        XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file78.txt'");
    }
    @finally {
        [fileManager removeItemAtURL:ch1 error:NULL];
        [fileManager removeItemAtURL:ch2 error:NULL];
    }
}

- (void)testCopyItemsCoverImage {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    [fileManager removeItemAtURL:ch1 error:NULL];
    [fileManager removeItemAtURL:ch2 error:NULL];

    [fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:NULL];

    @try {
        NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:ch1];
        NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:ch1];
        NSURL *file3 = [NSURL fileURLWithPath:@"img56.jpg" relativeToURL:ch2];
        NSURL *file4 = [NSURL fileURLWithPath:@"file78.txt" relativeToURL:ch2];

        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file3 error:&error], "%@", error);
        XCTAssert([@"not an image" writeToURL:file4 atomically:YES encoding:NSASCIIStringEncoding error:&error], "%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

        [_action parameters][@"firstIsCover"] = @YES;
        XCTAssert([_action prepareDestinationDirectoryForURL:outDirectory error:&error], @"%@", error);

        NSDictionary<NSString *, NSArray<Frame *> *> *result = [_action createChaptersFromPaths:paths error:&error];

        XCTAssertNotNil(result, @"%@", error);
        XCTAssertEqual(result.count, 2);
        XCTAssertEqualObjects(([result allKeys]), (@[@"01.alpha-one", @"02.beta-two"]));
        XCTAssertEqualObjects([result[@"01.alpha-one"] valueForKey:@"name"], @[@"im0001.jpeg"]);
        XCTAssertEqualObjects([result[@"02.beta-two"] valueForKey:@"name"], @[@"im0001.jpeg"]);

        // Verify a warning was created for the ignored file.
        XCTAssertPredicate(_messages, @"ANY message CONTAINS 'file78.txt'");
    }
    @finally {
        [fileManager removeItemAtURL:ch1 error:NULL];
        [fileManager removeItemAtURL:ch2 error:NULL];
    }
}

- (void)testCopyItemsFixImageExtensions {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    [fileManager removeItemAtURL:ch1 error:NULL];
    [fileManager removeItemAtURL:ch2 error:NULL];

    [fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:NULL];
    [fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:NULL];

    @try {
        NSURL *file1 = [NSURL fileURLWithPath:@"img12.bmp" relativeToURL:ch1];
        NSURL *file2 = [NSURL fileURLWithPath:@"img34.bmp" relativeToURL:ch1];
        NSURL *file3 = [NSURL fileURLWithPath:@"img56.bmp" relativeToURL:ch2];
        NSURL *file4 = [NSURL fileURLWithPath:@"img78.bmp" relativeToURL:ch2];

        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[2] toURL:file3 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[3] toURL:file4 error:&error], "%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

        XCTAssert([_action prepareDestinationDirectoryForURL:outDirectory error:&error], @"%@", error);

        NSDictionary<NSString *, NSArray<Frame *> *> *result = [_action createChaptersFromPaths:paths error:&error];

        XCTAssertNotNil(result, @"%@", error);
        XCTAssertEqual(result.count, 2);
        XCTAssertEqualObjects(([result allKeys]), (@[@"01.alpha-one", @"02.beta-two"]));
        XCTAssertEqualObjects([result[@"01.alpha-one"] valueForKey:@"name"], (@[@"im0001.png", @"im0002.jpeg"]));
        XCTAssertEqualObjects([result[@"02.beta-two"] valueForKey:@"name"], (@[@"im0001.gif", @"im0002.png"]));

        for (NSUInteger ix = 0; ix < 4; ++ix) {
            NSString *extension = @[@"png", @"jpeg", @"gif", @"png"][ix];

            // Verify warnings were created for the incorrect file extensions
            XCTAssertPredicate(_messages, @"level[%d] == 2 AND message[%d] CONTAINS %@", ix, ix, extension);
        }
    }
    @finally {
        [fileManager removeItemAtURL:ch1 error:NULL];
        [fileManager removeItemAtURL:ch2 error:NULL];
    }
}

- (void)testCreatePages {
    NSError * __autoreleasing error = nil;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    NSURL *destinationURL = nil;

    [fileManager removeItemAtURL:ch1 error:NULL];
    [fileManager removeItemAtURL:ch2 error:NULL];

    @try {
        [fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:NULL];
        [fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:NULL];

        NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:ch1];
        NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:ch1];
        NSURL *file3 = [NSURL fileURLWithPath:@"img56.gif" relativeToURL:ch2];
        NSURL *file4 = [NSURL fileURLWithPath:@"img78.png" relativeToURL:ch2];

        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[2] toURL:file3 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[3] toURL:file4 error:&error], "%@", error);

        destinationURL = [_action prepareDestinationDirectoryForURL:outDirectory error:&error];
        XCTAssertNotNil(destinationURL, @"%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

        id frames = [_action createChaptersFromPaths:paths error:&error];
        XCTAssertNotNil(frames, "%@", error);

        XCTAssertTrue(([_action createPagesForChapters:frames error:&error]), @"%@", error);

        NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:destinationURL includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        NSArray<NSURL *> *items = [enumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
            return [obj1.absoluteString compare:obj2.absoluteString];
        }];

        XCTAssertEqual(items.count, 14);
        XCTAssertTrue(items[0].isDirectoryOnFileSystem);
        XCTAssertEqualFileURLs(items[0], [destinationURL URLByAppendingPathComponent:@"Contents"]);
        XCTAssertTrue(items[1].isDirectoryOnFileSystem);
        XCTAssertEqualFileURLs(items[1], [destinationURL URLByAppendingPathComponent:@"Contents/01.alpha-one"]);
        XCTAssertTrue(items[4].isRegularFileOnFileSystem);
        XCTAssertEqualFileURLs(items[4], [destinationURL URLByAppendingPathComponent:@"Contents/01.alpha-one/pg0001.xhtml"]);
        XCTAssertTrue(items[5].isDirectoryOnFileSystem);
        XCTAssertEqualFileURLs(items[5], [destinationURL URLByAppendingPathComponent:@"Contents/02.beta-two"]);
        XCTAssertTrue(items[8].isRegularFileOnFileSystem);
        XCTAssertEqualFileURLs(items[8], [destinationURL URLByAppendingPathComponent:@"Contents/02.beta-two/pg0001.xhtml"]);
        XCTAssertTrue(items[9].isRegularFileOnFileSystem);
        XCTAssertEqualFileURLs(items[9], [destinationURL URLByAppendingPathComponent:@"Contents/02.beta-two/pg0002.xhtml"]);

        NSXMLDocument *document;
        NSArray<NSXMLNode *> *nodes;

        document = [[NSXMLDocument alloc] initWithContentsOfURL:items[4] options:0 error:&error];
        XCTAssertNotNil(document, @"%@", error);

        nodes = [document nodesForXPath:@"//img/@src" error:&error];
        XCTAssertNotNil(nodes, @"%@", error);
        XCTAssertEqual(nodes.count, 2);
        XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[@"im0001.png", @"im0002.jpeg"]));

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
    @finally {
        [fileManager removeItemAtURL:ch1 error:NULL];
        [fileManager removeItemAtURL:ch2 error:NULL];
        if (destinationURL) [fileManager removeItemAtURL:destinationURL error:NULL];
    }
}

- (void)testCreatePagesNoScaling {
    NSError * __autoreleasing error = nil;

    [_action parameters][@"disableUpscaling"] = @YES;

    NSString *title1 = @"Alpha One";
    NSString *title2 = @"Beta  Two";

    NSURL *ch1 = [NSURL fileURLWithPath:title1 isDirectory:YES relativeToURL:tmpDirectory];
    NSURL *ch2 = [NSURL fileURLWithPath:title2 isDirectory:YES relativeToURL:tmpDirectory];

    NSURL *destinationURL = nil;

    [fileManager removeItemAtURL:ch1 error:NULL];
    [fileManager removeItemAtURL:ch2 error:NULL];

    @try {
        [fileManager createDirectoryAtURL:ch1 withIntermediateDirectories:YES attributes:nil error:NULL];
        [fileManager createDirectoryAtURL:ch2 withIntermediateDirectories:YES attributes:nil error:NULL];

        NSURL *file1 = [NSURL fileURLWithPath:@"img12.png" relativeToURL:ch1];
        NSURL *file2 = [NSURL fileURLWithPath:@"img34.jpg" relativeToURL:ch1];
        NSURL *file3 = [NSURL fileURLWithPath:@"img56.gif" relativeToURL:ch2];
        NSURL *file4 = [NSURL fileURLWithPath:@"img78.png" relativeToURL:ch2];

        XCTAssert([fileManager copyItemAtURL:_images[0] toURL:file1 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[1] toURL:file2 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[2] toURL:file3 error:&error], "%@", error);
        XCTAssert([fileManager copyItemAtURL:_images[3] toURL:file4 error:&error], "%@", error);

        destinationURL = [_action prepareDestinationDirectoryForURL:outDirectory error:&error];
        XCTAssertNotNil(destinationURL, @"%@", error);

        NSArray<NSString *> *paths = @[file1.path, file2.path, file3.path, file4.path];

        id frames = [_action createChaptersFromPaths:paths error:&error];
        XCTAssertNotNil(frames, "%@", error);

        XCTAssertTrue(([_action createPagesForChapters:frames error:&error]), @"%@", error);

        NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:destinationURL includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
        NSArray<NSURL *> *items = [enumerator.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSURL *obj1, NSURL *obj2) {
            return [obj1.absoluteString compare:obj2.absoluteString];
        }];

        XCTAssertEqual(items.count, 13);
        XCTAssertTrue(items[0].isDirectoryOnFileSystem);
        XCTAssertEqualFileURLs(items[0], [destinationURL URLByAppendingPathComponent:@"Contents"]);
        XCTAssertTrue(items[1].isDirectoryOnFileSystem);
        XCTAssertEqualFileURLs(items[1], [destinationURL URLByAppendingPathComponent:@"Contents/01.alpha-one"]);
        XCTAssertTrue(items[4].isRegularFileOnFileSystem);
        XCTAssertEqualFileURLs(items[4], [destinationURL URLByAppendingPathComponent:@"Contents/01.alpha-one/pg0001.xhtml"]);
        XCTAssertTrue(items[5].isDirectoryOnFileSystem);
        XCTAssertEqualFileURLs(items[5], [destinationURL URLByAppendingPathComponent:@"Contents/02.beta-two"]);
        XCTAssertTrue(items[8].isRegularFileOnFileSystem);
        XCTAssertEqualFileURLs(items[8], [destinationURL URLByAppendingPathComponent:@"Contents/02.beta-two/pg0001.xhtml"]);

        NSXMLDocument *document;
        NSArray<NSXMLNode *> *nodes;

        document = [[NSXMLDocument alloc] initWithContentsOfURL:items[4] options:0 error:&error];
        XCTAssertNotNil(document, @"%@", error);

        nodes = [document nodesForXPath:@"//img/@src" error:&error];
        XCTAssertNotNil(nodes, @"%@", error);
        XCTAssertEqual(nodes.count, 2);
        XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[@"im0001.png", @"im0002.jpeg"]));

        document = [[NSXMLDocument alloc] initWithContentsOfURL:items[8] options:0 error:&error];
        XCTAssertNotNil(document, @"%@", error);

        nodes = [document nodesForXPath:@"//img/@src" error:&error];
        XCTAssertNotNil(nodes, @"%@", error);
        XCTAssertEqual(nodes.count, 2);
        XCTAssertEqualObjects(([nodes valueForKey:@"stringValue"]), (@[@"im0001.gif", @"im0002.png"]));
    }
    @finally {
        [fileManager removeItemAtURL:ch1 error:NULL];
        [fileManager removeItemAtURL:ch2 error:NULL];
        if (destinationURL) [fileManager removeItemAtURL:destinationURL error:NULL];
    }
}

- (void)testAddMetadata {
    [_action parameters][@"creators"] = @[@{@"displayName":@"Bob Smith", @"role":@"aut"}, @{@"displayName":@"Jack Brown", @"role":@"ill"}, @{@"displayName":@"Bill Jones"}];
    [_action parameters][@"publicationID"] = @"urn:uuid:2A7F7867-213A-4847-BAC7-E622012A5C47";

    NSError * __autoreleasing error;

    NSURL *temporaryDirectory = [_action prepareDestinationDirectoryForURL:outDirectory error:&error];
    XCTAssertNotNil(temporaryDirectory, "%@", error);

    XCTAssertTrue([_action writeMetadataFilesAndReturnError:&error], @"%@", error);

    NSURL *packageURL = [temporaryDirectory URLByAppendingPathComponent:@"Contents/package.opf"];

    XCTAssertTrue(packageURL.isRegularFileOnFileSystem);

    NSXMLDocument *package = [[NSXMLDocument alloc] initWithContentsOfURL:packageURL options:0 error:&error];
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

    elements = [package objectsForXQuery:@"/package/metadata/*:creator" error:&error];
    XCTAssertNotNil(elements, @"%@", error);

    XCTAssertEqualObjects(([elements valueForKey:@"stringValue"]), (@[@"Bob Smith", @"Jack Brown", @"Bill Jones"]));

    [[NSFileManager defaultManager] removeItemAtURL:temporaryDirectory error:NULL];
}

- (void)testLayoutDistribute {
    NSError * __autoreleasing error;

    XCTAssertEqual([_action layoutStyle], distributeInternalSpace);

    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:2];

    for (NSURL *url in [_images subarrayWithRange:NSMakeRange(0, 2)]) {
        NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:url];
        NSUInteger height = imageRep.pixelsHigh;
        NSUInteger width = imageRep.pixelsWide;

        NSDictionary<NSString *, id> *dictionary = @{@"url":url, @"width":@(width), @"height":@(height)};

        [frames addObject:dictionary];
    }

    NSURL *destinationURL = nil;

    @try {
        destinationURL = [_action prepareDestinationDirectoryForURL:outDirectory error:&error];
        XCTAssertNotNil(destinationURL, @"%@", error);

        XCTAssert([_action createPage:@"pg1.xhtml" fromFrames:frames error:&error], @"%@", error);

        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL URLWithString:@"Contents/pg1.xhtml" relativeToURL:destinationURL] options:0 error:&error];
        XCTAssertNotNil(document, @"%@", error);

        NSArray<NSDictionary *> *result = [[document objectsForXQuery:@"data(//img/@style)" error:&error] valueForKey:@"htmlStyle"];

        if (result.count == 2) {
            double top = [result[0][@"top"] doubleValue];
            double middleTop = top + [result[0][@"height"] doubleValue];
            double middleBottom = [result[1][@"top"] doubleValue];
            double bottom = middleBottom + [result[1][@"height"] doubleValue];

            XCTAssertGreaterThan(top, 0.0);
            XCTAssertLessThan(middleTop, middleBottom);
            XCTAssertLessThan(bottom, 100.0);
        }
        else {
            XCTFail(@"no panel information found");
        }
    }
    @finally {
        if (destinationURL) [fileManager removeItemAtURL:destinationURL error:NULL];
    }
}

- (void)testLayoutMinimize {
    NSError * __autoreleasing error;

    [_action parameters][@"layoutStyle"] = @(minimizeInternalSpace);

    XCTAssertEqual([_action layoutStyle], minimizeInternalSpace);

    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:2];

    for (NSURL *url in [_images subarrayWithRange:NSMakeRange(0, 2)]) {
        NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:url];
        NSUInteger height = imageRep.pixelsHigh;
        NSUInteger width = imageRep.pixelsWide;

        NSDictionary<NSString *, id> *dictionary = @{@"url":url, @"width":@(width), @"height":@(height)};
        [frames addObject:dictionary];
    }

    NSURL *destinationURL = nil;

    @try {
        destinationURL = [_action prepareDestinationDirectoryForURL:outDirectory error:&error];
        XCTAssertNotNil(destinationURL, @"%@", error);

        XCTAssert([_action createPage:@"pg1.xhtml" fromFrames:frames error:&error], "%@", error);

        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL URLWithString:@"Contents/pg1.xhtml" relativeToURL:destinationURL] options:0 error:&error];
        XCTAssertNotNil(document, @"%@", error);

        NSArray<NSDictionary *> *result = [[document objectsForXQuery:@"data(//img/@style)" error:&error] valueForKey:@"htmlStyle"];

        if (result.count == 2) {
            double top = [result[0][@"top"] doubleValue];
            double middleTop = top + [result[0][@"height"] doubleValue];
            double middleBottom = [result[1][@"top"] doubleValue];
            double bottom = middleBottom + [result[1][@"height"] doubleValue];

            XCTAssertGreaterThan(top, 0.0);
            XCTAssertEqualWithAccuracy(middleTop, middleBottom, 0.001);
            XCTAssertLessThan(bottom, 100.0);
        }
        else {
            XCTFail(@"no panel information found");
        }
    }
    @finally {
        if (destinationURL) [fileManager removeItemAtURL:destinationURL error:NULL];
    }
}

- (void)testLayoutMaximize {
    NSError * __autoreleasing error;

    [_action parameters][@"layoutStyle"] = @(maximizeInternalSpace);

    XCTAssertEqual([_action layoutStyle], maximizeInternalSpace);

    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:2];

    for (NSURL *url in [_images subarrayWithRange:NSMakeRange(0, 2)]) {
        NSImageRep *imageRep = [NSImageRep imageRepWithContentsOfURL:url];
        NSUInteger height = imageRep.pixelsHigh;
        NSUInteger width = imageRep.pixelsWide;

        NSDictionary<NSString *, id> *dictionary = @{@"url":url, @"width":@(width), @"height":@(height)};
        [frames addObject:dictionary];
    }

    NSURL *destinationURL = nil;

    @try {
        destinationURL = [_action prepareDestinationDirectoryForURL:outDirectory error:&error];
        XCTAssertNotNil(destinationURL, @"%@", error);

        XCTAssert([_action createPage:@"pg1.xhtml" fromFrames:frames error:&error], "%@", error);

        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[NSURL URLWithString:@"Contents/pg1.xhtml" relativeToURL:destinationURL] options:0 error:&error];
        XCTAssertNotNil(document, @"%@", error);

        NSArray<NSDictionary *> *result = [[document objectsForXQuery:@"data(//img/@style)" error:&error] valueForKey:@"htmlStyle"];

        if (result.count == 2) {
            double top = [result[0][@"top"] doubleValue];
            double middleTop = top + [result[0][@"height"] doubleValue];
            double middleBottom = [result[1][@"top"] doubleValue];
            double bottom = middleBottom + [result[1][@"height"] doubleValue];

            XCTAssertEqualWithAccuracy(top, 0.0, 0.001);
            XCTAssertLessThan(middleTop, middleBottom);
            XCTAssertEqualWithAccuracy(bottom, 100.0, 0.001);
        }
        else {
            XCTFail(@"no panel information found");
        }
    }
    @finally {
        if (destinationURL) [fileManager removeItemAtURL:destinationURL error:NULL];
    }
}

- (void)testAction {
    NSError * __autoreleasing error;

    NSMutableDictionary<NSString *, id> *parameters = [_action parameters];

    parameters[@"outputFolder"] = outDirectory.URLByDeletingLastPathComponent.path;
    parameters[@"title"] = outDirectory.lastPathComponent;
    parameters[@"creators"] = @[@{@"displayName":@"Anonymous", @"role":@"aut"}];
    parameters[@"publicationID"] = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
    parameters[@"doPanelAnalysis"] = @NO;
    parameters[@"firstIsCover"] = @NO;

    XCTAssert([fileManager removeItemAtURL:outDirectory error:&error], @"%@", error);
    outDirectory = [outDirectory URLByAppendingPathExtension:@"epub"];

    NSMutableArray<NSString *> *input = [NSMutableArray arrayWithCapacity:_images.count];

    for (NSURL *image in _images) {
        [input addObject:image.absoluteURL.path];
    }

    // The first run may initialize some variables thus leading to a bad STDEV.
    XCTAssertNotNil([_action runWithInput:input error:&error], @"%@", error);

    __block NSArray<NSString *> *result = nil;

    [self measureBlock:^{
        NSError * __autoreleasing error = nil;

        result = [_action runWithInput:input error:&error];

        XCTAssertNotNil(result, @"%@", error);
    }];

    XCTAssertEqualObjects(result[0], outDirectory.path);

    NSURL *contentsURL = [outDirectory URLByAppendingPathComponent:@"Contents"];

    NSXMLDocument *packageDocument = nil;

    NSMutableArray<NSString *> *manifestItem = [NSMutableArray array];

    for (NSString *subpath in [fileManager enumeratorAtPath:contentsURL.path]) {
        NSURL *url = [NSURL fileURLWithPath:subpath relativeToURL:contentsURL];

        NSString *typeIdentifier;

        XCTAssert([url getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:&error], @"%@", error);

        if (UTTypeConformsTo((__bridge CFStringRef)(typeIdentifier), kUTTypeDirectory)) continue;

        if ([subpath isEqualToString:@"package.opf"]) {
            packageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
            XCTAssertNotNil(packageDocument, "%@", error);
        }
        else if ([subpath isEqualToString:@"nav.xhtml"]) {
            NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
            XCTAssertNotNil(document, "%@", error);

            NSArray<NSXMLElement *> *navigation = [document objectsForXQuery:@"//li/a" error:&error];
            XCTAssertEqual(navigation.count, 1);
            XCTAssertEqualObjects(navigation[0].stringValue, @"Resources");
            XCTAssertEqualObjects([navigation[0] attributeForName:@"href"].stringValue, @"01.resources/pg0001.xhtml");

            [manifestItem addObject:@"nav.xhtml"];
        }
        else if ([subpath isEqualToString:@"data-nav.xhtml"]) {
            NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
            XCTAssertNotNil(document, "%@", error);

            NSArray *navigation = [document objectsForXQuery:@"data(//li[@epub:type='panel-group']/a/@href)" error:&error];
            XCTAssertEqual(navigation.count, 4);

            XCTAssertEqualObjects(navigation[0], @"01.resources/pg0001.xhtml#xywh=percent:0,15,100,28");
            XCTAssertEqualObjects(navigation[1], @"01.resources/pg0001.xhtml#xywh=percent:0,57,100,28");
            XCTAssertEqualObjects(navigation[2], @"01.resources/pg0002.xhtml#xywh=percent:5,0,90,100");
            XCTAssertEqualObjects(navigation[3], @"01.resources/pg0003.xhtml#xywh=percent:0,12,100,76");

            for (NSString *link in navigation) {
                NSURL *linkURL = [NSURL URLWithString:link relativeToURL:url];
                XCTAssertTrue([fileManager fileExistsAtPath:linkURL.path], @"file does not exist: %@", linkURL.path);
            }

            navigation = [document objectsForXQuery:@"data(//li[@epub:type='panel-group']/ol/li[@epub:type='panel']/a/@href)" error:&error];
            XCTAssertEqual(navigation.count, 7);

            XCTAssertEqualObjects(navigation[0], @"01.resources/pg0001.xhtml#xywh=percent:2,17,31,23");
            XCTAssertEqualObjects(navigation[1], @"01.resources/pg0001.xhtml#xywh=percent:35,17,30,23");
            XCTAssertEqualObjects(navigation[2], @"01.resources/pg0001.xhtml#xywh=percent:67,17,31,23");
            XCTAssertEqualObjects(navigation[3], @"01.resources/pg0001.xhtml#xywh=percent:2,60,31,23");
            XCTAssertEqualObjects(navigation[4], @"01.resources/pg0001.xhtml#xywh=percent:35,60,30,10");
            XCTAssertEqualObjects(navigation[5], @"01.resources/pg0001.xhtml#xywh=percent:35,72,30,11");
            XCTAssertEqualObjects(navigation[6], @"01.resources/pg0001.xhtml#xywh=percent:67,60,31,23");

            [manifestItem addObject:@"data-nav.xhtml"];
        }
        else {
            [manifestItem addObject:subpath];
        }
    }

    XCTAssertNotNil(packageDocument, @"package.opf not found");

    for (NSString *path in manifestItem) {
        NSNumber *result = [packageDocument objectsForXQuery:@"count(//manifest/item[@href=$path])" constants:@{@"path":path} error:&error].firstObject;
        XCTAssertNotNil(result, "%@", error);
        XCTAssertEqualObjects(result, @1);
    }

    XCTAssert([fileManager moveItemAtURL:outDirectory toURL:outDirectory.URLByDeletingPathExtension error:&error], "%@", error);

    outDirectory = outDirectory.URLByDeletingPathExtension;

    NSString *epubcheck = @"~/bin/epubcheck".stringByStandardizingPath;

    if ([fileManager fileExistsAtPath:epubcheck]) {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"~/bin/epubcheck".stringByStandardizingPath;
        task.currentDirectoryPath = outDirectory.URLByDeletingLastPathComponent.path;
        task.arguments = @[@"--mode", @"exp", @"--quiet", outDirectory.lastPathComponent];

        [task launch];
        [task waitUntilExit];

        XCTAssertEqual(task.terminationStatus, 0);
    }
}

@end
