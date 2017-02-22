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
    NSArray<NSXMLElement *> *elements = [self.metadataElement nodesForXPath:@"meta[@property = 'dcterms:modified']" error:NULL];
    NSAssert(elements.count == 1, @"package.opf resource is damaged.");

    return [DateFormatter dateFromString:elements[0].stringValue];
}

- (void)setModified:(NSDate *)date {
    NSArray<NSXMLElement *> *elements = [self.metadataElement nodesForXPath:@"meta[@property = 'dcterms:modified']" error:NULL];
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
    NSArray<NSXMLNode *> *attrs = [self.manifestElement objectsForXQuery:@"item[@href = $href]/@href" constants:@{@"href":item} error:&error];
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
            NSArray<NSXMLElement *> *elements = [self.document objectsForXQuery:@"//*[@id = $id]" constants:@{@"id":idTag} error:&error];
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
    [self willChangeValueForKey:@"manifest" withSetMutation:NSKeyValueMinusSetMutation usingObjects:items];

    NSError * __autoreleasing error;

    NSXMLElement * const manifestElement = self.manifestElement;
    NSXMLElement * const spineElement = self.spineElement;

    for (NSString *item in items) {
        NSArray<NSXMLElement *> *elements = [manifestElement objectsForXQuery:@"item[@href = $href]" constants:@{@"href":item} error:&error];
        NSAssert(elements, @"xpath - %@", error);

        if (!elements.count) continue;

        NSArray<NSXMLElement *> *spineElements = [spineElement objectsForXQuery:@"itemref[@idref = $idref]" constants:@{@"idref":[elements.firstObject attributeForName:@"id"].stringValue} error:&error];
        NSAssert(spineElements, @"xpath - %@", error);

        NSMutableIndexSet *indexSet = [NSMutableIndexSet indexSet];
        for (NSXMLElement *element in spineElements) {
            [indexSet addIndex:(element.index)];
        }

        if (indexSet.count) {
            [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:@"spine"];

            [indexSet enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
                [spineElement removeChildAtIndex:idx];
            }];

            [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:indexSet forKey:@"spine"];
        }

        [elements.firstObject detach];
    }

    [self didChangeValueForKey:@"manifest" withSetMutation:NSKeyValueMinusSetMutation usingObjects:items];
}

- (nullable NSString *)propertiesForManifest:(NSString *)item {
    NSError * __autoreleasing error;

    NSArray<NSXMLNode *> *attributes = [self.manifestElement objectsForXQuery:@"item[@href = $href]/@properties" constants:@{@"href":item} error:&error];
    NSAssert(attributes, @"xpath - %@", error);
    NSAssert(attributes.count <= 1, @"duplicate manifest items");

    return attributes.count ? attributes.firstObject.stringValue : nil;
}

- (void)setProperties:(nullable NSString *)properties forManifest:(NSString *)item {
    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [self.manifestElement objectsForXQuery:@"item[@href = $href]" constants:@{@"href":item} error:&error];
    NSAssert(elements, @"xpath - %@", error);
    NSAssert(elements.count <= 1, @"duplicate manifest items");

    if (elements.count == 0) return;

    NSXMLElement *element = elements.firstObject;

    if (properties) {
        [element addAttribute:[NSXMLNode attributeWithName:@"properties" stringValue:properties]];
    }
    else {
        [element removeAttributeForName:@"properties"];
    }
}

- (NSUInteger)countOfSpine {
    return self.spineElement.childCount;
}

- (NSString *)objectInSpineAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;
    NSArray<NSXMLNode *> *elements = [self.document.rootElement objectsForXQuery:@"let $id := spine/itemref[$ix]/@idref return manifest/item[@id = $id]/@href" constants:@{@"ix":@(index + 1)} error:&error];
    NSAssert(elements, @"xpath - %@", error);

    if (elements.count == 0) {
        @throw [NSException exceptionWithName:NSRangeException reason:[NSString stringWithFormat:@"index %lu beyond bounds of spine", (unsigned long)(index)] userInfo:nil];
    }

    return elements.firstObject.stringValue;
}

