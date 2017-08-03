//
//  ImagesToEPUBAction.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "ImagesToEPUBAction.h"
#import "NSXMLDocument+OPFDocumentExtensions.h"
#import "VImageBuffer.h"

@import AppKit.NSColorSpace;
@import AppKit.NSKeyValueBinding;
@import ObjectiveC.runtime;

NS_ASSUME_NONNULL_BEGIN

#if DEBUG
    #define BEGIN_TIMING(TIMER) NSDate *TIMER = [NSDate date]
    #define END_TIMING(TIMER)   [self logMessageWithLevel:AMLogLevelDebug format:@#TIMER " = %f s", [[NSDate date] timeIntervalSinceDate:TIMER]]
#else
    #define BEGIN_TIMING(TIMER) do {} while (0)
    #define END_TIMING(TIMER)   do {} while (0)
#endif

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
    static NSDictionary<NSString *, NSSet<NSString *> *> *extensions;

    static dispatch_once_t onceToken;
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

@interface NSColor (WebColorExtension)

@property (nonatomic, readonly) NSString *webColor;

@end

@implementation NSColor (WebColorExtension)

- (NSString *)webColor {
    NSColor *rgbColor = [self colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSAssert(rgbColor.numberOfComponents == 4, @"Incorrect color space");

    CGFloat fcomponents[4];

    [rgbColor getComponents:fcomponents];

    return [NSString stringWithFormat:@"rgba(%0.0f,%0.0f,%0.0f,%0.2f)", fcomponents[0] * 255.0, fcomponents[1] * 255.0, fcomponents[2] * 255.0, fcomponents[3]];
}

@end

@interface NSFileWrapper (ChapterTitleExtension)

@property (nonatomic, nullable, copy) NSString *title;

@end

@implementation NSFileWrapper (ChapterTitleExtension)

- (nullable NSString *)title {
    return objc_getAssociatedObject(self, "com.the-wabe.title");
}

- (void)setTitle:(nullable NSString *)title {
    objc_setAssociatedObject(self, "com.the-wabe.title", title, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

@end

@interface Frame : NSObject

@property (nonatomic, nonnull) id image;
@property (nonatomic, nonnull, copy) NSString *name;
@property (nonatomic, assign) CGFloat width, height;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithImage:(id)image name:(NSString *)name width:(CGFloat)width height:(CGFloat)height NS_DESIGNATED_INITIALIZER;

@end

@implementation Frame

- (instancetype)initWithImage:(id)image name:(NSString *)name width:(CGFloat)width height:(CGFloat)height {
    self = [super init];

    if (self) {
        self.image = image;
        self.name = name;
        self.width = width;
        self.height = height;
    }

    return self;
}

@end

@interface ImagesToEPUBAction ()

@property (nonatomic, nullable) NSFileWrapper *coverImage;

@end

@implementation ImagesToEPUBAction

- (void)dealloc {
    [self unbind:AMFractionCompletedBinding];
}

- (NSString *)outputFolder {
    return self.parameters[@"outputFolder"];
}

- (NSString *)title {
    NSString *title = self.parameters[@"title"];
    if (title.length == 0) {
        self.parameters[@"title"] = title = @"Untitled";
        [self logMessageWithLevel:AMLogLevelWarn format:@"Title unset; setting to '%@'", title];
    }
    return title;
}

- (NSString *)authors {
    return self.parameters[@"authors"];
}

- (NSString *)publicationID {
    NSString *publicationID = self.parameters[@"publicationID"];
    if (publicationID.length == 0) {
        self.parameters[@"publicationID"] = publicationID = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
        [self logMessageWithLevel:AMLogLevelWarn format:@"Publication ID unset; setting to '%@'", publicationID];
    }
    return publicationID;
}

- (NSUInteger)pageWidth {
    return [self.parameters[@"pageWidth"] unsignedIntegerValue];
}

- (NSUInteger)pageHeight {
    return [self.parameters[@"pageHeight"] unsignedIntegerValue];
}

- (NSUInteger)pageMargin {
    return [self.parameters[@"pageMargin"] unsignedIntegerValue];
}

- (BOOL)disableUpscaling {
    return [self.parameters[@"disableUpscaling"] boolValue];
}

- (NSColor *)backgroundColor {
    NSData *archivedBackgroundColor = self.parameters[@"backgroundColor"];
    return archivedBackgroundColor ? [NSUnarchiver unarchiveObjectWithData:archivedBackgroundColor] : [NSColor whiteColor];
}

- (PageLayoutStyle)layoutStyle {
    return [self.parameters[@"layoutStyle"] unsignedIntegerValue];
}

- (BOOL)doPanelAnalysis {
    return [self.parameters[@"doPanelAnalysis"] boolValue];
}

- (BOOL)firstIsCover {
    return [self.parameters[@"firstIsCover"] boolValue];
}

- (NSURL *)outputURL {
    NSURL *folderURL = [NSURL fileURLWithPath:self.outputFolder.stringByExpandingTildeInPath isDirectory:YES];
    NSString *outputName = [[self.title stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"epub"];
    return [NSURL fileURLWithPath:outputName isDirectory:YES relativeToURL:folderURL];
}

- (nullable NSArray<NSFileWrapper *> *)createChaptersFromPaths:(NSArray<NSString *> *)paths error:(NSError **)error {
    const NSUInteger count = paths.count;

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:count];

    NSMutableArray<NSFileWrapper *> *result = [NSMutableArray arrayWithCapacity:count];

    if (self.firstIsCover) {
        NSURL *inputURL = [NSURL fileURLWithPath:paths.firstObject];
        paths = [paths subarrayWithRange:NSMakeRange(1, paths.count - 1)];

        NSString * _Nonnull typeIdentifier;

        if (![inputURL getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if (typeIsImage(typeIdentifier)) {
            _coverImage = [[NSFileWrapper alloc] initWithURL:inputURL options:0 error:error];
            _coverImage.preferredFilename = [NSString stringWithFormat:@"cover.%@", extensionForType(typeIdentifier)];
            if (!_coverImage) return nil;
        }
        else {
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ is not an image file supported by this action", inputURL.lastPathComponent];
        }
    }

    NSFileWrapper *chapter = nil;

    for (NSString *path in paths) {
        NSURL *inputURL = [NSURL fileURLWithPath:path];

        NSString *typeIdentifier;

        if (![inputURL getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if (typeIsImage(typeIdentifier)) {
            if (self.stopped) return nil;

            NSString *pendingChapter = inputURL.URLByDeletingLastPathComponent.lastPathComponent;

            if (![chapter.title isEqualToString:pendingChapter]) {
                chapter = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{}];
                chapter.title = pendingChapter;

                NSMutableArray<NSString *> *components = [pendingChapter componentsSeparatedByCharactersInSet:NSCharacterSet.URLPathAllowedCharacterSet.invertedSet].mutableCopy;
                [components filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.length > 0"]];
                chapter.preferredFilename = [NSString stringWithFormat:@"%02lu.%@", (unsigned long)(result.count + 1), [components componentsJoinedByString:@"-"].lowercaseString];

                [result addObject:chapter];
            }

            NSAssert(result.count > 0, @"Chapter has not been recorded");

            NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithURL:inputURL options:NSFileWrapperReadingImmediate error:error];
            if (!wrapper) return nil;

            wrapper.preferredFilename = [NSString stringWithFormat:@"im%04lu.%@", chapter.fileWrappers.count + 1, extensionForType(typeIdentifier)];
            [chapter addFileWrapper:wrapper];
        }
        else {
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ is not a file type supported by this action", path.lastPathComponent];
        }

        NSAssert(chapter == nil || chapter.fileWrappers.count > 0, @"Chapter should be non-empty");

        progress.completedUnitCount++;
    }

    return result;
}

- (nullable NSString *)createPage:(NSArray<Frame *> *)page number:(NSUInteger)pageNum inDirectory:(NSFileWrapper *)directory error:(NSError **)error {
    NSAssert(page.count > 0, @"Attempted to generate page with no images");

    const CGFloat contentWidth  = self.pageWidth  - 2 * self.pageMargin;
    const CGFloat contentHeight = self.pageHeight - 2 * self.pageMargin;

    CGFloat usedHeight = [[page valueForKeyPath:@"@sum.height"] doubleValue];

    CGFloat vSpace, y;

    switch (self.layoutStyle) {
        case minimizeInternalSpace:
            vSpace = 0.0;
            y = self.pageMargin + (contentHeight - usedHeight) / 2.0;
            break;

        case maximizeInternalSpace:
            if (page.count > 1) {
                vSpace = (contentHeight - usedHeight) / (CGFloat)(page.count - 1);
                y = self.pageMargin;
                break;
            }

        case distributeInternalSpace: // or maximizeInternalSpace with a single image
            vSpace = (contentHeight - usedHeight) / (CGFloat)(page.count + 1);
            y = self.pageMargin + vSpace;
            break;

        default:
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Unknown layout style %lu", (unsigned long)(self.layoutStyle)] userInfo:nil];
    }

    CGAffineTransform pixelToPercent = CGAffineTransformMakeScale(100.0 / self.pageWidth, 100.0 / self.pageHeight);

    NSURL * _Nonnull templateURL = [self.bundle URLForResource:@"page" withExtension:@"xhtml"];
    if (!templateURL) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml resource missing" userInfo:nil];

    NSError * __autoreleasing underlyingError;

    NSXMLDocument *pageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:templateURL options:0 error:&underlyingError];
    if (!pageDocument) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml failed to load" userInfo:@{NSURLErrorKey:templateURL, NSUnderlyingErrorKey:underlyingError}];

    NSXMLElement *bodyElement = [pageDocument nodesForXPath:@"/html/body" error:&underlyingError].firstObject;
    if (!bodyElement) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml failed to load" userInfo:@{NSURLErrorKey:templateURL, NSUnderlyingErrorKey:underlyingError}];

    [bodyElement addAttribute:[NSXMLNode attributeWithName:@"style" stringValue:[NSString stringWithFormat:@"width:%lupx; height:%lupx; background-color:%@", (unsigned long)(self.pageWidth), (unsigned long)(self.pageHeight), self.backgroundColor.webColor]]];

    NSXMLNode *viewportNode = [pageDocument nodesForXPath:@"/html/head/meta[@name='viewport']/@content" error:&underlyingError].firstObject;
    if (!viewportNode) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"page.xhtml failed to load" userInfo:@{NSURLErrorKey:templateURL, NSUnderlyingErrorKey:underlyingError}];

    viewportNode.stringValue = [NSString stringWithFormat:@"width=%lu, height=%lu", (unsigned long)(self.pageWidth), (unsigned long)(self.pageHeight)];

    for (Frame *frame in page) {
        NSString *name = [frame valueForKey:@"name"];

        CGFloat width = [[frame valueForKey:@"width"] doubleValue];
        CGFloat height = [[frame valueForKey:@"height"] doubleValue];

        CGFloat x = (contentWidth - width) / 2.0 + self.pageMargin;

        CGRect r = CGRectApplyAffineTransform(CGRectMake(x, y, width, height), pixelToPercent);

        NSString *style = [NSString stringWithFormat:@"left:%0.4f%%; top:%0.4f%%; width:%0.4f%%; height:%0.4f%%", r.origin.x, r.origin.y, r.size.width, r.size.height];

        NSXMLNode *srcAttr = [NSXMLNode attributeWithName:@"src" stringValue:name];
        NSXMLNode *altAttr = [NSXMLNode attributeWithName:@"alt" stringValue:@""];
        NSXMLNode *widthAttr = [NSXMLNode attributeWithName:@"width" stringValue:[NSString stringWithFormat:@"%0.0f", r.size.width]];
        NSXMLNode *heightAttr = [NSXMLNode attributeWithName:@"width" stringValue:[NSString stringWithFormat:@"%0.0f", r.size.height]];
        NSXMLNode *styleAttr = [NSXMLNode attributeWithName:@"style" stringValue:style];

        NSXMLElement *imgElement = [NSXMLElement elementWithName:@"img" children:nil attributes:@[srcAttr, altAttr, widthAttr, heightAttr, styleAttr]];

        [bodyElement addChild:imgElement];

        NSXMLNode *classAttr = [NSXMLNode attributeWithName:@"class" stringValue:@"panel-group"];

        NSXMLElement *divElement = [NSXMLElement elementWithName:@"div" children:nil attributes:@[classAttr, styleAttr.copy]];

        [bodyElement addChild:divElement];

        if (self.doPanelAnalysis) {
            id image = [frame valueForKey:@"image"];

            CGFloat originalWidth = CGImageGetWidth((CGImageRef)image);
            CGFloat originalHeight = CGImageGetHeight((CGImageRef)image);

            CGAffineTransform localToGlobal = CGAffineTransformMakeTranslation(x, y);
            localToGlobal = CGAffineTransformScale(localToGlobal, width / originalWidth, height / originalHeight);

            CIImage *ciImage = [CIImage imageWithCGImage:(CGImageRef)(image)];

            ciImage = [ciImage imageByCompositingOverImage:[CIImage imageWithColor:[[CIColor alloc] initWithColor:self.backgroundColor]]];
            ciImage = [ciImage imageByApplyingFilter:@"CIEdges" withInputParameters:nil];
            ciImage = [ciImage imageByApplyingFilter:@"CIMaximumComponent" withInputParameters:nil];
            ciImage = [ciImage imageByCroppingToRect:CGRectMake(0, 0, originalWidth, originalHeight)];

            VImageBuffer *imageBuffer = [[VImageBuffer alloc] initWithCIImage:ciImage error:error];
            if (!imageBuffer) return nil;

            NSArray<NSValue *> *regions = [imageBuffer findRegionsAndReturnError:error];
            if (!regions) return nil;

            for (NSValue *value in regions) {
                CGRect region = NSRectToCGRect(value.rectValue);

                region = CGRectApplyAffineTransform(region, localToGlobal);
                region = CGRectApplyAffineTransform(region, pixelToPercent);

                style = [NSString stringWithFormat:@"left:%0.4f%%; top:%0.4f%%; width:%0.4f%%; height:%0.4f%%", region.origin.x, region.origin.y, region.size.width, region.size.height];

                classAttr = [NSXMLNode attributeWithName:@"class" stringValue:@"panel"];
                styleAttr = [NSXMLNode attributeWithName:@"style" stringValue:style];

                divElement = [NSXMLElement elementWithName:@"div" children:nil attributes:@[classAttr, styleAttr]];

                [bodyElement addChild:divElement];
            }
        }

        y += height;
        y += vSpace;
    }

    NSFileWrapper *chapterWrapper = directory;

    NSFileWrapper *wrapper = [[NSFileWrapper alloc] initRegularFileWithContents:[pageDocument XMLDataWithOptions:NSXMLNodePrettyPrint]];
    wrapper.preferredFilename = [NSString stringWithFormat:@"pg%04lu.xhtml", pageNum];
    return [chapterWrapper.preferredFilename stringByAppendingPathComponent:[chapterWrapper addFileWrapper:wrapper]];
}

- (nullable NSArray<NSString *> *)createPagesForChapters:(NSArray<NSFileWrapper *> *)chapters error:(NSError **)error {
    const CGFloat contentWidth  = self.pageWidth  - 2 * self.pageMargin;
    const CGFloat contentHeight = self.pageHeight - 2 * self.pageMargin;

    NSAssert(contentWidth > 0, @"Content width incorrect");
    NSAssert(contentHeight > 0, @"Content height incorrect");

    NSUInteger count = 0;

    for (NSFileWrapper *chapter in chapters) {
        count += chapter.fileWrappers.count;
    }

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:count];

    NSMutableArray<NSString *> *result = [NSMutableArray array];

    for (NSFileWrapper *chapter in chapters) {
        NSUInteger pageCount = 0;

        NSMutableArray<Frame *> *page = [NSMutableArray array];
        CGFloat currentHeight = 0.0;

        for (NSString *name in [chapter.fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            if (self.stopped) return nil;

            NSFileWrapper *imageWrapper = chapter.fileWrappers[name];

            CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)(imageWrapper.regularFileContents), NULL);

            if (!source) {
                if (error) *error = [NSError errorWithDomain:@"CoreGraphicsErrorDomain" code:__LINE__ userInfo:@{NSFilePathErrorKey:imageWrapper.preferredFilename}];
                return nil;
            }

            id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex(source, 0, NULL));
            CFRelease(source);

            if (!image) {
                if (error) *error = [NSError errorWithDomain:@"CoreGraphicsErrorDomain" code:__LINE__ userInfo:@{NSFilePathErrorKey:imageWrapper.preferredFilename}];
                return nil;
            }

            CGFloat w = CGImageGetWidth((CGImageRef)image);
            CGFloat h = CGImageGetHeight((CGImageRef)image);
            NSString *typeIdentifier = (NSString *)CGImageGetUTType((CGImageRef)image);

            if (!isExtensionCorrectForType(name.pathExtension, typeIdentifier)) {
                NSString *newName = [name.stringByDeletingPathExtension stringByAppendingPathExtension:extensionForType(typeIdentifier)];

                [self logMessageWithLevel:AMLogLevelWarn format:@"%@ has an incorrect extension; should be %@", name, newName];
                [chapter removeFileWrapper:imageWrapper];
                imageWrapper.preferredFilename = newName;
                [chapter addFileWrapper:imageWrapper];
            }

            CGFloat scale = fmin(contentWidth / w, contentHeight / h);

            while ((h * scale > contentHeight) || (w * scale > contentWidth)) {
                scale = nextafter(scale, 0.0);
            }

            if (self.disableUpscaling && scale > 1.0) {
                scale = 1.0;
            }

            NSAssert(w * scale <= contentWidth, @"width: %f, scale: %f, scaled width: %f, max: %f", w, scale, w * scale, contentWidth);
            NSAssert(h * scale <= contentHeight, @"height: %f, scale: %f, scaled height: %f, max: %f", h, scale, h * scale, contentHeight);

            Frame *frame = [[Frame alloc] initWithImage:image name:imageWrapper.preferredFilename width:(w * scale) height:(h * scale)];

            if (currentHeight + h * scale > contentHeight) {
                NSString *pageURL = [self createPage:page number:(++pageCount) inDirectory:chapter error:error];
                if (!pageURL) return nil;

                [result addObject:pageURL];

                page = [NSMutableArray array];
                currentHeight = 0.0;
            }

            [page addObject:frame];
            currentHeight += h * scale;

            progress.completedUnitCount++;
        }

        NSString *pageURL = [self createPage:page number:(++pageCount) inDirectory:chapter error:error];
        if (!pageURL) return nil;

        [result addObject:pageURL];
    }

    return result;
}

- (BOOL)addMetadataToDirectory:(NSFileWrapper *)contentsDirectory chapters:(NSArray<NSFileWrapper *> *)chapters spineItems:(NSArray<NSString *> *)spineItems error:(NSError **)error {
    NSURL *packageURL = [self.bundle URLForResource:@"package" withExtension:@"opf"];
    NSAssert(packageURL, @"package.opf resource is missing from action.");

    NSURL *navURL = [self.bundle URLForResource:@"nav" withExtension:@"xhtml"];
    NSAssert(navURL, @"nav.xhtml resource is missing from action.");

    NSError * __autoreleasing internalError;

    NSXMLDocument *packageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:packageURL options:0 error:&internalError];
    NSAssert(packageDocument, @"package.opf resource is damaged - %@", internalError);

    packageDocument.identifier = self.publicationID;
    packageDocument.title = self.title;
    packageDocument.subject = @"Comic books";
    packageDocument.modified = [NSDate date];

    for (NSString *component in [self.authors componentsSeparatedByString:@";"]) {
        NSMutableArray<NSString *> *components = [component componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].mutableCopy;

        for (NSUInteger index = 0; index < components.count; ++index) {
            if (components[index].length == 0) {
                [components removeObjectAtIndex:(index--)];
            }
        }

        if (components.count == 0) continue;

        NSString *role = components.lastObject;

        if ([role hasPrefix:@"("] && [role hasSuffix:@")"]) {
            role = [role substringWithRange:NSMakeRange(1, role.length - 2)];
            [components removeLastObject];
        }
        else {
            role = nil;
        }

        [packageDocument addAuthor:[components componentsJoinedByString:@" "] role:role];
    }

    for (NSFileWrapper *chapter in chapters) {
        NSString *path = chapter.preferredFilename;

        for (NSString *subpath in [chapter.fileWrappers.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [packageDocument addManifestItem:[path stringByAppendingPathComponent:subpath] properties:nil];
        }
    }

    if (self.coverImage) {
        NSString *filename = [contentsDirectory addFileWrapper:self.coverImage];
        [packageDocument addManifestItem:filename properties:@"cover-image"];
    }

    for (NSString *spineItem in spineItems) {
        [packageDocument addSpineItem:spineItem properties:nil];
    }

    [contentsDirectory addRegularFileWithContents:[packageDocument XMLDataWithOptions:NSXMLNodePrettyPrint] preferredFilename:@"package.opf"];

    NSXMLDocument *navDocument = [[NSXMLDocument alloc] initWithContentsOfURL:navURL options:0 error:&internalError];
    NSAssert(navDocument, @"nav.xhtml resource is damaged - %@", internalError);

    NSXMLElement *listElement = [navDocument nodesForXPath:@"//nav/ol" error:&internalError].firstObject;
    NSAssert(listElement, @"nav.xhtml resource is damaged - %@", internalError);

    for (NSFileWrapper *chapter in chapters) {
        NSString *path  = [chapter.preferredFilename stringByAppendingPathComponent:@"pg0001.xhtml"];
        NSString *title = chapter.title;

        NSXMLNode *titleNode = [NSXMLNode textWithStringValue:title];
        NSXMLNode *hrefAttribute = [NSXMLNode attributeWithName:@"href" stringValue:[path stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet]];
        NSXMLElement *aElement = [NSXMLElement elementWithName:@"a" children:@[titleNode] attributes:@[hrefAttribute]];
        NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[aElement] attributes:nil];

        [listElement addChild:liElement];
    }

    [contentsDirectory addRegularFileWithContents:[navDocument XMLDataWithOptions:NSXMLNodePrettyPrint] preferredFilename:@"nav.xhtml"];

    return !self.stopped;
}

