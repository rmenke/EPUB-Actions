//
//  ImagesToEPUBAction.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "ImagesToEPUBAction.h"
#import "OPFPackageDocument.h"

@import AppKit.NSColor;
@import AppKit.NSKeyValueBinding;

NS_ASSUME_NONNULL_BEGIN

static NSString * const AMFractionCompletedBinding = @"fractionCompleted";

static inline BOOL typeIsImage(NSString *typeIdentifier) {
    static NSSet<NSString *> *imageTypes;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageTypes = [NSSet setWithArray:CFBridgingRelease(CGImageSourceCopyTypeIdentifiers())];
    });

    return [imageTypes containsObject:typeIdentifier];
}

static inline NSString *extensionForType(NSString *typeIdentifier) {
    return CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)(typeIdentifier), kUTTagClassFilenameExtension));
}

static inline BOOL isExtensionCorrectForType(NSString *extension, NSString *typeIdentifier) {
    static dispatch_once_t onceToken;
    static NSDictionary<NSString *, NSSet<NSString *> *> *extensions;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *imageTypes = CFBridgingRelease(CGImageSourceCopyTypeIdentifiers());
        NSMutableArray<NSSet<NSString *> *> *extensionSets = [NSMutableArray arrayWithCapacity:imageTypes.count];

        for (NSString *imageType in imageTypes) {
            NSArray<NSString *> *extensionsForType = CFBridgingRelease(UTTypeCopyAllTagsWithClass((__bridge CFStringRef)(imageType), kUTTagClassFilenameExtension));
            [extensionSets addObject:[NSSet setWithArray:extensionsForType]];
        }

        extensions = [NSDictionary dictionaryWithObjects:extensionSets forKeys:imageTypes];
    });

    return [extensions[typeIdentifier] containsObject:extension];
}

@interface ImagesToEPUBAction ()

@property (nonatomic) NSString *outputFolder;
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *authors;
@property (nonatomic) NSString *publicationID;
@property (nonatomic) NSUInteger pageWidth, pageHeight, pageMargin;
@property (nonatomic) BOOL disableUpscaling;
@property (nonatomic) NSData *backgroundColor;
@property (nonatomic) BOOL doPanelAnalysis;

@end

@implementation ImagesToEPUBAction

- (void)dealloc {
    [self unbind:AMFractionCompletedBinding];
}

