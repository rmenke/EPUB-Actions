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
static NSString * const ConvertMarkupToEPUBNavigationErrorDomain = @"ConvertMarkupToEPUBNavigationErrorDomain";

@implementation ConvertMarkupToEPUBNavigationAction

- (void)dealloc {
    [self unbind:AMFractionCompletedBinding];
}

- (nullable NSData *)processPage:(NSFileWrapper *)wrapper chapter:(NSString *)chapter updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError **)error {
    NSError * __autoreleasing internalError;

    NSString *page = wrapper.preferredFilename;

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:wrapper.regularFileContents options:0 error:error];
    if (!document) return nil;

    NSArray<NSXMLElement *> *divElements = [document nodesForXPath:@"//div[@class='panel' or @class='panel-group']" error:error];
    if (!divElements) return nil;

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\w+)\\s*:\\s*(\\d+\\.\\d+)%" options:0 error:&internalError];
    if (!regex) return nil;

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

    return [document XMLDataWithOptions:NSXMLNodePrettyPrint];
}

- (BOOL)processChapter:(NSFileWrapper *)wrapper updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError **)error {
    NSString *chapter = wrapper.preferredFilename;
    NSDictionary<NSString *, NSFileWrapper *> *fileWrappers = wrapper.fileWrappers;

    NSArray<NSString *> *keys = [[fileWrappers.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF MATCHES 'pg[0-9]+\\.xhtml'"]] sortedArrayUsingSelector:@selector(compare:)];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:keys.count];

    for (NSString *key in keys) {
        [progress becomeCurrentWithPendingUnitCount:1];

        NSFileWrapper *original = fileWrappers[key];

        NSData *replacementContent = [self processPage:original chapter:chapter updating:regions error:error];
        if (!replacementContent) return NO;

        [wrapper removeFileWrapper:original];
        [wrapper addRegularFileWithContents:replacementContent preferredFilename:key];

        [progress resignCurrent];
    }

    return YES;
}

- (BOOL)processFolder:(NSURL *)epubURL error:(NSError **)error {
    NSError * __autoreleasing internalError;

    NSFileWrapper *directory = [[NSFileWrapper alloc] initWithURL:epubURL options:NSFileWrapperReadingWithoutMapping error:error];
    if (!directory) return NO;

    NSFileWrapper *contentsDirectory = directory.fileWrappers[@"Contents"];
    if (!contentsDirectory) {
        if (error) *error = [NSError errorWithDomain:ConvertMarkupToEPUBNavigationErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey:@"The folder is not a valid EPUB.", NSLocalizedFailureReasonErrorKey:@"The directory does not contain a 'Contents' subdirectory."}];
        return NO;
    }

    NSDictionary<NSString *, NSFileWrapper *> *chapterWrappers = contentsDirectory.fileWrappers;

    NSArray<NSString *> *chapterKeys = [[contentsDirectory.fileWrappers.allKeys filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF MATCHES '[0-9]+\\..*'"]] sortedArrayUsingSelector:@selector(compare:)];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:chapterKeys.count];

    NSMutableArray<NSXMLElement *> *regions = [NSMutableArray array];

    for (NSString *chapterName in chapterKeys) {
        [progress becomeCurrentWithPendingUnitCount:1];
        if (![self processChapter:chapterWrappers[chapterName] updating:regions error:error]) return NO;
        [progress resignCurrent];
    }

    for (NSXMLElement *element in regions) {
        NSArray<NSXMLElement *> *emptyListElements = [element nodesForXPath:@"ol[not(*)]" error:&internalError];
        NSAssert(emptyListElements, @"xpath - %@", internalError);

        for (NSXMLElement *element in emptyListElements) {
            [element detach];
        }
    }

    NSURL *cssURL = [self.bundle URLForResource:@"contents" withExtension:@"css"];
    NSAssert(cssURL, @"contents.css resource is missing from action.");

    NSFileWrapper *contentsCSSWrapper = [[NSFileWrapper alloc] initWithURL:cssURL options:0 error:error];
    if (!contentsCSSWrapper) return NO;

    [contentsDirectory removeFileWrapper:contentsDirectory.fileWrappers[@"contents.css"]];
    [contentsDirectory addFileWrapper:contentsCSSWrapper];

    NSURL *navURL = [self.bundle URLForResource:@"data-nav" withExtension:@"xhtml"];
    NSAssert(navURL, @"data-nav.xhtml resource is missing from action.");

    NSXMLDocument *navDocument = [[NSXMLDocument alloc] initWithContentsOfURL:navURL options:0 error:&internalError];
    NSAssert(navDocument, @"data-nav.xhtml resource is damaged - %@", internalError);

    NSXMLElement *listElement = [navDocument nodesForXPath:@"//nav/ol" error:&internalError].firstObject;
    NSAssert(listElement, @"data-nav.xhtml resource is damaged - %@", internalError);

    listElement.children = regions;

    NSString *dataNavPath = [contentsDirectory addRegularFileWithContents:[navDocument XMLDataWithOptions:NSXMLNodePrettyPrint] preferredFilename:@"data-nav.xhtml"];

    NSFileWrapper *packageFile = contentsDirectory.fileWrappers[@"package.opf"];
    NSXMLDocument *packageDocument = [[NSXMLDocument alloc] initWithData:packageFile.regularFileContents options:0 error:error];
    if (!packageDocument) return NO;

    NSArray<NSXMLElement *> *elements = [packageDocument nodesForXPath:@"//manifest" error:&internalError];
    NSAssert(elements, @"xpath - %@", internalError);

    if (elements.count != 1) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{NSLocalizedDescriptionKey:@"There should be exactly one 'manifest' element in a package document."}];
        return NO;
    }

    NSXMLNode *idAttr = [NSXMLNode attributeWithName:@"id" stringValue:@"data-nav"];
    NSXMLNode *hrefAttr = [NSXMLNode attributeWithName:@"href" stringValue:dataNavPath];
    NSXMLNode *propertiesAttr = [NSXMLNode attributeWithName:@"properties" stringValue:@"data-nav"];
    NSXMLNode *mediaTypeAttr = [NSXMLNode attributeWithName:@"media-type" stringValue:@"application/xhtml+xml"];

    [elements.firstObject addChild:[NSXMLElement elementWithName:@"item" children:nil attributes:@[idAttr, hrefAttr, propertiesAttr, mediaTypeAttr]]];

    [contentsDirectory removeFileWrapper:packageFile];
    [contentsDirectory addRegularFileWithContents:[packageDocument XMLDataWithOptions:NSXMLNodePrettyPrint] preferredFilename:@"package.opf"];

    return [directory writeToURL:epubURL options:NSFileWrapperWritingAtomic originalContentsURL:epubURL error:error];
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
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ ignored; this action cannot handle compressed EPUB documents", url.lastPathComponent];
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
