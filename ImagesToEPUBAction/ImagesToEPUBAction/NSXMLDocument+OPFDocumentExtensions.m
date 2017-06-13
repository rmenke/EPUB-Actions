//
//  NSXMLDocument+OPFDocumentExtensions.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 6/12/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import ObjectiveC.runtime;

#import "NSXMLDocument+OPFDocumentExtensions.h"

#define NS_OPF @"http://www.idpf.org/2007/opf"
#define NS_DC @"http://purl.org/dc/elements/1.1/"

#define Q(QUERY) @"declare default element namespace \"" NS_OPF "\";\ndeclare namespace dc = \"" NS_DC "\";\n\n" QUERY

static NSDateFormatter *DateFormatter = nil;

NS_ASSUME_NONNULL_BEGIN

static inline NSString *mediaTypeForExtension(NSString *extension) {
    CFStringRef typeIdentifier = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)(extension), NULL);

    if (typeIdentifier) {
        CFStringRef mediaType = UTTypeCopyPreferredTagWithClass(typeIdentifier, kUTTagClassMIMEType);
        CFRelease(typeIdentifier);
        return CFBridgingRelease(mediaType);
    }
    else {
        return @"application/octet-stream";
    }
}

@implementation NSXMLNode (XQueryExceptionExtensions)

- (NSArray *)objectsForXQuery:(NSString *)xquery {
#if DEBUG
    NSError * __autoreleasing error;
    NSArray *result = [self objectsForXQuery:xquery error:&error];
    if (!result) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"The XQuery could not be processed." userInfo:@{NSUnderlyingErrorKey:error}];
    return result;
#else
    return [self objectsForXQuery:xquery error:NULL];
#endif
}

- (NSArray *)objectsForXQuery:(NSString *)xquery constants:(NSDictionary<NSString *,id> *)constants {
#if DEBUG
    NSError * __autoreleasing error;
    NSArray *result = [self objectsForXQuery:xquery constants:constants error:&error];
    if (!result) @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"The XQuery could not be processed." userInfo:@{NSUnderlyingErrorKey:error}];
    return result;
#else
    return [self objectsForXQuery:xquery constants:constants error:NULL];
#endif
}

@end

@implementation NSXMLDocument (OPFDocumentExtensions)

+ (void)load {
    if (!DateFormatter) {
        DateFormatter = [[NSDateFormatter alloc] init];
        DateFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        DateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        DateFormatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    }
}

- (NSString *)identifier {
    return [[self objectsForXQuery:Q("/package/metadata/dc:identifier")].firstObject stringValue ];
}

- (void)setIdentifier:(NSString *)identifier {
    [[self objectsForXQuery:Q("/package/metadata/dc:identifier")].firstObject setStringValue:identifier];
}

- (NSString *)title {
    return [[self objectsForXQuery:Q("/package/metadata/dc:title")].firstObject stringValue];
}

- (void)setTitle:(NSString *)title {
    [[self objectsForXQuery:Q("/package/metadata/dc:title")].firstObject setStringValue:title];
}

- (nullable NSDate *)modified {
    NSXMLElement *element = [self objectsForXQuery:Q("/package/metadata/meta[@property='dcterms:modified']")].firstObject;
    return [DateFormatter dateFromString:element.stringValue];
}

- (void)setModified:(nullable NSDate *)modified {
    NSXMLElement *element = [self objectsForXQuery:Q("/package/metadata/meta[@property='dcterms:modified']")].firstObject;
    element.stringValue = modified ? [DateFormatter stringFromDate:modified] : @"";
}