- (void)loadParameters {
    NSMutableDictionary<NSString *, id> *parameters = self.parameters;

    for (NSString *property in parameters) {
        if ([self respondsToSelector:NSSelectorFromString(property)]) {
            [self setValue:parameters[property] forKeyPath:property];
        }
    }

    if (_title.length == 0) {
        _title = parameters[@"title"] = @"Untitled";
        [self logMessageWithLevel:AMLogLevelWarn format:@"Title unset; setting to 'Untitled'"];
    }

    if (_publicationID.length == 0) {
        _publicationID = parameters[@"publicationID"] = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
        [self logMessageWithLevel:AMLogLevelWarn format:@"Publication ID unset; setting to '%@'", _publicationID];
    }

    NSParameterAssert(_pageWidth  > 2 * _pageMargin);
    NSParameterAssert(_pageHeight > 2 * _pageMargin);

    NSColor *backgroundColor = _backgroundColor ? [NSUnarchiver unarchiveObjectWithData:_backgroundColor] : nil;

    if (backgroundColor) {
        CGFloat rgba[4];

        [[backgroundColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getComponents:rgba];

        const uint8_t r = rgba[0] * 255.0;
        const uint8_t g = rgba[1] * 255.0;
        const uint8_t b = rgba[2] * 255.0;

        _pageColor = [NSString stringWithFormat:@"#%02"PRIx8"%02"PRIx8"%02"PRIx8, r, g, b];
    }
    else {
        _pageColor = @"#ffffff";
    }

    NSURL *folderURL   = [NSURL fileURLWithPath:_outputFolder.stringByExpandingTildeInPath isDirectory:YES];
    NSString *filename = [[_title stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"epub"];

    _outputURL         = [NSURL fileURLWithPath:filename isDirectory:YES relativeToURL:folderURL];
}

- (nullable NSURL *)createWorkingDirectory:(NSError **)error {
    return [[NSFileManager defaultManager] URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:_outputURL create:YES error:error];
}

- (nullable NSURL *)finalizeWorkingDirectory:(NSURL *)workingURL error:(NSError **)error {
    NSURL * __autoreleasing outputURL;
    return [[NSFileManager defaultManager] replaceItemAtURL:_outputURL withItemAtURL:workingURL backupItemName:NULL options:0 resultingItemURL:&outputURL error:error] ? outputURL : nil;
}

- (nullable NSArray<NSDictionary<NSString *, id> *> *)copyItemsFromPaths:(NSArray<NSString *> *)paths toDirectory:(NSURL *)directory error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];

    NSURL *contentURL = [directory URLByAppendingPathComponent:@"Contents" isDirectory:YES];

    if (![manager createDirectoryAtURL:contentURL withIntermediateDirectories:YES attributes:nil error:error]) return nil;

    const NSUInteger count = paths.count;

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:count];

    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray arrayWithCapacity:count];

    NSDictionary<NSString *, id> *chapter = @{@"title": @""};

    for (NSString *path in paths) {
        NSURL *inputURL = [NSURL fileURLWithPath:path];

        NSString * _Nonnull typeIdentifier;

        if (![inputURL getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if (typeIsImage(typeIdentifier)) {
            NSString * _Nonnull pendingChapter = inputURL.URLByDeletingLastPathComponent.lastPathComponent;

            if (![chapter[@"title"] isEqualToString:pendingChapter]) {
                NSURL *url = [NSURL fileURLWithPath:[NSString stringWithFormat:@"ch%04lu", (unsigned long)(result.count + 1)] isDirectory:YES relativeToURL:contentURL];
                chapter = @{@"title":pendingChapter, @"images":[NSMutableArray array], @"url":url};
                [result addObject:chapter];

                if (![manager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:error]) return nil;
            }

            NSAssert(result.count > 0, @"Chapter has not been recorded");

            NSURL *outputURL = [chapter[@"url"] URLByAppendingPathComponent:[NSString stringWithFormat:@"im%04lu.%@", [chapter[@"images"] count] + 1, extensionForType(typeIdentifier)]];
            if (![manager copyItemAtURL:inputURL toURL:outputURL error:error]) return nil;
            [chapter[@"images"] addObject:outputURL];
        }
        else {
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ is not a file type supported by this action", path.lastPathComponent];
        }

        progress.completedUnitCount++;
    }

    return result;
}

- (nullable NSURL *)createPage:(NSArray<NSDictionary<NSString *, id> *> *)page number:(NSUInteger)pageNum inDirectory:(NSURL *)directory error:(NSError **)error {
    NSParameterAssert(page.count > 0);

    const CGFloat contentWidth  = _pageWidth  - 2 * _pageMargin;
    const CGFloat contentHeight = _pageHeight - 2 * _pageMargin;

    const CGFloat usedHeight = [[page valueForKeyPath:@"@sum.height"] doubleValue];

    const CGFloat vSpace = (contentHeight - usedHeight) / (CGFloat)(page.count - 1);

    CGFloat y = _pageMargin;

    if (page.count == 1) y += (contentHeight - usedHeight) / 2.0;

    CGAffineTransform pixelToPercent = CGAffineTransformMakeScale(100.0 / _pageWidth, 100.0 / _pageHeight);

    NSURL * _Nonnull templateURL = [self.bundle URLForResource:@"page" withExtension:@"xhtml"];
    if (!templateURL) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml resource missing" userInfo:nil];

    NSError * __autoreleasing underlyingError;

    NSXMLDocument *pageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:templateURL options:0 error:&underlyingError];
    if (!pageDocument) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml failed to load" userInfo:@{NSURLErrorKey:templateURL, NSUnderlyingErrorKey:underlyingError}];

    NSXMLElement *bodyElement = [pageDocument nodesForXPath:@"/html/body" error:&underlyingError].firstObject;
    if (!bodyElement) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml failed to load" userInfo:@{NSURLErrorKey:templateURL, NSUnderlyingErrorKey:underlyingError}];

    [bodyElement addAttribute:[NSXMLNode attributeWithName:@"style" stringValue:[NSString stringWithFormat:@"width:%lupx; height:%lupx", (unsigned long)(_pageWidth), (unsigned long)(_pageHeight)]]];

    NSXMLNode *viewportNode = [pageDocument nodesForXPath:@"/html/head/meta[@name='viewport']/@content" error:&underlyingError].firstObject;
    if (!viewportNode) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml failed to load" userInfo:@{NSURLErrorKey:templateURL, NSUnderlyingErrorKey:underlyingError}];

    viewportNode.stringValue = [NSString stringWithFormat:@"width=%lu, height=%lu", (unsigned long)(_pageWidth), (unsigned long)(_pageHeight)];

    for (NSDictionary<NSString *, id> *frame in page) {
        NSURL *url = [frame valueForKey:@"url"];

        CGFloat width = [[frame valueForKey:@"width"] doubleValue];
        CGFloat height = [[frame valueForKey:@"height"] doubleValue];

        CGFloat x = (contentWidth - width) / 2.0 + _pageMargin;

        CGRect r = CGRectApplyAffineTransform(CGRectMake(x, y, width, height), pixelToPercent);

        NSString *style = [NSString stringWithFormat:@"left:%0.4f%%; top:%0.4f%%; width:%0.4f%%; height:%0.4f%%", r.origin.x, r.origin.y, r.size.width, r.size.height];

        NSXMLNode *srcAttr = [NSXMLNode attributeWithName:@"src" stringValue:url.lastPathComponent];
        NSXMLNode *altAttr = [NSXMLNode attributeWithName:@"alt" stringValue:@""];
        NSXMLNode *widthAttr = [NSXMLNode attributeWithName:@"width" stringValue:[NSString stringWithFormat:@"%0.0f", r.size.width]];
        NSXMLNode *heightAttr = [NSXMLNode attributeWithName:@"width" stringValue:[NSString stringWithFormat:@"%0.0f", r.size.height]];
        NSXMLNode *styleAttr = [NSXMLNode attributeWithName:@"style" stringValue:style];

        NSXMLElement *imgElement = [NSXMLElement elementWithName:@"img" children:nil attributes:@[srcAttr, altAttr, widthAttr, heightAttr, styleAttr]];

        [bodyElement addChild:imgElement];

        NSXMLNode *classAttr = [NSXMLNode attributeWithName:@"class" stringValue:@"panel-group"];

        NSXMLElement *divElement = [NSXMLElement elementWithName:@"div" children:nil attributes:@[classAttr, styleAttr.copy]];

        [bodyElement addChild:divElement];

        if (_doPanelAnalysis) {
            id image = [frame valueForKey:@"image"];

            CGFloat originalWidth = CGImageGetWidth((CGImageRef)image);
            CGFloat originalHeight = CGImageGetHeight((CGImageRef)image);

            __unused CGAffineTransform localToGlobal = CGAffineTransformMakeTranslation(x, y);
            localToGlobal = CGAffineTransformScale(localToGlobal, width / originalWidth, height / originalHeight);

            // TODO: Implement panel analysis
        }

        y += height;
        y += vSpace;
    }

    NSURL *pageURL = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@"pg%04lu.xhtml", pageNum]];
    return [[pageDocument XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:pageURL options:0 error:error] ? pageURL : nil;
}

