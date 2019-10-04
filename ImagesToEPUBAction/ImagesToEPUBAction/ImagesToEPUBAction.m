//
//  ImagesToEPUBAction.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "ImagesToEPUBAction.h"
#import "NSXMLDocument+OPFDocumentExtensions.h"

@import AppKit.NSColorSpace;
@import AppKit.NSKeyValueBinding;
@import Darwin.POSIX.sys.xattr;
@import ObjectiveC.runtime;

NS_ASSUME_NONNULL_BEGIN

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

static id relators = nil;

@implementation NSColor (WebColorExtension)

- (NSString *)webColor {
    NSColor *rgbColor = [self colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    NSAssert(rgbColor.numberOfComponents == 4, @"Incorrect color space");

    CGFloat fcomponents[4];

    [rgbColor getComponents:fcomponents];

    return [NSString stringWithFormat:@"rgba(%0.0f,%0.0f,%0.0f,%0.2f)", fcomponents[0] * 255.0, fcomponents[1] * 255.0, fcomponents[2] * 255.0, fcomponents[3]];
}

@end

@interface Frame : NSObject

@property (nonatomic, nonnull, copy) NSString *name;
@property (nonatomic, nonnull, copy) NSArray<NSValue *> *regions;
@property (nonatomic, assign) CGFloat width, height;

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithName:(NSString *)name regions:(NSArray<NSValue *> *)regions width:(CGFloat)width height:(CGFloat)height NS_DESIGNATED_INITIALIZER;

@end

@implementation Frame

- (instancetype)initWithName:(NSString *)name regions:(NSArray<NSValue *> *)regions width:(CGFloat)width height:(CGFloat)height {
    self = [super init];

    if (self) {
        self.name = name;
        self.regions = regions;
        self.width = width;
        self.height = height;
    }

    return self;
}

@end

@implementation NSURL (Regions)

- (NSArray<NSArray *> *)regions {
    ssize_t size = getxattr(self.fileSystemRepresentation, EPUB_REGION_XATTR, NULL, 0, 0, 0);
    if (size < 0 && errno == ENOATTR) return @[];

    if (size < 0) @throw [NSException exceptionWithName:NSGenericException reason:[NSString stringWithFormat:@"Unable to read “%s” attribute on file “%@”: %s", EPUB_REGION_XATTR, self.lastPathComponent, strerror(errno)] userInfo:@{NSURLErrorKey:self}];

    NSMutableData *data = [NSMutableData dataWithLength:size];
    size = getxattr(self.fileSystemRepresentation, EPUB_REGION_XATTR, data.mutableBytes, data.length, 0, 0);
    if (size < 0) @throw [NSException exceptionWithName:NSGenericException reason:[NSString stringWithFormat:@"Unable to read “%s” attribute on file “%@”: %s", EPUB_REGION_XATTR, self.lastPathComponent, strerror(errno)] userInfo:@{NSURLErrorKey:self}];

    NSError * __autoreleasing error;

    id result = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];

    if (!result) @throw [NSException exceptionWithName:NSParseErrorException reason:[NSString stringWithFormat:@"Unable to parse “%s” attribute on file “%@”: %@", EPUB_REGION_XATTR, self.lastPathComponent, error.localizedDescription] userInfo:@{NSURLErrorKey:self}];

    return result;
}

@end

@interface ImagesToEPUBAction ()

@property (nonatomic, nullable) NSURL *contentsURL;
@property (nonatomic, null_resettable) NSURL *outputURL;
@property (nonatomic, nonnull) NSXMLDocument *packageDocument;
@property (nonatomic, nonnull) NSXMLDocument *navDocument;
@property (nonatomic, nonnull) NSXMLDocument *dataNavDocument;

@end

@implementation ImagesToEPUBAction

+ (void)load {
    NSError * __autoreleasing error;

    NSBundle *bundle = [NSBundle bundleForClass:self];
    NSURL *plistURL = [bundle URLForResource:@"MARC" withExtension:@"plist"];
    NSAssert(plistURL, @"“MARC.plist” not found.");

    NSData *data = [NSData dataWithContentsOfURL:plistURL options:NSDataReadingMappedIfSafe error:&error];
    NSAssert(data, @"%@", error.localizedDescription);

    relators = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error];
    NSAssert(relators, @"%@", error.localizedDescription);
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

