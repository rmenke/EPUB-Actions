//
//  OPFPackageDocument.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/16/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "OPFPackageDocument.h"

NS_ASSUME_NONNULL_BEGIN

static NSString * const NS_OPF = @"http://www.idpf.org/2007/opf";
static NSString * const NS_DC = @"http://purl.org/dc/elements/1.1/";

static NSDateFormatter *DateFormatter;

static inline NSString *mimeTypeForExtension(NSString *extension) {
    CFStringRef typeIdentifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(extension), NULL);

    NSCAssert(typeIdentifier, @"Unknown/unsupported extension %@", extension);

    CFStringRef mimeType = UTTypeCopyPreferredTagWithClass(typeIdentifier, kUTTagClassMIMEType);
    CFRelease(typeIdentifier);

    NSCAssert(mimeType, @"Unknown/unsupported extension %@", extension);

    return CFBridgingRelease(mimeType);
}

@interface OPFPackageDocument ()

@property (nonatomic, readonly) NSXMLElement *metadataElement, *manifestElement, *spineElement;

@end

@implementation OPFPackageDocument

+ (void)initialize {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        DateFormatter = [[NSDateFormatter alloc] init];
        DateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        DateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    });
}

- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    self = [super init];

    if (self) {
        _document = [[NSXMLDocument alloc] initWithContentsOfURL:url options:0 error:error];
        if (!_document) return nil;
    }

    return self;
}

+ (nullable instancetype)documentWithContentsOfURL:(NSURL *)url error:(NSError **)error {
    return [[self alloc] initWithContentsOfURL:url error:error];
}

- (NSXMLElement *)metadataElement {
    NSArray<NSXMLElement *> *elements = [_document.rootElement elementsForLocalName:@"metadata" URI:NS_OPF];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return elements[0];
}

- (NSXMLElement *)manifestElement {
    NSArray<NSXMLElement *> *elements = [_document.rootElement elementsForLocalName:@"manifest" URI:NS_OPF];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return elements[0];
}

- (NSXMLElement *)spineElement {
    NSArray<NSXMLElement *> *elements = [_document.rootElement elementsForLocalName:@"spine" URI:NS_OPF];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return elements[0];
}

- (NSString *)identifier {
    NSArray<NSXMLElement *> *elements = [self.metadataElement elementsForLocalName:@"identifier" URI:NS_DC];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return elements[0].stringValue;
}

- (void)setIdentifier:(NSString *)identifier {
    NSArray<NSXMLElement *> *elements = [self.metadataElement elementsForLocalName:@"identifier" URI:NS_DC];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    elements[0].stringValue = identifier;
}

- (NSString *)title {
    NSArray<NSXMLElement *> *elements = [self.metadataElement elementsForLocalName:@"title" URI:NS_DC];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return elements[0].stringValue;
}

- (void)setTitle:(NSString *)title {
    NSArray<NSXMLElement *> *elements = [self.metadataElement elementsForLocalName:@"title" URI:NS_DC];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    elements[0].stringValue = title;
}

- (NSDate *)modified {
    NSArray<NSXMLElement *> *elements = [self.metadataElement nodesForXPath:@"meta[@property='dcterms:modified']" error:NULL];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return [DateFormatter dateFromString:elements[0].stringValue];
}

- (void)setModified:(NSDate *)date {
    NSArray<NSXMLElement *> *elements = [self.metadataElement nodesForXPath:@"meta[@property='dcterms:modified']" error:NULL];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    elements[0].stringValue = [DateFormatter stringFromDate:date];
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
    if ([key isEqualToString:@"manifest"] || [key isEqualToString:@"spine"]) {
        return NO;
    }

    return [super automaticallyNotifiesObserversForKey:key];
}

- (NSUInteger)countOfManifest {
    return self.manifestElement.childCount;
}

- (NSEnumerator<NSString *> *)enumeratorOfManifest {
    NSError * __autoreleasing error;
    NSArray<NSXMLNode *> *attrs = [self.manifestElement objectsForXQuery:@"item/@href" error:&error];
    NSAssert(attrs, @"xpath - %@", error);

    return [[attrs valueForKey:@"stringValue"] objectEnumerator];
}

- (nullable NSString *)memberOfManifest:(NSString *)item {
    NSError * __autoreleasing error;
    NSArray<NSXMLNode *> *attrs = [self.manifestElement objectsForXQuery:@"item[@href=$href]/@href" constants:@{@"href":item} error:&error];
    NSAssert(attrs, @"xpath - %@", error);

    return attrs.count ? attrs.firstObject.stringValue : nil;
}