- (nullable NSArray<NSURL *> *)createChapters:(NSArray<NSDictionary<NSString *, id> *> *)chapters error:(NSError **)error {
    const CGFloat contentWidth  = _pageWidth  - 2 * _pageMargin;
    const CGFloat contentHeight = _pageHeight - 2 * _pageMargin;

    NSAssert(contentWidth > 0, @"Content width incorrect");
    NSAssert(contentHeight > 0, @"Content height incorrect");

    NSUInteger count = [[chapters valueForKeyPath:@"@sum.images.@count"] unsignedIntegerValue];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:count];

    NSMutableArray<NSURL *> *result = [NSMutableArray array];

    for (NSDictionary<NSString *, id> *chapter in chapters) {
        NSURL *chapterURL = chapter[@"url"];

        NSUInteger pageCount = 0;

        NSMutableArray<NSDictionary<NSString *, id> *> *page = [NSMutableArray array];
        CGFloat currentHeight = 0.0;

        for (NSURL *url in chapter[@"images"]) {
            CGImageSourceRef source = CGImageSourceCreateWithURL((CFURLRef)url, NULL);
            if (!source) {
                if (error) *error = [NSError errorWithDomain:@"CoreGraphicsErrorDomain" code:__LINE__ userInfo:@{NSURLErrorKey:url}];
                return nil;
            }

            id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex(source, 0, NULL));
            CFRelease(source);

            if (!image) {
                if (error) *error = [NSError errorWithDomain:@"CoreGraphicsErrorDomain" code:__LINE__ userInfo:@{NSURLErrorKey:url}];
                return nil;
            }

            CGFloat w = CGImageGetWidth((CGImageRef)image);
            CGFloat h = CGImageGetHeight((CGImageRef)image);
            NSString *typeIdentifier = (NSString *)CGImageGetUTType((CGImageRef)image);

            NSURL *correctedURL;

            if (isExtensionCorrectForType(url.pathExtension, typeIdentifier)) {
                correctedURL = url;
            }
            else {
                correctedURL = [url.URLByDeletingPathExtension URLByAppendingPathExtension:extensionForType(typeIdentifier)];
                [self logMessageWithLevel:AMLogLevelWarn format:@"%@ has an incorrect extension; should be %@", url.lastPathComponent, correctedURL.lastPathComponent];
                if (![[NSFileManager defaultManager] moveItemAtURL:url toURL:correctedURL error:error]) return nil;
            }

            CGFloat scale = fmin(contentWidth / w, contentHeight / h);

            while ((h * scale > contentHeight) || (w * scale > contentWidth)) {
                scale = nextafter(scale, 0.0);
            }

            if (_disableUpscaling && scale > 1.0) {
                scale = 1.0;
            }

            NSAssert(w * scale <= contentWidth, @"width: %f, scale: %f, scaled width: %f, max: %f", w, scale, w * scale, contentWidth);
            NSAssert(h * scale <= contentHeight, @"height: %f, scale: %f, scaled height: %f, max: %f", h, scale, h * scale, contentHeight);

            NSDictionary<NSString *, id> *frame = @{@"image":image, @"url":correctedURL, @"width": @(w * scale), @"height": @(h * scale)};

            if (currentHeight + h * scale > contentHeight) {
                NSURL *pageURL = [self createPage:page number:(++pageCount) inDirectory:chapterURL error:error];
                if (!pageURL) return nil;

                [result addObject:pageURL];

                page = [NSMutableArray array];
                currentHeight = 0.0;
            }

            [page addObject:frame];
            currentHeight += h * scale;

            progress.completedUnitCount++;
        }

        NSURL *pageURL = [self createPage:page number:(++pageCount) inDirectory:chapterURL error:error];
        if (!pageURL) return nil;

        [result addObject:pageURL];
    }

    return result;
}

