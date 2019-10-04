//
//  CreateEPUBAction.m
//  CreateEPUBAction
//
//  Created by Rob Menke on 8/13/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

#import "CreateEPUBAction.h"

NS_ASSUME_NONNULL_BEGIN

// These have to be macros to allow string pasting.

#define NS_OPF   @"http://www.idpf.org/2007/opf"
#define NS_DC    @"http://purl.org/dc/elements/1.1/"
#define NS_XHTML @"http://www.w3.org/1999/xhtml"
#define NS_EPUB  @"http://www.idpf.org/2007/ops"

#define PACKAGE_QUERY(QUERY) @"declare default element namespace \"" NS_OPF "\"; declare namespace dc = \"" NS_DC "\"; " QUERY
#define DOC_QUERY(QUERY) @"declare default element namespace \"" NS_XHTML "\"; declare namespace epub = \"" NS_EPUB "\"; " QUERY

NSString * const EPUBOutputFolderProperty = @"outputFolder";
NSString * const EPUBIdentifierProperty = @"publicationID";
NSString * const EPUBTitleProperty = @"title";
NSString * const EPUBCollectionProperty = @"collection";
NSString * const EPUBDateProperty = @"publicationDate";
NSString * const EPUBCreatorsProperty = @"creators";

NSString * const EPUBManifestItemTitleKey = @"title";
NSString * const EPUBManifestItemSpineKey = @"spine";
NSString * const EPUBManifestItemURLKey = @"url";
NSString * const EPUBManifestItemFileTypeIdentifierKey = @"type";

NSString * const EPUBCreatorDisplayNameKey = @"displayName";
NSString * const EPUBCreatorFileAsKey = @"fileAsName";
NSString * const EPUBCreatorRoleKeyPath = @"role.code";
NSString * const EPUBCreatorSchemeKeyPath = @"role.scheme";

@implementation NSString (UTTypes)

- (BOOL)typeConformsTo:(NSString *)type {
    return UTTypeConformsTo((__bridge CFStringRef)self, (__bridge CFStringRef)type);
}

- (NSString *)mimeTypeForType {
    return CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)self, kUTTagClassMIMEType));
}

@end

@implementation NSXMLNode (ExceptionRaisingOperations)

- (NSArray *)objectsForXQuery:(NSString *)xquery {
    NSError * __autoreleasing error;
    NSArray *array = [self objectsForXQuery:xquery error:&error];
    if (!array) @throw [NSException exceptionWithName:NSGenericException reason:error.localizedFailureReason userInfo:@{NSUnderlyingErrorKey:error}];
    return array;
}

- (NSArray *)objectsForXQuery:(NSString *)xquery constants:(nullable NSDictionary<NSString *,id> *)constants {
    NSError * __autoreleasing error;
    NSArray *array = [self objectsForXQuery:xquery constants:constants error:&error];
    if (!array) @throw [NSException exceptionWithName:NSGenericException reason:error.localizedFailureReason userInfo:@{NSUnderlyingErrorKey:error}];
    return array;
}

@end

@interface CreateEPUBAction ()

@property (nonatomic, readonly) NSString *outputFolder;
@property (nonatomic, nullable, readonly) NSString *title;
@property (nonatomic, nullable, readonly) NSString *collection;
@property (nonatomic, nullable, readonly) NSString *groupPosition;
@property (nonatomic, nullable, readonly) NSString *publicationIdentifier;
@property (nonatomic, readonly) NSString *publicationDate;
@property (nonatomic, readonly) NSArray *creators;

@property (nonatomic, readonly) NSURL *outputURL;
@property (nonatomic, readonly) NSDateFormatter *dateFormatter;

@property (nonatomic, readonly) NSRegularExpression *collectionRegularExpression;

@property (nonatomic, readwrite) double fractionCompleted;

@end

@implementation CreateEPUBAction {
    NSDateFormatter *_dateFormatter;
    NSDictionary<NSString *,NSDictionary<NSString *,id> *> *_relators;
}

- (NSDateFormatter *)dateFormatter {
    if (!_dateFormatter) {
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        _dateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    }
    return _dateFormatter;
}