- (void)addManifest:(NSSet *)items {
    [self willChangeValueForKey:@"manifest" withSetMutation:NSKeyValueUnionSetMutation usingObjects:items];

    NSXMLElement * const manifestElement = self.manifestElement;

    for (NSString *item in items) {
        if ([self memberOfManifest:item]) continue;

        NSUInteger idNum = [item hash];
        NSString *idTag;

        while (true) {
            idTag = [NSString stringWithFormat:@"g%020lu", (unsigned long)(idNum)];

            NSError * __autoreleasing error;
            NSArray<NSXMLElement *> *elements = [manifestElement objectsForXQuery:@"item[@id=$id]" constants:@{@"id":idTag} error:&error];
            NSAssert(elements, @"xpath - %@", error);

            if (elements.count == 0) break;

            ++idNum;
        }

        NSXMLNode *idAttr = [NSXMLNode attributeWithName:@"id" stringValue:idTag];
        NSXMLNode *hrefAttr = [NSXMLNode attributeWithName:@"href" stringValue:item];
        NSXMLNode *mediaTypeAttr = [NSXMLNode attributeWithName:@"media-type" stringValue:mimeTypeForExtension(item.pathExtension)];

        NSXMLElement *element = [NSXMLElement elementWithName:@"item" children:nil attributes:@[idAttr, hrefAttr, mediaTypeAttr]];
        [manifestElement addChild:element];
    }

    [self didChangeValueForKey:@"manifest" withSetMutation:NSKeyValueUnionSetMutation usingObjects:items];
}

- (void)removeManifest:(NSSet<NSString *> *)items {
    NSError * __autoreleasing error;

    [self willChangeValueForKey:@"manifest" withSetMutation:NSKeyValueMinusSetMutation usingObjects:items];

    for (NSString *item in items) {
        NSArray<NSXMLElement *> *elements = [self.manifestElement objectsForXQuery:@"item[@href=$href]" constants:@{@"href":item} error:&error];
        NSAssert(elements, @"xpath - %@", error);

        if (!elements.count) continue;

        NSArray<NSXMLElement *> *spineElements = [self.spineElement objectsForXQuery:@"itemref[@idref=$idref]" constants:@{@"idref":[elements.firstObject attributeForName:@"id"].stringValue} error:&error];
        NSAssert(spineElements, @"xpath - %@", error);

        NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
        for (NSXMLElement *element in spineElements) {
            [indexSet addIndex:(element.index)];
        }

        if (indexSet.count) {
            [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:@"spine"];

            [indexSet enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
                [self.spineElement removeChildAtIndex:idx];
            }];

            [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:@"spine"];
        }

        [elements.firstObject detach];
    }

    [self didChangeValueForKey:@"manifest" withSetMutation:NSKeyValueMinusSetMutation usingObjects:items];
}

- (NSUInteger)countOfSpine {
    return self.spineElement.childCount;
}

- (NSString *)objectInSpineAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;
    NSArray<NSXMLNode *> *elements = [self.document.rootElement objectsForXQuery:@"let $id := spine/itemref[$ix]/@idref return manifest/item[@id=$id]/@href" constants:@{@"ix":@(index + 1)} error:&error];
    NSAssert(elements, @"xpath - %@", error);
    NSAssert(elements.count == 1, @"spine itemref element refers to a non-existent manifest item");

    return elements.firstObject.stringValue;
}

- (void)insertObject:(NSString *)item inSpineAtIndex:(NSUInteger)index {
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"spine"];

    [self addManifest:[NSSet setWithObject:item]];

    NSError * __autoreleasing error;
    NSArray<NSXMLNode *> *attrs = [self.manifestElement objectsForXQuery:@"item[@href=$href]/@id" constants:@{@"href":item} error:&error];
    NSAssert(attrs, @"xpath - %@", error);
    NSAssert(attrs.count == 1, @"missing manifest item for %@", item);

    NSString *idTag = attrs.firstObject.stringValue;
    NSXMLElement *element = [NSXMLElement elementWithName:@"itemref" children:nil attributes:@[[NSXMLNode attributeWithName:@"idref" stringValue:idTag]]];

    [self.spineElement insertChild:element atIndex:index];

    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"spine"];
}

- (void)removeObjectFromSpineAtIndex:(NSUInteger)index {
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"spine"];

    [self.spineElement removeChildAtIndex:index];

    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"spine"];
}

@end

NS_ASSUME_NONNULL_END