- (NSString *)publicationID {
    NSString *publicationID = self.parameters[@"publicationID"];
    return publicationID ? publicationID : @"";
}

- (NSDate *)publicationDate {
    NSDate *publicationDate = self.parameters[@"publicationDate"];
    return publicationDate ? publicationDate : [NSDate date];
}

- (NSArray *)creators {
    NSArray *creators = self.parameters[@"creators"];
    return creators ? creators : @[];
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

- (BOOL)firstIsCover {
    return [self.parameters[@"firstIsCover"] boolValue];
}

- (BOOL)syntheticSpread {
    return [self.parameters[@"syntheticSpread"] boolValue];
}

- (id)relators {
    return relators;
}

- (NSURL *)outputURL {
    if (!_outputURL) {
        NSURL *folderURL = [NSURL fileURLWithPath:self.outputFolder.stringByExpandingTildeInPath isDirectory:YES];
        NSString *outputName = [[self.title stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"epub"];
        _outputURL = [NSURL fileURLWithPath:outputName isDirectory:YES relativeToURL:folderURL];
    }

    return _outputURL;
}

- (IBAction)generateNewPublicationID:(nullable id)sender {
    NSString *newID = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
    [self.parameters setValue:newID forKey:@"publicationID"];
    [self parametersUpdated];
}

- (BOOL)copyResource:(NSString *)resource toDirectoryURL:(NSURL *)directoryURL error:(NSError **)error {
    NSURL *url = [self.bundle URLForResource:resource.stringByDeletingPathExtension withExtension:resource.pathExtension];
    NSAssert(url, @"The “%@” resource is missing from the action.", resource);
    return [[NSFileManager defaultManager] copyItemAtURL:url toURL:[directoryURL URLByAppendingPathComponent:resource] error:error];
}

- (NSXMLDocument *)XMLDocumentForResource:(NSString *)resource {
    NSURL *url = [self.bundle URLForResource:resource.stringByDeletingPathExtension withExtension:resource.pathExtension];
    NSAssert(url, @"The “%@” resource is missing from the action.", resource);

    NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:NULL];
    NSAssert(document, @"The “%@” resource is damaged.", resource);

    return document;
}

- (nullable NSURL *)prepareDestinationDirectoryForURL:(NSURL *)url error:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *destinationURL = [fileManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:url create:YES error:error];
    if (!destinationURL) return nil;

    NSData *data = [@"application/epub+zip" dataUsingEncoding:NSASCIIStringEncoding];
    if (![data writeToURL:[destinationURL URLByAppendingPathComponent:@"mimetype"] options:0 error:error]) return nil;

    NSURL *metaInfURL = [destinationURL URLByAppendingPathComponent:@"META-INF" isDirectory:YES];
    if (![fileManager createDirectoryAtURL:metaInfURL withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    if (![self copyResource:@"container.xml" toDirectoryURL:metaInfURL error:error]) return nil;

    self.contentsURL = [destinationURL URLByAppendingPathComponent:@"Contents" isDirectory:YES];
    if (![fileManager createDirectoryAtURL:self.contentsURL withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    if (![self copyResource:@"contents.css" toDirectoryURL:self.contentsURL error:error]) return nil;

    self.packageDocument = [self XMLDocumentForResource:@"package.opf"];
    self.navDocument     = [self XMLDocumentForResource:@"nav.xhtml"];
    self.dataNavDocument = [self XMLDocumentForResource:@"data-nav.xhtml"];

    return destinationURL;
}

- (nullable NSDictionary<NSString *, NSArray<Frame *> *> *)createChaptersFromPaths:(NSArray<NSString *> *)paths error:(NSError **)error {
    const CGFloat contentWidth  = self.pageWidth  - 2 * self.pageMargin;
    const CGFloat contentHeight = self.pageHeight - 2 * self.pageMargin;

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:paths.count];

    NSXMLElement *olElement = [self.navDocument nodesForXPath:@"//nav[@epub:type='toc']/ol" error:NULL].firstObject;
    NSAssert(olElement, @"The “nav.xhtml” resource is damaged.");

    if (self.firstIsCover) {
        NSURL *inputURL = [NSURL fileURLWithPath:paths.firstObject];
        paths = [paths subarrayWithRange:NSMakeRange(1, paths.count - 1)];

        NSString * __autoreleasing typeIdentifier;

        if (![inputURL getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if (typeIsImage(typeIdentifier)) {
            NSString *filename = [NSString stringWithFormat:@"cover.%@", extensionForType(typeIdentifier)];
            if (![fileManager copyItemAtURL:inputURL toURL:[self.contentsURL URLByAppendingPathComponent:filename] error:error]) return nil;
            [self.packageDocument addManifestItem:filename properties:@"cover-image"];
        }
        else {
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ is not an image file supported by this action.", inputURL.lastPathComponent];
        }

        ++progress.completedUnitCount;
    }

    NSString *chapter = nil;
    NSString *title = @"";
    NSString *bodymatter = nil;

    NSUInteger chapterIndex = 0;
    NSUInteger index = 0;

    NSMutableDictionary<NSString *, NSMutableArray<Frame *> *> *chapters = [NSMutableDictionary dictionary];

    for (NSString *path in paths) {
        NSURL *inputURL = [NSURL fileURLWithPath:path];

        NSString *typeIdentifier;

        if (![inputURL getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if (typeIsImage(typeIdentifier)) {
            if (self.stopped) return nil;

            NSString *pendingChapter = inputURL.URLByDeletingLastPathComponent.lastPathComponent;

            if (![title isEqualToString:pendingChapter]) {
                title = pendingChapter;

                NSMutableArray<NSString *> *components = [pendingChapter componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet].mutableCopy;
                [components filterUsingPredicate:[NSPredicate predicateWithFormat:@"SELF.length > 0"]];
                if ([components count] == 0) components = @[@"untitled"].mutableCopy;

                chapter = [NSString stringWithFormat:@"%02lu.%@", (unsigned long)(++chapterIndex), [components componentsJoinedByString:@"-"].lowercaseString];

                if (![fileManager createDirectoryAtURL:[self.contentsURL URLByAppendingPathComponent:chapter] withIntermediateDirectories:YES attributes:nil error:error]) return nil;

                chapters[chapter] = [NSMutableArray array];

                [olElement addChild:[NSXMLElement elementWithName:@"li" children:@[[NSXMLElement elementWithName:@"a" children:@[[NSXMLNode textWithStringValue:title]] attributes:@[[NSXMLNode attributeWithName:@"href" stringValue:[chapter stringByAppendingPathComponent:@"pg0001.xhtml"]]]]] attributes:nil]];

                index = 0;
            }

            NSString *filename = [NSString stringWithFormat:@"im%04lu.%@", (unsigned long)(++index), extensionForType(typeIdentifier)];
            NSString *relativePath = [chapter stringByAppendingPathComponent:filename];

            NSURL *outputURL = [self.contentsURL URLByAppendingPathComponent:relativePath];

            id source = CFBridgingRelease(CGImageSourceCreateWithURL((CFURLRef)inputURL, NULL));

            if (!source) {
                if (error) *error = [NSError errorWithDomain:@"CoreGraphicsErrorDomain" code:__LINE__ userInfo:@{NSURLErrorKey:inputURL}];
                return NO;
            }

            id image = CFBridgingRelease(CGImageSourceCreateImageAtIndex((CGImageSourceRef)source, 0, NULL));

            if (!image) {
                if (error) *error = [NSError errorWithDomain:@"CoreGraphicsErrorDomain" code:__LINE__ userInfo:@{NSURLErrorKey:inputURL}];
                return NO;
            }

            CGFloat w = CGImageGetWidth((CGImageRef)image);
            CGFloat h = CGImageGetHeight((CGImageRef)image);
            NSString *typeIdentifier = (NSString *)CGImageGetUTType((CGImageRef)image);

            NSMutableArray<NSValue *> *regions = [NSMutableArray array];

            CGAffineTransform pixelToFraction = CGAffineTransformMakeScale(1.0 / w, 1.0 / h);

            for (NSArray *region in inputURL.regions) {
                CGRect r = CGRectMake([region[0] doubleValue], [region[1] doubleValue], [region[2] doubleValue], [region[3] doubleValue]);
                [regions addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectApplyAffineTransform(r, pixelToFraction))]];
            }

            if (!isExtensionCorrectForType(outputURL.pathExtension, typeIdentifier)) {
                outputURL = [outputURL.URLByDeletingPathExtension URLByAppendingPathExtension:extensionForType(typeIdentifier)];
                [self logMessageWithLevel:AMLogLevelWarn format:@"%@ has an incorrect extension; should be “%@”", inputURL.lastPathComponent, outputURL.pathExtension];
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

            Frame *frame = [[Frame alloc] initWithName:outputURL.lastPathComponent regions:regions width:(w * scale) height:(h * scale)];

            if (![fileManager copyItemAtURL:inputURL toURL:outputURL error:error]) return nil;

            [self.packageDocument addManifestItem:relativePath properties:nil];

            [chapters[chapter] addObject:frame];
        }
        else {
            [self logMessageWithLevel:AMLogLevelWarn format:@"%@ is not a file type supported by this action", path.lastPathComponent];
        }

        ++progress.completedUnitCount;
    }

    if (bodymatter) {
        NSXMLElement *olElement = [self.navDocument nodesForXPath:@"//nav[@epub:type='landmarks']/ol" error:NULL].firstObject;
        NSAssert(olElement, @"The “nav.xhtml” resource is damaged.");

        NSXMLNode *typeAttr = [NSXMLNode attributeWithName:@"epub:type" stringValue:@"bodymatter"];
        NSXMLNode *hrefAttr = [NSXMLNode attributeWithName:@"href" stringValue:bodymatter];
        NSXMLNode *textNode = [NSXMLNode textWithStringValue:@"Start of Content"];

        NSXMLElement *aElement = [NSXMLElement elementWithName:@"a" children:@[textNode] attributes:@[typeAttr, hrefAttr]];
        NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[aElement] attributes:nil];

        [olElement addChild:liElement];
    }

    return chapters;
}

- (BOOL)createPage:(NSString *)pageName fromFrames:(NSArray<Frame *> *)frames error:(NSError **)error {
    NSAssert(frames.count > 0, @"Attempted to generate page with no images");

    NSXMLElement *dataNavOLElement = [self.dataNavDocument nodesForXPath:@"//ol" error:NULL].firstObject;
    NSAssert(dataNavOLElement, @"The “data-nav.xhtml” resource is damaged.");

    const CGFloat contentWidth  = self.pageWidth  - 2 * self.pageMargin;
    const CGFloat contentHeight = self.pageHeight - 2 * self.pageMargin;

    CGFloat usedHeight = [[frames valueForKeyPath:@"@sum.height"] doubleValue];

    CGFloat vSpace, y;

    switch (self.layoutStyle) {
        case minimizeInternalSpace:
            vSpace = 0.0;
            y = self.pageMargin + (contentHeight - usedHeight) / 2.0;
            break;

        case maximizeInternalSpace:
            if (frames.count > 1) {
                vSpace = (contentHeight - usedHeight) / (CGFloat)(frames.count - 1);
                y = self.pageMargin;
                break;
            }

        case distributeInternalSpace: // or maximizeInternalSpace with a single image
            vSpace = (contentHeight - usedHeight) / (CGFloat)(frames.count + 1);
            y = self.pageMargin + vSpace;
            break;

        default:
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"bad value for self.layoutStyle" userInfo:nil];
    }

    CGAffineTransform pixelToPercent = CGAffineTransformMakeScale(100.0 / self.pageWidth, 100.0 / self.pageHeight);

    NSXMLDocument *pageDocument = [self XMLDocumentForResource:@"page.xhtml"];

    NSError * __autoreleasing underlyingError;

    NSXMLElement *bodyElement = [pageDocument nodesForXPath:@"/html/body" error:&underlyingError].firstObject;
    NSAssert(bodyElement, @"The “page.xhtml” resource is damaged.");

    [bodyElement addAttribute:[NSXMLNode attributeWithName:@"style" stringValue:[NSString stringWithFormat:@"width:%lupx; height:%lupx; background-color:%@", (unsigned long)(self.pageWidth), (unsigned long)(self.pageHeight), self.backgroundColor.webColor]]];

    NSXMLNode *viewportNode = [pageDocument nodesForXPath:@"/html/head/meta[@name='viewport']/@content" error:&underlyingError].firstObject;
    NSAssert(viewportNode, @"The “page.xhtml” resource is damaged.");

    viewportNode.stringValue = [NSString stringWithFormat:@"width=%lu, height=%lu", (unsigned long)(self.pageWidth), (unsigned long)(self.pageHeight)];

    NSXMLNode *panelGroupTypeAttr = [NSXMLNode attributeWithName:@"epub:type" stringValue:@"panel-group"];
    NSXMLNode *panelTypeAttr = [NSXMLNode attributeWithName:@"epub:type" stringValue:@"panel"];

    for (Frame *frame in frames) {
        if (self.stopped) return NO;

        NSString *name = [frame valueForKey:@"name"];

        CGFloat width = [[frame valueForKey:@"width"] doubleValue];
        CGFloat height = [[frame valueForKey:@"height"] doubleValue];

        NSArray<NSValue *> *regions = [frame valueForKey:@"regions"];

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

        r = CGRectIntegral(r);
        NSString *href = [NSString stringWithFormat:@"%@#xywh=percent:%0.0f,%0.0f,%0.0f,%0.0f", pageName, r.origin.x, r.origin.y, r.size.width, r.size.height];

        NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[[NSXMLElement elementWithName:@"a" children:nil attributes:@[[NSXMLNode attributeWithName:@"href" stringValue:href]]]] attributes:@[panelGroupTypeAttr.copy]];

        [dataNavOLElement addChild:liElement];

        NSXMLElement *subNavOLElement = nil;

        CGAffineTransform regionToPercent = CGAffineTransformTranslate(pixelToPercent, x, y);
        regionToPercent = CGAffineTransformScale(regionToPercent, width, height);

        for (NSValue *value in regions) {
            CGRect r = CGRectIntegral(CGRectApplyAffineTransform(NSRectToCGRect(value.rectValue), regionToPercent));

            if (!subNavOLElement) {
                subNavOLElement = [NSXMLElement elementWithName:@"ol"];
                [liElement addChild:subNavOLElement];
            }

            NSString *href = [NSString stringWithFormat:@"%@#xywh=percent:%0.0f,%0.0f,%0.0f,%0.0f", pageName, r.origin.x, r.origin.y, r.size.width, r.size.height];

            NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[[NSXMLElement elementWithName:@"a" children:nil attributes:@[[NSXMLNode attributeWithName:@"href" stringValue:href]]]] attributes:@[panelTypeAttr.copy]];

            [subNavOLElement addChild:liElement];
        }

        y += height;
        y += vSpace;
    }

    NSData *data = [pageDocument XMLDataWithOptions:NSXMLNodePrettyPrint];
    NSURL  *url  = [self.contentsURL URLByAppendingPathComponent:pageName];

    if (![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;

    [self.packageDocument addSpineItem:pageName properties:nil];

    return YES;
}

- (BOOL)createPagesForChapters:(NSDictionary<NSString *, NSArray<Frame *> *> *)chapters error:(NSError **)error {
    const CGFloat contentHeight = self.pageHeight - 2 * self.pageMargin;

    NSUInteger count = [[chapters.allValues valueForKeyPath:@"@unionOfArrays.self"] count];

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:count];

    for (NSString *chapterName in [chapters.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSUInteger pageCount = 0;

        NSMutableArray<Frame *> *frames = [NSMutableArray array];
        CGFloat currentHeight = 0.0;

        for (Frame *frame in chapters[chapterName]) {
            if (self.stopped) return NO;

            if (currentHeight + frame.height > contentHeight) {
                NSString *pageName = [NSString stringWithFormat:@"%@/pg%04lu.xhtml", chapterName, (unsigned long)(++pageCount)];
                if (![self createPage:pageName fromFrames:frames error:error]) return NO;

                frames = [NSMutableArray array];
                currentHeight = 0.0;
            }

            [frames addObject:frame];
            currentHeight += frame.height;

            ++progress.completedUnitCount;
        }

        NSString *pageName = [NSString stringWithFormat:@"%@/pg%04lu.xhtml", chapterName, (unsigned long)(++pageCount)];
        if (![self createPage:pageName fromFrames:frames error:error]) return NO;
    }

    return YES;
}

- (BOOL)writeMetadataFilesAndReturnError:(NSError **)error {
    NSXMLDocument *packageDocument = self.packageDocument;

    NSProgress *progress = [NSProgress progressWithTotalUnitCount:4];

    packageDocument.identifier = self.publicationID;
    packageDocument.title = self.title;
    packageDocument.date = self.publicationDate;
    packageDocument.subject = @"Comic books";
    packageDocument.modified = [NSDate date];
    packageDocument.landscapeOrientation = self.pageWidth > self.pageHeight;
    packageDocument.syntheticSpread = self.syntheticSpread;

    for (id creator in self.creators) {
        NSString *displayName = [creator valueForKey:@"displayName"];
        NSString *fileAsName = [creator valueForKey:@"fileAsName"];
        NSString *role = [creator valueForKey:@"role"];

        [packageDocument addCreator:displayName fileAs:fileAsName role:role];
    }

    ++progress.completedUnitCount;

    if (![[packageDocument XMLDataWithOptions:NSXMLNodePrettyPrint|NSXMLNodeCompactEmptyElement] writeToURL:[self.contentsURL URLByAppendingPathComponent:@"package.opf"] options:NSDataWritingAtomic error:error]) return NO;

    ++progress.completedUnitCount;

    if (![[self.navDocument XMLDataWithOptions:NSXMLNodePrettyPrint|NSXMLNodeCompactEmptyElement] writeToURL:[self.contentsURL URLByAppendingPathComponent:@"nav.xhtml"] options:NSDataWritingAtomic error:error]) return NO;

    ++progress.completedUnitCount;

    if (![[self.dataNavDocument XMLDataWithOptions:NSXMLNodePrettyPrint|NSXMLNodeCompactEmptyElement] writeToURL:[self.contentsURL URLByAppendingPathComponent:@"data-nav.xhtml"] options:NSDataWritingAtomic error:error]) return NO;

    ++progress.completedUnitCount;

    return YES;
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (!input || input.count == 0) return @[];

    if (self.pageHeight <= 2 * self.pageMargin) {
        @throw [NSException exceptionWithName:NSGenericException reason:@"Content height is too small." userInfo:nil];
    }
    if (self.pageWidth <= 2 * self.pageMargin) {
        @throw [NSException exceptionWithName:NSGenericException reason:@"Content width is too small." userInfo:nil];
    }
    if (self.publicationID.length == 0) {
        @throw [NSException exceptionWithName:NSGenericException reason:@"Publication ID is required." userInfo:nil];
    }

    self.outputURL = nil;

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];
    [progress addObserver:self forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionInitial context:NULL];

    NSURL *destinationURL = [self prepareDestinationDirectoryForURL:self.outputURL error:error];

    if (!destinationURL) return nil;

    [progress becomeCurrentWithPendingUnitCount:65];
    NSDictionary<NSString *, NSArray<Frame *> *> *chapters = [self createChaptersFromPaths:input error:error];
    [progress resignCurrent];

    if (!chapters) return nil;

    [progress becomeCurrentWithPendingUnitCount:30];
    BOOL success = [self createPagesForChapters:chapters error:error];
    [progress resignCurrent];

    if (!success) return nil;

    [progress becomeCurrentWithPendingUnitCount:4];
    success = [self writeMetadataFilesAndReturnError:error];
    [progress resignCurrent];

    if (!success) return nil;

    NSURL * __autoreleasing resultingItemURL;

    [progress becomeCurrentWithPendingUnitCount:1];
    success = [[NSFileManager defaultManager] replaceItemAtURL:self.outputURL withItemAtURL:destinationURL backupItemName:nil options:0 resultingItemURL:&resultingItemURL error:error];
    [progress resignCurrent];

    return success ? @[resultingItemURL.path] : nil;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context {
    const double fractionCompleted = [object fractionCompleted];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressValue = fractionCompleted;
    });
}

@end

NS_ASSUME_NONNULL_END