- (NSDictionary<NSString *,NSDictionary<NSString *,id> *> *)relators {
    if (!_relators) {
        NSError * __autoreleasing error;
        
        NSBundle *bundle = [NSBundle bundleForClass:self.class];

        NSURL *url = [bundle URLForResource:@"Relators" withExtension:@"plist"];
        NSAssert(url, @"Unable to locate resource “Relators.plist.”");

        NSData *data = [[NSData alloc] initWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error];
        NSAssert(data, @"Unable to read resource: %@", error.localizedFailureReason);

        _relators = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&error];
        NSAssert(_relators, @"Unable to read resource: %@", error.localizedFailureReason);
    }

    return _relators;
}

- (NSString *)outputFolder {
    NSString * _Nullable outputFolder = self.parameters[EPUBOutputFolderProperty];
    return (outputFolder ? outputFolder : @"~/Desktop").stringByStandardizingPath;
}

- (nullable NSString *)publicationIdentifier {
    return self.parameters[EPUBIdentifierProperty];
}

- (nullable NSString *)title {
    return self.parameters[EPUBTitleProperty];
}

- (nullable NSString *)collection {
    NSString * _Nullable collection = self.parameters[EPUBCollectionProperty];
    return [_collectionRegularExpression stringByReplacingMatchesInString:collection options:0 range:NSMakeRange(0, collection.length) withTemplate:@""];
}

- (nullable NSString *)groupPosition {
    NSString * _Nullable collection = self.parameters[EPUBCollectionProperty];
    NSTextCheckingResult * _Nullable result = [_collectionRegularExpression firstMatchInString:collection options:0 range:NSMakeRange(0, collection.length)];

    if (result && result.range.location != NSNotFound) {
        return [collection substringWithRange:[result rangeAtIndex:1]];
    }

    return nil;
}

- (NSString *)publicationDate {
    NSDate *publicationDate = self.parameters[EPUBDateProperty];
    if (!publicationDate) publicationDate = [NSDate date];

    return [self.dateFormatter stringFromDate:publicationDate];
}

- (NSArray *)creators {
    NSArray *creators = self.parameters[EPUBCreatorsProperty];
    return creators ? creators : @[];
}

- (NSURL *)outputURL {
    NSString *title = [self.title stringByReplacingOccurrencesOfString:@"/" withString:@":"];

    return [NSURL fileURLWithPath:[title stringByAppendingPathExtension:@"epub"]
                      isDirectory:YES
                    relativeToURL:[NSURL fileURLWithPath:self.outputFolder]];
}

- (IBAction)generateNewPublicationID:(nullable id)sender {
    NSString *newID = [@"urn:uuid:" stringByAppendingString:NSUUID.UUID.UUIDString];
    [self.parameters setValue:newID forKey:EPUBIdentifierProperty];
    [self parametersUpdated];
}

