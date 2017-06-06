//
//  ConvertMarkupToEPUBNavigationActionTests.m
//  ConvertMarkupToEPUBNavigationActionTests
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import XCTest;
@import Automator;
@import ObjectiveC.runtime;

@interface ConvertMarkupToEPUBNavigationActionTests : XCTestCase

@property (strong, nonatomic) AMBundleAction *action;
@property (strong, nonatomic) NSArray<NSDictionary<NSString *, id> *> *messages;
@property (strong, nonatomic) NSURL *epubURL, *epubCompressedURL;

@end

@implementation ConvertMarkupToEPUBNavigationActionTests

- (void)setUp {
    [super setUp];

    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *actionURL = [bundle URLForResource:@"Convert Markup to EPUB Navigation" withExtension:@"action"];
    XCTAssertNotNil(actionURL, @"Error loading action: resource not found");

    NSError * __autoreleasing error;
    _action = [[AMBundleAction alloc] initWithContentsOfURL:actionURL error:&error];
    XCTAssertNotNil(_action, @"Error loading action: %@", error.localizedDescription);

    NSMutableArray<NSDictionary<NSString *, id> *> *messages = [NSMutableArray array];

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

    _messages = messages;

    class_replaceMethod(c, s, imp, method_getTypeEncoding(m));

    NSURL *epubURL = [bundle URLForResource:nil withExtension:@"epub"];
    NSURL *tmpDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory()];

    _epubURL = [tmpDirectory URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"epub"]];

    XCTAssert(([[NSFileManager defaultManager] copyItemAtURL:epubURL toURL:_epubURL error:&error]), @"Error copying EPUB: %@", error);

    _epubCompressedURL = [NSURL fileURLWithPath:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"epub"] relativeToURL:_epubURL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:_epubCompressedURL error:NULL];
    [[NSFileManager defaultManager] removeItemAtURL:_epubURL error:NULL];

    Class c = [_action class];
    SEL s = @selector(logMessageWithLevel:format:);
    Method m = class_getInstanceMethod(c, s);

    class_replaceMethod(c, s, nil, method_getTypeEncoding(m));

    _epubURL = nil;
    _messages = nil;
    _action = nil;

    [super tearDown];
}

- (void)testAction {
    NSError * __autoreleasing error;

    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:_epubURL includingPropertiesForKeys:@[NSURLTypeIdentifierKey] options:0 errorHandler:nil];

    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *actualPanels = [NSMutableArray array];
    NSMutableArray<NSDictionary<NSString *, NSNumber *> *> *actualPanelGroups = [NSMutableArray array];

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\w+)\\s*:\\s*(\\d+\\.\\d+)" options:0 error:NULL];

    for (NSURL *url in enumerator) {
        if (enumerator.level != 3) continue;

        NSString * __autoreleasing typeIdentifier;
        XCTAssert([url getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:&error], @"error - %@", error);
        if (![@"public.xhtml" isEqualToString:typeIdentifier]) continue;

        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
        XCTAssertNotNil(document, @"error - %@", error);

        NSArray<NSXMLElement *> *elements = [document nodesForXPath:@"//div[@class='panel' or @class='panel-group']" error:&error];
        XCTAssertNotNil(elements, @"error - %@", error);

        for (NSXMLElement *element in elements) {
            NSString *string = [element attributeForName:@"style"].stringValue;

            NSMutableDictionary<NSString *, NSNumber *> *dictionary = [NSMutableDictionary dictionary];

            [regex enumerateMatchesInString:string options:0 range:NSMakeRange(0, string.length) usingBlock:^(NSTextCheckingResult * _Nullable match, NSMatchingFlags flags, BOOL * _Nonnull stop) {
                NSString *key = [string substringWithRange:[match rangeAtIndex:1]];
                NSString *val = [string substringWithRange:[match rangeAtIndex:2]];
                dictionary[key] = @(val.doubleValue);
            }];

            if ([[element attributeForName:@"class"].stringValue isEqualToString:@"panel"]) {
                [actualPanels addObject:dictionary];
            }
            else {
                [actualPanelGroups addObject:dictionary];
            }
        }
    }

    NSArray<NSString *> *result = [_action runWithInput:@[_epubURL.path] error:&error];

    XCTAssertNotNil(result, "error - %@", error);
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects(result[0], _epubURL.path);

    enumerator = [[NSFileManager defaultManager] enumeratorAtURL:_epubURL includingPropertiesForKeys:@[NSURLTypeIdentifierKey] options:0 errorHandler:nil];

    for (NSURL *url in enumerator) {
        if (enumerator.level != 3) continue;

        NSString * __autoreleasing typeIdentifier;
        XCTAssert([url getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:&error], @"error - %@", error);
        if (![@"public.xhtml" isEqualToString:typeIdentifier]) continue;

        NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:&error];
        XCTAssertNotNil(document, @"error - %@", error);

        NSArray<NSXMLElement *> *elements = [document nodesForXPath:@"//div[@class='panel' or @class='panel-group']" error:&error];
        XCTAssertNotNil(elements, @"error - %@", error);

        XCTAssertEqual(elements.count, 0, @"Not all panel or panel-group markers removed: %@", elements);
    }

    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[_epubURL.path stringByAppendingPathComponent:@"Contents/nav.xhtml"]]);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[_epubURL.path stringByAppendingPathComponent:@"Contents/data-nav.xhtml"]]);

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:[_epubURL URLByAppendingPathComponent:@"Contents/data-nav.xhtml"] options:0 error:&error];
    XCTAssertNotNil(document, @"error - %@", error);

    NSArray<NSString *> *foundPanelGroups = [document objectsForXQuery:@"data(//nav/ol/li/a/@href)" error:&error];
    XCTAssertNotNil(foundPanelGroups, @"error - %@", error);
    XCTAssertEqual(foundPanelGroups.count, actualPanelGroups.count);

    regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+\\.\\d+" options:0 error:NULL];

    for (NSUInteger index = 0; index < foundPanelGroups.count; ++index) {
        NSString *string = foundPanelGroups[index];
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:4];
        NSDictionary<NSString *, NSNumber *> *actualValues = actualPanelGroups[index];

        [regex enumerateMatchesInString:string options:0 range:NSMakeRange(0, string.length) usingBlock:^(NSTextCheckingResult * _Nullable match, NSMatchingFlags flags, BOOL * _Nonnull stop) {
            [values addObject:@([string substringWithRange:match.range].doubleValue)];
        }];

        XCTAssertEqualWithAccuracy(values[0].doubleValue, actualValues[@"left"].doubleValue, 1E-6);
        XCTAssertEqualWithAccuracy(values[1].doubleValue, actualValues[@"top"].doubleValue, 1E-6);
        XCTAssertEqualWithAccuracy(values[2].doubleValue, actualValues[@"width"].doubleValue, 1E-6);
        XCTAssertEqualWithAccuracy(values[3].doubleValue, actualValues[@"height"].doubleValue, 1E-6);
    }

    NSArray<NSString *> *foundPanels = [document objectsForXQuery:@"data(//nav/ol/li/ol/li/a/@href)" error:&error];
    XCTAssertNotNil(foundPanels, @"error - %@", error);
    XCTAssertEqual(foundPanels.count, actualPanels.count);

    regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+\\.\\d+" options:0 error:NULL];

    for (NSUInteger index = 0; index < foundPanels.count; ++index) {
        NSString *string = foundPanels[index];
        NSMutableArray<NSNumber *> *values = [NSMutableArray arrayWithCapacity:4];
        NSDictionary<NSString *, NSNumber *> *actualValues = actualPanels[index];

        [regex enumerateMatchesInString:string options:0 range:NSMakeRange(0, string.length) usingBlock:^(NSTextCheckingResult * _Nullable match, NSMatchingFlags flags, BOOL * _Nonnull stop) {
            [values addObject:@([string substringWithRange:match.range].doubleValue)];
        }];

        XCTAssertEqualWithAccuracy(values[0].doubleValue, actualValues[@"left"].doubleValue, 1E-6);
        XCTAssertEqualWithAccuracy(values[1].doubleValue, actualValues[@"top"].doubleValue, 1E-6);
        XCTAssertEqualWithAccuracy(values[2].doubleValue, actualValues[@"width"].doubleValue, 1E-6);
        XCTAssertEqualWithAccuracy(values[3].doubleValue, actualValues[@"height"].doubleValue, 1E-6);
    }
}