- (void)insertObject:(NSString *)item inSpineAtIndex:(NSUInteger)index {
    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"spine"];

    [self addManifest:[NSSet setWithObject:item]];

    NSError * __autoreleasing error;
    NSArray<NSXMLNode *> *attrs = [self.manifestElement objectsForXQuery:@"item[@href = $href]/@id" constants:@{@"href":item} error:&error];
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

- (nullable NSString *)propertiesForSpineAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;

    NSArray<NSXMLNode *> *attributes = [self.spineElement objectsForXQuery:@"itemref[$index]/@properties" constants:@{@"index":@(index)} error:&error];
    NSAssert(attributes, @"xpath - %@", error);
    NSAssert(attributes.count <= 1, @"duplicate manifest items");

    return attributes.count ? attributes.firstObject.stringValue : nil;
}

- (void)setProperties:(nullable NSString *)properties forSpineAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [self.spineElement objectsForXQuery:@"itemref[$index]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xpath - %@", error);

    if (elements.count == 0) return;

    NSXMLElement *element = elements.firstObject;

    if (properties) {
        [element addAttribute:[NSXMLNode attributeWithName:@"properties" stringValue:properties]];
    }
    else {
        [element removeAttributeForName:@"properties"];
    }
}

- (NSUInteger)countOfAuthors {
    NSError * __autoreleasing error;

    NSArray<NSNumber *> *values = [self.metadataElement objectsForXQuery:@"count(dc:creator)" error:&error];
    NSAssert(values, @"xpath - %@", error);

    return values.firstObject.unsignedIntegerValue;
}

- (NSString *)objectInAuthorsAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [self.metadataElement objectsForXQuery:@"let $id := substring(meta[@property='display-seq' and number(text()) = $index]/@refines, 2) return dc:creator[@id=$id]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xpath - %@", error);

    if (elements.count == 0) {
        @throw [NSException exceptionWithName:NSRangeException reason:[NSString stringWithFormat:@"index %lu beyond bounds of authors", (unsigned long)(index)] userInfo:nil];
    }

    return elements.firstObject.stringValue;
}

- (void)insertObject:(NSString *)author inAuthorsAtIndex:(NSUInteger)index {
    if (index > [self countOfAuthors]) {
        @throw [NSException exceptionWithName:NSRangeException reason:[NSString stringWithFormat:@"index %lu beyond bounds of authors", (unsigned long)(index)] userInfo:nil];
    }

    [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"authors"];

    NSXMLElement *metadataElement = self.metadataElement;

    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [metadataElement objectsForXQuery:@"meta[@property='display-seq' and number(text())>=$index]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xquery - %@", error);

    for (NSXMLElement *element in elements) {
        element.stringValue = [NSString stringWithFormat:@"%ld", (long)(element.stringValue.integerValue + 1)];
    }

    NSUInteger idNum = [author hash];

    NSString *idTag;

    while (true) {
        idTag = [NSString stringWithFormat:@"g%020lu", (unsigned long)(idNum)];

        NSArray<NSXMLElement *> *elements = [self.document objectsForXQuery:@"//*[@id=$id]" constants:@{@"id":idTag} error:&error];
        NSAssert(elements, @"xquery - %@", error);

        if (elements.count == 0) break;

        ++idNum;
    }

    NSXMLElement *element = [NSXMLElement elementWithName:@"dc:creator" URI:NS_DC];
    element.attributes = @[[NSXMLNode attributeWithName:@"id" stringValue:idTag]];
    element.stringValue = author;

    [metadataElement addChild:element];

    element = [NSXMLElement elementWithName:@"meta" URI:NS_OPF];
    element.attributes = @[[NSXMLNode attributeWithName:@"refines" stringValue:[@"#" stringByAppendingString:idTag]], [NSXMLNode attributeWithName:@"property" stringValue:@"display-seq"]];
    element.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)(index + 1)];

    [metadataElement addChild:element];

    [self didChange:NSKeyValueChangeInsertion valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"authors"];
}