- (NSArray<NSDictionary<NSString *, id> *> *)copyItemsAtPaths:(NSArray<NSString *> *)paths
                                             toDirectoryAtURL:(NSURL *)directoryURL
                                                        error:(NSError **)error {
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:paths.count];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableSet<NSString *> *components = [NSMutableSet set];

    NSMutableArray<NSDictionary<NSString *, id> *> *result = [NSMutableArray arrayWithCapacity:paths.count];

    for (NSString *path in paths) {
        NSURL *srcURL = [NSURL fileURLWithPath:path];
        NSString *component = srcURL.lastPathComponent;

        if ([components containsObject:component]) {
            NSString *basename = component.stringByDeletingPathExtension;
            NSString *extension = component.pathExtension;

            NSUInteger index = 1;

            do {
                component = [NSString stringWithFormat:@"%@-%lu.%@", basename, ++index, extension];
            } while ([components containsObject:component]);
        }

        [components addObject:component];

        NSMutableDictionary<NSString *, id> *itemInfo = [NSMutableDictionary dictionary];

        NSString * __autoreleasing typeIdentifier;

        if (![srcURL getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if ([typeIdentifier typeConformsTo:@"public.xhtml"]) {
            NSXMLDocument *document = [[NSXMLDocument alloc] initWithContentsOfURL:srcURL options:0 error:error];
            if (!document) return nil;

            NSArray *result = [document objectsForXQuery:DOC_QUERY("/html/head/title")];
            NSString *title = [result.firstObject stringValue];

            result = [document objectsForXQuery:DOC_QUERY("/html/head/meta[@name='epub:toc']/@content = 'omit'")];

            if (![result.firstObject boolValue]) {
                itemInfo[EPUBManifestItemTitleKey] = title;
            }

            itemInfo[EPUBManifestItemSpineKey] = @YES;
        }

        NSURL *dstURL = [NSURL fileURLWithPath:component relativeToURL:directoryURL];

        itemInfo[EPUBManifestItemFileTypeIdentifierKey] = typeIdentifier;
        itemInfo[EPUBManifestItemURLKey] = dstURL;

        if (![fileManager copyItemAtURL:srcURL toURL:dstURL error:error]) return nil;

        [result addObject:itemInfo];

        ++progress.completedUnitCount;
    }

    return result;
}

- (BOOL)addPackageMetadataToDirectoryAtURL:(NSURL *)baseURL
                                  manifest:(NSArray<NSDictionary<NSString *, id> *> *)manifest
                                     error:(NSError **)error {
    NSData *mimetypeData = [@"application/epub+zip" dataUsingEncoding:NSASCIIStringEncoding];
    if (![mimetypeData writeToURL:[NSURL fileURLWithPath:@"mimetype" relativeToURL:baseURL] options:NSDataWritingAtomic error:error]) return NO;

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *metadataURL = [NSURL fileURLWithPath:@"META-INF" isDirectory:YES relativeToURL:baseURL];

    if (![fileManager createDirectoryAtURL:metadataURL withIntermediateDirectories:NO attributes:nil error:error]) return NO;

    NSBundle *bundle = self.bundle;

    NSURL *containerURL = [bundle URLForResource:@"container" withExtension:@"xml"];
    NSAssert(containerURL, @"“container.xml” missing from bundle.");

    if (![fileManager copyItemAtURL:containerURL toURL:[NSURL fileURLWithPath:containerURL.lastPathComponent relativeToURL:metadataURL] error:error]) return NO;

    NSURL *packageURL = [bundle URLForResource:@"package" withExtension:@"opf"];
    NSAssert(packageURL, @"“package.opf” missing from bundle.");

    NSXMLDocument *packageDocument = [[NSXMLDocument alloc] initWithContentsOfURL:packageURL options:0 error:error];
    if (!packageDocument) return NO;

    NSURL *navURL = [bundle URLForResource:@"nav" withExtension:@"xhtml"];
    NSAssert(navURL, @"“nav.xhtml” missing from bundle.");

    NSXMLDocument *navDocument = [[NSXMLDocument alloc] initWithContentsOfURL:navURL options:0 error:error];
    if (!navDocument) return NO;

    NSXMLElement *packageElement = [packageDocument rootElement];

    NSXMLElement *metadataElement = [packageElement elementsForLocalName:@"metadata" URI:NS_OPF].firstObject;
    NSAssert(metadataElement, @"“package.opf” file damaged.");

    NSXMLElement *identifierElement = [metadataElement objectsForXQuery:PACKAGE_QUERY("dc:identifier[@id='pub-id']")].firstObject;
    NSAssert(identifierElement, @"“package.opf” file damaged.");

    identifierElement.stringValue = self.publicationIdentifier;

    NSXMLElement *titleElement = [metadataElement objectsForXQuery:PACKAGE_QUERY("dc:title[@id='main-title']")].firstObject;
    NSAssert(titleElement, @"“package.opf” file damaged.");

    titleElement.stringValue = self.title;

    NSUInteger index = 0;

#define T(STRING) [NSXMLNode textWithStringValue:(STRING)]
#define A(NAME, STRING) [NSXMLNode attributeWithName:@#NAME stringValue:(STRING)]

    for (id creator in self.creators) {
        NSString * _Nonnull  displayName = [creator valueForKey:EPUBCreatorDisplayNameKey];
        NSString * _Nullable fileAsName = [creator valueForKey:EPUBCreatorFileAsKey];
        NSString * _Nullable role = [creator valueForKeyPath:EPUBCreatorRoleKeyPath];
        NSString * _Nullable scheme = [creator valueForKeyPath:EPUBCreatorSchemeKeyPath];

        NSAssert((role == nil) || (scheme != nil), @"Cannot have a role without a scheme.");
        NSAssert((scheme == nil) || (role != nil), @"Cannot have a scheme without a role.");

        NSString *ident = [NSString stringWithFormat:@"creator-%lu", (unsigned long)(++index)];

        NSXMLElement *element = [NSXMLElement elementWithName:@"dc:creator" children:@[T(displayName)] attributes:@[A(id, ident)]];
        [metadataElement addChild:element];

        ident = [@"#" stringByAppendingString:ident];

        if (role.length) {
            element = [NSXMLElement elementWithName:@"meta" children:@[T(role)] attributes:@[A(refines, ident), A(property, @"role"), A(scheme, scheme)]];
            [metadataElement addChild:element];
        }

        if (fileAsName.length) {
            element = [NSXMLElement elementWithName:@"meta" children:@[T(fileAsName)] attributes:@[A(refines, ident), A(property, @"file-as")]];
            [metadataElement addChild:element];
        }
    }

    NSXMLElement *dateElement = [metadataElement objectsForXQuery:PACKAGE_QUERY("dc:date")].firstObject;
    NSAssert(dateElement, @"“package.opf” file damaged.");

    dateElement.stringValue = self.publicationDate;
    
    NSXMLElement *modifiedElement = [metadataElement objectsForXQuery:PACKAGE_QUERY("meta[@property='dcterms:modified']")].firstObject;
    NSAssert(modifiedElement, @"“package.opf” file damaged.");

    modifiedElement.stringValue = [self.dateFormatter stringFromDate:[NSDate date]];

    NSString * _Nullable collection = self.collection;

    if (collection) {
        NSXMLElement *metaElement = [NSXMLElement elementWithName:@"meta" children:@[T(collection)] attributes:@[A(id, @"collection"), A(property, @"belongs-to-collection")]];
        [metadataElement addChild:metaElement];

        metaElement = [NSXMLElement elementWithName:@"meta" children:@[T(@"series")] attributes:@[A(refines, @"#collection"), A(property, @"collection-type")]];
        [metadataElement addChild:metaElement];

        NSString * _Nullable groupPosition = self.groupPosition;

        if (groupPosition) {
            metaElement = [NSXMLElement elementWithName:@"meta" children:@[T(groupPosition)] attributes:@[A(refines, @"#collection"), A(property, @"group-position")]];
            [metadataElement addChild:metaElement];
        }
    }

    NSXMLElement *manifestElement = [packageDocument objectsForXQuery:PACKAGE_QUERY("/package/manifest")].firstObject;
    NSAssert(manifestElement, @"“package.opf” file damaged.");

    NSXMLElement *spineElement = [packageDocument objectsForXQuery:PACKAGE_QUERY("/package/spine")].firstObject;
    NSAssert(spineElement, @"“package.opf” file damaged.");

    NSXMLElement *tocElement = [navDocument objectsForXQuery:DOC_QUERY("//nav[@epub:type='toc']/ol")].firstObject;
    NSAssert(tocElement, @"“nav.xhtml” file damaged.");

    NSXMLElement *landmarksElement = [navDocument objectsForXQuery:DOC_QUERY("//nav[@epub:type='landmarks']/ol")].firstObject;
    NSAssert(landmarksElement, @"“nav.xhtml” file damaged.");

    index = 0;

    NSString *bodymatter = nil;

    for (NSDictionary<NSString *, id> *manifestItem in manifest) {
        NSString *ident     = [NSString stringWithFormat:@"manifest-%lu", ++index];
        NSString *url       = [manifestItem[EPUBManifestItemURLKey] lastPathComponent];
        BOOL      spine     = [manifestItem[EPUBManifestItemSpineKey] boolValue];
        NSString *title     = manifestItem[EPUBManifestItemTitleKey];
        NSString *mediaType = [manifestItem[EPUBManifestItemFileTypeIdentifierKey] mimeTypeForType];

        if (!mediaType) mediaType = @"application/octet-stream";

        NSXMLElement *itemElement = [NSXMLElement elementWithName:@"item" children:nil attributes:@[A(id, ident), A(href, url), A(media-type, mediaType)]];

        [manifestElement addChild:itemElement];

        if (spine) {
            NSXMLElement *itemRefElement = [NSXMLElement elementWithName:@"itemref" children:nil attributes:@[[NSXMLNode attributeWithName:@"idref" stringValue:ident]]];
            [spineElement addChild:itemRefElement];
        }

        if (title) {
            NSXMLElement *aElement  = [NSXMLElement elementWithName:@"a" children:@[T(title)] attributes:@[A(href, url)]];
            NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[aElement] attributes:nil];

            [tocElement addChild:liElement];

            if (!bodymatter) bodymatter = url;
        }
    }

    if (bodymatter) {
        NSXMLElement *aElement = [NSXMLElement elementWithName:@"a" children:@[T(@"Start of Content")] attributes:@[A(epub:type, @"bodymatter"), A(href, bodymatter)]];
        NSXMLElement *liElement = [NSXMLElement elementWithName:@"li" children:@[aElement] attributes:nil];

        [landmarksElement addChild:liElement];
    }

    NSURL *contentsURL = [NSURL fileURLWithPath:@"Contents" isDirectory:YES relativeToURL:baseURL];

    if (![packageDocument.XMLData writeToURL:[NSURL fileURLWithPath:packageURL.lastPathComponent relativeToURL:contentsURL] options:0 error:error]) return NO;
    if (![navDocument.XMLData writeToURL:[NSURL fileURLWithPath:navURL.lastPathComponent relativeToURL:contentsURL] options:0 error:error]) return NO;

    return YES;
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (input.count == 0) return @[];

    _collectionRegularExpression = [NSRegularExpression regularExpressionWithPattern:@":(\\d+(?:\\.\\d+)*)$" options:0 error:error];
    if (!_collectionRegularExpression) return nil;

    if (self.title.length == 0) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"The EPUB title is required." userInfo:nil];
    }
    if (self.publicationIdentifier.length == 0) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"The publication identifier is required." userInfo:nil];
    }
    if (self.creators.count == 0) {
        [self logMessageWithLevel:AMLogLevelWarn format:@"Some EPUB readers have problems if no creators are specified."];
    }

    for (id creator in self.creators) {
        if ([[creator valueForKey:EPUBCreatorDisplayNameKey] length] == 0) {
            @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"Every creator must have a display name." userInfo:nil];
        }
    }

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];

    [progress addObserver:self forKeyPath:@"fractionCompleted" options:NSKeyValueObservingOptionInitial context:NULL];

    NSFileManager *fileManager = [NSFileManager defaultManager];

    NSURL *outputURL = self.outputURL;
    NSURL *temporaryURL = [fileManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:outputURL create:YES error:error];
    if (!temporaryURL) return nil;

    NSURL *contentsURL = [NSURL fileURLWithPath:@"Contents" isDirectory:YES relativeToURL:temporaryURL];

    if (![fileManager createDirectoryAtURL:contentsURL withIntermediateDirectories:NO attributes:nil error:error]) return nil;

    [progress becomeCurrentWithPendingUnitCount:95];
    NSArray<NSDictionary<NSString *, id> *> *manifest = [self copyItemsAtPaths:input toDirectoryAtURL:contentsURL error:error];
    [progress resignCurrent];

    if (!manifest) return nil;

    [progress becomeCurrentWithPendingUnitCount:4];
    BOOL status = [self addPackageMetadataToDirectoryAtURL:temporaryURL manifest:manifest error:error];
    [progress resignCurrent];

    if (!status) return nil;

    NSURL * __autoreleasing actualURL;

    [progress becomeCurrentWithPendingUnitCount:1];
    status = [fileManager replaceItemAtURL:outputURL withItemAtURL:temporaryURL backupItemName:nil options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:&actualURL error:error];
    [progress resignCurrent];

    return status ? @[actualURL.path] : nil;
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context {
    double fractionCompleted = [object fractionCompleted];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressValue = fractionCompleted;
    });
}

@end

NS_ASSUME_NONNULL_END