- (void)testActionPassthru {
    NSError * __autoreleasing error;

    NSArray<NSString *> *xhtml = [_action.bundle pathsForResourcesOfType:@"xhtml" inDirectory:nil];
    XCTAssert(xhtml.count);

    NSArray<NSString *> *result = [_action runWithInput:xhtml error:&error];

    XCTAssertNotNil(result, "error - %@", error);
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects(result, xhtml);

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"level == %d AND message CONTAINS %@", AMLogLevelDebug, xhtml[0].lastPathComponent];
    NSArray *messages = [_messages filteredArrayUsingPredicate:predicate];

    XCTAssertGreaterThan(messages.count, 0, @"No messages generated for errant file %@", xhtml[0].lastPathComponent);

    predicate = [NSPredicate predicateWithFormat:@"level > %d", AMLogLevelInfo, messages];
    messages = [_messages filteredArrayUsingPredicate:predicate];

    XCTAssertEqual(messages.count, 0, @"Unexpected warning/error messages: %@", [messages valueForKey:@"message"]);
}

- (void)testActionPassthruCompressedEPUB {
    NSError * __autoreleasing error;

    NSString *shellCommand = [NSString stringWithFormat:@"cd %1$@; zip -0X ../%2$@ mimetype; zip -urX ../%2$@ .", _epubURL.path, _epubCompressedURL.lastPathComponent];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/bash";
    task.arguments = @[@"-c", shellCommand];
    task.standardInput = nil;
    task.standardOutput = nil;
    task.standardError = nil;

    [task launch];
    [task waitUntilExit];

    XCTAssert(task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 0);

    NSArray<NSString *> *input = @[_epubCompressedURL.path];
    NSArray<NSString *> *result = [_action runWithInput:input error:&error];

    XCTAssertNotNil(result, "error - %@", error);
    XCTAssertEqual(result.count, 1);
    XCTAssertEqualObjects(result, input);

    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"level == %d AND message CONTAINS %@", AMLogLevelWarn, _epubCompressedURL.lastPathComponent];
    NSArray *messages = [_messages filteredArrayUsingPredicate:predicate];

    XCTAssertGreaterThan(messages.count, 0, @"No messages generated for errant file %@", _epubCompressedURL.lastPathComponent);

    predicate = [NSPredicate predicateWithFormat:@"level > %d AND NOT SELF IN %@", AMLogLevelInfo, messages];
    messages = [_messages filteredArrayUsingPredicate:predicate];

    XCTAssertEqual(messages.count, 0, @"Unexpected warning/error messages: %@", [messages valueForKey:@"message"]);
}

@end