- (BOOL)addMetadataToDirectory:(NSURL *)directory chapters:(NSArray<NSDictionary<NSString *, id> *> *)chapters spineItems:(NSArray<NSString *> *)spineItems error:(NSError **)error {
    NSFileManager *manager = [NSFileManager defaultManager];

    NSURL *mimetypeURL = [NSURL fileURLWithPath:@"mimetype" isDirectory:NO relativeToURL:directory];
    NSURL *metainfoDirectory = [NSURL fileURLWithPath:@"META-INF" isDirectory:YES relativeToURL:directory];
    NSURL *contentsDirectory = [NSURL fileURLWithPath:@"Contents" isDirectory:YES relativeToURL:directory];

    if (![@"application/epub+zip" writeToURL:mimetypeURL atomically:NO encoding:NSASCIIStringEncoding error:error]) return NO;
    if (![manager createDirectoryAtURL:metainfoDirectory withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    if (![manager createDirectoryAtURL:contentsDirectory withIntermediateDirectories:YES attributes:nil error:error]) return NO;

    NSURL *containerURL = [self.bundle URLForResource:@"container" withExtension:@"xml"];
    NSAssert(containerURL, @"container.xml resource is missing from action.");

    if (![manager copyItemAtURL:containerURL toURL:[metainfoDirectory URLByAppendingPathComponent:containerURL.lastPathComponent] error:error]) return NO;

    NSURL *stylesheetURL = [self.bundle URLForResource:@"contents" withExtension:@"css"];
    NSAssert(stylesheetURL, @"contents.css resource is missing from action.");

    if (![manager copyItemAtURL:stylesheetURL toURL:[contentsDirectory URLByAppendingPathComponent:stylesheetURL.lastPathComponent] error:error]) return NO;

    NSError * __autoreleasing internalError;

    NSURL *packageURL = [self.bundle URLForResource:@"package" withExtension:@"opf"];
    NSAssert(packageURL, @"package.opf resource is missing from action.");

    OPFPackageDocument *packageDocument = [OPFPackageDocument documentWithContentsOfURL:packageURL error:&internalError];
    NSAssert(packageDocument, @"package.opf resource is damaged - %@", internalError);

    packageDocument.identifier = _publicationID;
    packageDocument.title = _title;
    packageDocument.modified = [NSDate date];

    NSArray<NSString *> *manifestItems = [chapters valueForKeyPath:@"@unionOfArrays.images.relativePath"];

    [[packageDocument mutableSetValueForKey:@"manifest"] addObjectsFromArray:manifestItems];
    [[packageDocument mutableArrayValueForKey:@"spine"] addObjectsFromArray:spineItems];

    if (![[packageDocument.document XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:[contentsDirectory URLByAppendingPathComponent:packageURL.lastPathComponent] options:0 error:error]) return NO;

    NSURL *navURL = [self.bundle URLForResource:@"nav" withExtension:@"xhtml"];
    NSAssert(navURL, @"nav.xhtml resource is missing from action.");

    NSXMLDocument *navDocument = [[NSXMLDocument alloc] initWithContentsOfURL:navURL options:0 error:&internalError];
    NSAssert(navDocument, @"nav.xhtml resource is damaged - %@", internalError);

    NSXMLElement *listElement = [navDocument nodesForXPath:@"//nav/ol" error:&internalError].firstObject;
    NSAssert(listElement, @"nav.xhtml resource is damaged - %@", internalError);

    for (id chapter in chapters) {
        NSURL *url = [[chapter valueForKey:@"url"] URLByAppendingPathComponent:@"pg0001.xhtml"];
        NSString *title = [chapter valueForKey:@"title"];

        NSXMLNode *titleNode = [NSXMLNode textWithStringValue:title];
        NSXMLNode *hrefAttribute = [NSXMLNode attributeWithName:@"href" stringValue:url.relativePath];
        NSXMLElement *aElement = [NSXMLElement elementWithName:@"a" children:@[titleNode] attributes:@[hrefAttribute]];
        NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[aElement] attributes:nil];

        [listElement addChild:liElement];
    }

    if (![[navDocument XMLDataWithOptions:NSXMLNodePrettyPrint] writeToURL:[contentsDirectory URLByAppendingPathComponent:navURL.lastPathComponent] options:0 error:error]) return NO;

    return YES;
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (!input || input.count == 0) return @[];

    [self loadParameters];

    NSURL *workingURL = [self createWorkingDirectory:error];
    if (!workingURL) return nil;

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];
    [self bind:AMFractionCompletedBinding toObject:progress withKeyPath:@"fractionCompleted" options:nil];

    [progress becomeCurrentWithPendingUnitCount:25];
    NSArray<NSDictionary<NSString *, id> *> *chapters = [self copyItemsFromPaths:input toDirectory:workingURL error:error];
    [progress resignCurrent];

    if (!chapters) return nil;
    if (chapters.count == 0) { // This will happen if there are no image files in the input
        if (![[NSFileManager defaultManager] removeItemAtURL:workingURL error:error]) return nil;
        return @[];
    }

    [progress becomeCurrentWithPendingUnitCount:73];
    NSArray<NSURL *> *pages = [self createChapters:chapters error:error];
    [progress resignCurrent];

    if (!pages) return nil;

    NSArray<NSString *> *pagePaths = [pages valueForKeyPath:@"relativePath"];

    [progress becomeCurrentWithPendingUnitCount:1];
    if (![self addMetadataToDirectory:workingURL chapters:chapters spineItems:pagePaths error:error]) return nil;
    [progress resignCurrent];

    [progress becomeCurrentWithPendingUnitCount:1];
    NSURL *outputURL = [self finalizeWorkingDirectory:workingURL error:error];
    [progress resignCurrent];

    return outputURL ? @[outputURL.path] : nil;
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
