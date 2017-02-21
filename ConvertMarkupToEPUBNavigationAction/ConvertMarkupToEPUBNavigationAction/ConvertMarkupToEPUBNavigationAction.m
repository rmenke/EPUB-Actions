//
//  ConvertMarkupToEPUBNavigationAction.m
//  ConvertMarkupToEPUBNavigationAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "ConvertMarkupToEPUBNavigationAction.h"

@import AppKit.NSKeyValueBinding;

NS_ASSUME_NONNULL_BEGIN

static NSString * const AMFractionCompletedBinding = @"fractionCompleted";

@implementation ConvertMarkupToEPUBNavigationAction

- (void)dealloc {
    [self unbind:AMFractionCompletedBinding];
}

- (BOOL)processPage:(NSURL *)url updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError ** _Nullable)error {
    NSError * __autoreleasing internalError;

    NSString *page = url.lastPathComponent;
    NSString *chapter = url.URLByDeletingLastPathComponent.lastPathComponent;

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:error];
    if (!document) return NO;

    NSArray<NSXMLElement *> *divElements = [document nodesForXPath:@"//div[@class='panel' or @class='panel-group']" error:&internalError];
    NSAssert(divElements, @"xpath - %@", internalError);

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\w+)\\s*:\\s*(\\d+\\.\\d+)%" options:0 error:&internalError];
    NSAssert(regex, @"regex - %@", internalError);

    for (NSXMLElement* element in divElements) {
        [element detach];

        NSString *style = [element attributeForName:@"style"].stringValue;
        NSString *class = [element attributeForName:@"class"].stringValue;

        NSMutableDictionary<NSString *, NSNumber *> *bounds = [NSMutableDictionary dictionaryWithCapacity:4];

        [regex enumerateMatchesInString:style options:0 range:NSMakeRange(0, style.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            NSString *name  = [style substringWithRange:[result rangeAtIndex:1]];
            NSString *value = [style substringWithRange:[result rangeAtIndex:2]];
            [bounds setValue:@(value.doubleValue) forKey:name];
        }];

        NSString *path = [NSString stringWithFormat:@"%@/%@#xywh=percent:%0.4f,%0.4f,%0.4f,%0.4f", chapter, page, bounds[@"left"].doubleValue, bounds[@"top"].doubleValue, bounds[@"width"].doubleValue, bounds[@"height"].doubleValue];

        NSXMLNode *typeAttr = [NSXMLNode attributeWithName:@"epub:type" stringValue:class];

        if ([class isEqualToString:@"panel-group"]) {
            NSXMLElement *aElement = [NSXMLElement elementWithName:@"a" children:nil attributes:@[[NSXMLNode attributeWithName:@"href" stringValue:path]]];
            NSXMLElement *olElement = [NSXMLElement elementWithName:@"ol"];

            [regions addObject:[NSXMLElement elementWithName:@"li" children:@[aElement, olElement] attributes:@[typeAttr]]];
        }
        else {
            NSXMLElement *aElement = [NSXMLElement elementWithName:@"a" children:nil attributes:@[[NSXMLNode attributeWithName:@"href" stringValue:path]]];
            NSXMLElement *currentSubregionList = [regions.lastObject elementsForName:@"ol"].lastObject;

            [currentSubregionList addChild:[NSXMLElement elementWithName:@"li" children:@[aElement] attributes:@[typeAttr]]];
        }
    }

    return [[document XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:url options:0 error:error];
}

- (BOOL)processChapter:(NSURL *)url updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSArray<NSString *> *pages = [[[fileManager contentsOfDirectoryAtPath:url.path error:error] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF MATCHES 'pg[0-9]+.xhtml'"]] sortedArrayUsingSelector:@selector(compare:)];
    if (!pages) return NO;

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:pages.count];

    for (NSString *page in pages) {
        [progress becomeCurrentWithPendingUnitCount:1];
        if (![self processPage:[url URLByAppendingPathComponent:page] updating:regions error:error]) return NO;
        [progress resignCurrent];
    }

    return YES;
}