- (void)removeObjectFromAuthorsAtIndex:(NSUInteger)index {
    [self willChange:NSKeyValueChangeRemoval valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"authors"];

    NSXMLElement *metadataElement = self.metadataElement;

    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [metadataElement objectsForXQuery:@"let $refines := meta[@property='display-seq' and number(text())=$index]/@refines return meta[@refines=$refines] | dc:creator[@id=substring($refines,2)]" constants:@{@"index":@(index+1)} error:NULL];
    NSAssert(elements, @"xquery - %@", error);

    if (elements.count == 0) {
        @throw [NSException exceptionWithName:NSRangeException reason:[NSString stringWithFormat:@"index %lu beyond bounds of authors", (unsigned long)(index)] userInfo:nil];
    }

    for (NSXMLElement *element in elements) {
        [element detach];
    }

    elements = [metadataElement objectsForXQuery:@"meta[@property='display-seq' and number(text())>$index]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xquery - %@", error);

    for (NSXMLElement *element in elements) {
        element.objectValue = [NSString stringWithFormat:@"%lu", (unsigned long)(element.stringValue.integerValue - 1)];
    }

    [self didChange:NSKeyValueChangeRemoval valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"authors"];
}

- (void)replaceObjectInAuthorsAtIndex:(NSUInteger)index withObject:(NSString *)author {
    [self willChange:NSKeyValueChangeReplacement valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"authors"];

    NSXMLElement *metadataElement = self.metadataElement;

    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [metadataElement objectsForXQuery:@"let $id := substring(meta[@property='display-seq' and number(text()) = $index]/@refines, 2) return dc:creator[@id=$id]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xquery - %@", error);

    if (elements.count == 0) {
        @throw [NSException exceptionWithName:NSRangeException reason:[NSString stringWithFormat:@"index %lu beyond bounds of authors", (unsigned long)(index)] userInfo:nil];
    }

    elements.firstObject.stringValue = author;

    elements = [metadataElement objectsForXQuery:@"let $refines := meta[@property='display-seq' and number(text()) = $index]/@refines return meta[@property!='display-seq' and @refines=$refines]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xquery - %@", error);

    for (NSXMLElement *element in elements) {
        [element detach];
    }

    [self didChange:NSKeyValueChangeReplacement valuesAtIndexes:[NSIndexSet indexSetWithIndex:index] forKey:@"authors"];
}

- (NSString *)roleForAuthorAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;

    NSArray<NSXMLElement *> *elements = [self.metadataElement objectsForXQuery:@"let $refines := meta[@property='display-seq' and number(text())=$index]/@refines return meta[@property='role' and @refines=$refines]" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(elements, @"xquery - %@", error);

    return elements.firstObject.stringValue;
}

- (void)setRole:(nullable NSString *)role forAuthorAtIndex:(NSUInteger)index {
    NSError * __autoreleasing error;

    NSXMLElement *metadataElement = self.metadataElement;

    NSArray<NSXMLNode *> *nodes = [metadataElement objectsForXQuery:@"meta[@property='display-seq' and number(text())=$index]/@refines" constants:@{@"index":@(index + 1)} error:&error];
    NSAssert(nodes, @"xquery - %@", error);

    NSString *refines = nodes.firstObject.stringValue;

    NSArray<NSXMLElement *> *elements = [metadataElement objectsForXQuery:@"meta[@property='role' and @refines=$refines]" constants:@{@"refines":refines} error:&error];
    NSAssert(elements, @"xquery - %@", error);

    if (elements.count) {
        NSXMLElement *element = elements.firstObject;

        if (role) {
            element.stringValue = role;
        }
        else {
            [element detach];
        }
    }
    else {
        NSXMLNode *refinesAttr = [NSXMLNode attributeWithName:@"refines" stringValue:refines];
        NSXMLNode *propertyAttr = [NSXMLNode attributeWithName:@"property" stringValue:@"role"];
        NSXMLNode *schemeAttr = [NSXMLNode attributeWithName:@"scheme" stringValue:@"marc:relators"];
        NSXMLElement *element = [NSXMLElement elementWithName:@"meta" children:@[[NSXMLNode textWithStringValue:role]] attributes:@[refinesAttr, propertyAttr, schemeAttr]];

        [metadataElement addChild:element];
    }
}

@end

NS_ASSUME_NONNULL_END