- (NSFileWrapper *)fileWrapperForResource:(NSString *)resource withExtension:(NSString *)extension error:(NSError **)error {
    NSURL *url = [self.bundle URLForResource:resource withExtension:extension];
    if (!url) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:@{NSURLErrorKey:[[self.bundle.resourceURL URLByAppendingPathComponent:resource] URLByAppendingPathExtension:extension], NSLocalizedDescriptionKey:[NSString stringWithFormat:@"The bundle resource “%@.%@” is missing.", resource ? resource : @"*", extension ? extension : @"*"], NSLocalizedFailureReasonErrorKey:@"A bundle resource is missing.", NSLocalizedRecoverySuggestionErrorKey:@"Reinstall the action and try again."}];
        return nil;
    }

    return [[NSFileWrapper alloc] initWithURL:url options:NSFileWrapperReadingImmediate error:error];
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (!input || input.count == 0) return @[];

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];
    [self bind:AMFractionCompletedBinding toObject:progress withKeyPath:@"fractionCompleted" options:nil];

    NSFileWrapper *containerFile = [self fileWrapperForResource:@"container" withExtension:@"xml" error:error];
    if (!containerFile) return nil;

    NSFileWrapper *stylesheetFile = [self fileWrapperForResource:@"contents" withExtension:@"css" error:error];
    if (!stylesheetFile) return nil;

    NSFileWrapper *mimetypeFile      = [[NSFileWrapper alloc] initRegularFileWithContents:[@"application/epub+zip" dataUsingEncoding:NSASCIIStringEncoding]];
    NSFileWrapper *contentsDirectory = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"contents.css":stylesheetFile}];
    NSFileWrapper *metainfoDirectory = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"container.xml":containerFile}];

    NSFileWrapper *epubDirectory = [[NSFileWrapper alloc] initDirectoryWithFileWrappers:@{@"mimetype":mimetypeFile, @"META-INF":metainfoDirectory, @"Contents":contentsDirectory}];

    BEGIN_TIMING(load);
    [progress becomeCurrentWithPendingUnitCount:10];
    NSArray<NSFileWrapper *> *chapters = [self createChaptersFromPaths:input error:error];
    [progress resignCurrent];
    END_TIMING(load);

    if (!chapters) return nil;

    // This will happen if there are no supported image files in the input
    if (chapters.count == 0) return @[];

    for (NSFileWrapper *chapter in chapters) {
        [contentsDirectory addFileWrapper:chapter];
    }

    BEGIN_TIMING(paginate);
    [progress becomeCurrentWithPendingUnitCount:80];
    NSArray<NSString *> *pages = [self createPagesForChapters:chapters error:error];
    [progress resignCurrent];
    END_TIMING(paginate);

    if (!pages) return nil;

    BEGIN_TIMING(metadata);
    [progress becomeCurrentWithPendingUnitCount:1];
    if (![self addMetadataToDirectory:contentsDirectory chapters:chapters spineItems:pages error:error]) return nil;
    [progress resignCurrent];
    END_TIMING(metadata);

    BEGIN_TIMING(write);
    [progress becomeCurrentWithPendingUnitCount:9];
    BOOL success = [epubDirectory writeToURL:self.outputURL options:NSFileWrapperWritingAtomic originalContentsURL:nil error:error];
    [progress resignCurrent];
    END_TIMING(write);

    if (!success) return nil;

    return @[self.outputURL.path];
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
