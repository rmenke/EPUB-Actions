//
//  OPFPackageDocument.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 2/16/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface OPFPackageDocument : NSObject

@property (nonatomic, readonly, nonnull) NSXMLDocument *document;
@property (nonatomic, readwrite, copy, nonnull) NSString *identifier;
@property (nonatomic, readwrite, copy, nonnull) NSString *title;
@property (nonatomic, readwrite, copy, nonnull) NSDate *modified;

- (instancetype)init NS_UNAVAILABLE;
- (nullable instancetype)initWithContentsOfURL:(NSURL *)url error:(NSError **)error NS_DESIGNATED_INITIALIZER;

+ (nullable instancetype)documentWithContentsOfURL:(NSURL *)url error:(NSError **)error;

- (NSUInteger)countOfManifest;
- (NSEnumerator<NSString *> *)enumeratorOfManifest;
- (nullable NSString *)memberOfManifest:(NSString *)item;
- (void)addManifest:(NSSet<NSString *> *)items;
- (void)removeManifest:(NSSet<NSString *> *)items;

- (nullable NSString *)propertiesForManifest:(NSString *)item;
- (void)setProperties:(nullable NSString *)properties forManifest:(NSString *)item;

- (NSUInteger)countOfSpine;
- (NSString *)objectInSpineAtIndex:(NSUInteger)index;
- (void)insertObject:(NSString *)item inSpineAtIndex:(NSUInteger)index;
- (void)removeObjectFromSpineAtIndex:(NSUInteger)index;

- (nullable NSString *)propertiesForSpineAtIndex:(NSUInteger)index;
- (void)setProperties:(nullable NSString *)properties forSpineAtIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