- (NSMutableDictionary<NSString *, NSNumber *> *)idents {
    NSMutableDictionary<NSString *, NSNumber *> *idents = objc_getAssociatedObject(self, "com.the-wabe.ids");
    if (!idents) {
        idents = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, "com.the-wabe.ids", idents, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return idents;
}

- (NSMutableDictionary<NSString *, NSString *> *)manifest {
    NSMutableDictionary<NSString *, NSString *> *manifest = objc_getAssociatedObject(self, "com.the-wabe.manifest");
    if (!manifest) {
        manifest = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, "com.the-wabe.manifest", manifest, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return manifest;
}

- (void)addAuthor:(NSString *)author role:(nullable NSString *)role {
    NSXMLElement *metadataElement = [self.rootElement elementsForLocalName:@"metadata" URI:NS_OPF].firstObject;
    NSAssert(metadataElement, @"Document is missing elements.");

    NSArray<NSNumber *> *result = [metadataElement objectsForXQuery:Q("count(dc:creator)")];
    NSUInteger count = result.firstObject.unsignedIntegerValue;

    NSString *ident;

    do {
        ident = [NSString stringWithFormat:@"creator-%lu", (unsigned long)(++count)];
        NSNumber *result = [self objectsForXQuery:Q("count(//*[@id=$id])") constants:@{@"id":ident}].firstObject;
        if (result.integerValue > 0) ident = nil;
    } while (!ident);

    NSString *identRef = [@"#" stringByAppendingString:ident];

    NSXMLElement *element = [NSXMLElement elementWithName:@"dc:creator" URI:NS_DC];
    element.stringValue = author;

    [element addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:ident]];

    [metadataElement addChild:element];

    element = nil;

    for (NSUInteger displaySeq = 1; !element; ++displaySeq) {
        NSNumber *result = [metadataElement objectsForXQuery:Q("count(meta[@property='display-seq' and text()=$seq])") constants:@{@"seq":@(displaySeq)}].firstObject;
        if (result.unsignedIntegerValue == 0) {
            element = [NSXMLElement elementWithName:@"meta" URI:NS_OPF];
            element.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)(displaySeq)];

            [element addAttribute:[NSXMLNode attributeWithName:@"refines" stringValue:identRef]];
            [element addAttribute:[NSXMLNode attributeWithName:@"property" stringValue:@"display-seq"]];
        }
    }

    [metadataElement addChild:element];

    if (role) {
        element = [NSXMLElement elementWithName:@"meta" URI:NS_OPF];
        element.stringValue = role;

        [element addAttribute:[NSXMLNode attributeWithName:@"refines" stringValue:identRef]];
        [element addAttribute:[NSXMLNode attributeWithName:@"property" stringValue:@"role"]];
        [element addAttribute:[NSXMLNode attributeWithName:@"scheme" stringValue:@"marc:relators"]];

        [metadataElement addChild:element];
    }
}

- (NSString *)addManifestItem:(NSString *)item properties:(nullable NSString *)properties {
    NSXMLElement *manifestElement = [self.rootElement elementsForLocalName:@"manifest" URI:NS_OPF].firstObject;
    NSAssert(manifestElement, @"Document is missing elements.");

    NSXMLElement *element = [NSXMLElement elementWithName:@"item" URI:NS_OPF];

    NSMutableDictionary<NSString *, NSNumber *> *idents = self.idents;

    NSString *prefix = [item.lastPathComponent substringToIndex:2];
    NSUInteger count = idents[prefix].unsignedIntegerValue + 1;
    NSString *ident = [NSString stringWithFormat:@"%@-%04lu", prefix, (unsigned long)(count)];
    idents[prefix] = @(count);

    [element addAttribute:[NSXMLNode attributeWithName:@"id" stringValue:ident]];
    [element addAttribute:[NSXMLNode attributeWithName:@"href" stringValue:item]];
    [element addAttribute:[NSXMLNode attributeWithName:@"media-type" stringValue:mediaTypeForExtension(item.pathExtension)]];

    self.manifest[item] = ident;

    if (properties) {
        [element addAttribute:[NSXMLNode attributeWithName:@"properties" stringValue:properties]];
    }

    [manifestElement addChild:element];

    return ident;
}

- (void)addSpineItem:(NSString *)item properties:(nullable NSString *)properties {
    NSXMLElement *manifestElement = [self.rootElement elementsForLocalName:@"manifest" URI:NS_OPF].firstObject;
    NSXMLElement *spineElement = [self.rootElement elementsForLocalName:@"spine" URI:NS_OPF].firstObject;
    NSAssert(manifestElement && spineElement, @"Document is missing elements.");

    NSString *ident = self.manifest[item];
    if (!ident) ident = [self addManifestItem:item properties:nil];

    NSXMLElement *element = [NSXMLElement elementWithName:@"itemref" URI:NS_OPF];
    [element addAttribute:[NSXMLNode attributeWithName:@"idref" stringValue:ident]];

    if (properties) {
        [element addAttribute:[NSXMLNode attributeWithName:@"properties" stringValue:properties]];
    }

    [spineElement addChild:element];
}

@end

NS_ASSUME_NONNULL_END