- (BOOL)processFolder:(NSURL *)baseURL error:(NSError **)error {
    NSError * __autoreleasing internalError;

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *contentsURL = [baseURL URLByAppendingPathComponent:@"Contents" isDirectory:YES];

    NSArray<NSString *> *chapters = [[[fileManager contentsOfDirectoryAtPath:contentsURL.path error:error] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF MATCHES 'ch[0-9]+'"]] sortedArrayUsingSelector:@selector(compare:)];
    if (!chapters) return NO;

    NSAssert(chapters.count > 0, @"No chapters found");

    NSMutableArray<NSXMLElement *> *regions = [NSMutableArray array];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:chapters.count];

    for (NSString *chapter in chapters) {
        [progress becomeCurrentWithPendingUnitCount:1];
        if (![self processChapter:[contentsURL URLByAppendingPathComponent:chapter] updating:regions error:error]) return NO;
        [progress resignCurrent];
    }

    for (NSXMLElement *element in regions) {
        NSArray<NSXMLElement *> *emptyListElements = [element nodesForXPath:@"ol[not(*)]" error:&internalError];
        NSAssert(emptyListElements, @"xpath - %@", internalError);

        for (NSXMLElement *element in emptyListElements) {
            [element detach];
        }
    }

    NSURL *originalStylesheetURL = [contentsURL URLByAppendingPathComponent:@"contents.css"];
    NSURL *replacementStylesheetURL = [self.bundle URLForResource:@"contents" withExtension:@"css"];
    NSAssert(replacementStylesheetURL, @"contents.css resource is missing from action.");

    if (![fileManager removeItemAtURL:originalStylesheetURL error:error]) return NO;
    if (![fileManager copyItemAtURL:replacementStylesheetURL toURL:originalStylesheetURL error:error]) return NO;

    NSURL *navURL = [self.bundle URLForResource:@"data-nav" withExtension:@"xhtml"];
    NSAssert(navURL, @"data-nav.xhtml resource is missing from action.");

    NSXMLDocument *navDocument = [[NSXMLDocument alloc] initWithContentsOfURL:navURL options:0 error:&internalError];
    NSAssert(navDocument, @"data-nav.xhtml resource is damaged - %@", internalError);

    NSXMLElement *listElement = [navDocument nodesForXPath:@"//nav/ol" error:&internalError].firstObject;
    NSAssert(listElement, @"data-nav.xhtml resource is damaged - %@", internalError);

    listElement.children = regions;

    if (![[navDocument XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:[contentsURL URLByAppendingPathComponent:navURL.lastPathComponent] options:0 error:error]) return NO;

    NSURL *packageURL = [contentsURL URLByAppendingPathComponent:@"package.opf"];
    NSXMLDocument *packageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:packageURL options:0 error:error];
    if (!packageDocument) return NO;

    NSArray<NSXMLElement *> *elements = [packageDocument nodesForXPath:@"//manifest" error:&internalError];
    NSAssert(elements, @"xpath - %@", internalError);

    if (elements.count != 1) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSURLErrorKey:packageURL, NSLocalizedDescriptionKey:@"There should be exactly one 'manifest' element in a package document."}];
        return NO;
    }

    NSXMLNode *idAttr = [NSXMLNode attributeWithName:@"id" stringValue:@"data-nav"];
    NSXMLNode *hrefAttr = [NSXMLNode attributeWithName:@"href" stringValue:@"data-nav.xhtml"];
    NSXMLNode *propertiesAttr = [NSXMLNode attributeWithName:@"properties" stringValue:@"data-nav"];
    NSXMLNode *mediaTypeAttr = [NSXMLNode attributeWithName:@"media-type" stringValue:@"application/xhtml+xml"];

    [elements.firstObject addChild:[NSXMLElement elementWithName:@"item" children:nil attributes:@[idAttr, hrefAttr, propertiesAttr, mediaTypeAttr]]];

    return [[packageDocument XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:packageURL options:0 error:error];
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (!input || input.count == 0) return @[];

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:input.count];
    [self bind:AMFractionCompletedBinding toObject:progress withKeyPath:@"fractionCompleted" options:nil];

    for (NSString *path in input) {
        NSURL *url = [NSURL fileURLWithPath:path];

        NSDictionary<NSURLResourceKey, id> *resourceInformation = [url resourceValuesForKeys:@[NSURLTypeIdentifierKey] error:error];
        if (!resourceInformation) return nil;
        
        NSString *typeIdentifier = resourceInformation[NSURLTypeIdentifierKey];

        [progress becomeCurrentWithPendingUnitCount:1];

        if (UTTypeConformsTo((__bridge CFStringRef _Nonnull)(typeIdentifier), CFSTR("org.idpf.epub-folder"))) {
            if (![self processFolder:url error:error]) return nil;
        }
        else if (UTTypeConformsTo((__bridge CFStringRef _Nonnull)(typeIdentifier), CFSTR("org.idpf.epub-container"))) {
            // TODO: Uncompress and replace container with folder
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ ignored; this action cannot handle compressed ePub documents", url.lastPathComponent];
        }
        else {
            NSString *typeDescription = CFBridgingRelease(UTTypeCopyDescription((__bridge CFStringRef _Nonnull)(typeIdentifier)));
            [self logMessageWithLevel:AMLogLevelDebug format:@"%@ ignored; this action cannot handle %@ files", url.lastPathComponent, typeDescription];
        }

        [progress resignCurrent];
    }

    return input;
}

- (CGFloat)fractionCompleted {
    return self.progressValue;
}

- (void)setFractionCompleted:(CGFloat)fractionCompleted {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressValue = fractionCompleted;
    });
}

@end

NS_ASSUME_NONNULL_END
