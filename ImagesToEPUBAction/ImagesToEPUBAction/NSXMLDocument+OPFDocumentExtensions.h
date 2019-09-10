//
//  NSXMLDocument+OPFDocumentExtensions.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 6/12/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSXMLDocument (OPFDocumentExtensions)

@property (nonatomic) NSString *identifier;
@property (nonatomic) NSString *title;
@property (nonatomic, nullable) NSDate *date;
@property (nonatomic, nullable) NSString *subject;
@property (nonatomic, nullable) NSDate *modified;
@property (nonatomic) BOOL landscapeOrientation;
@property (nonatomic) BOOL syntheticSpread;

- (void)addCreator:(NSString *)creator fileAs:(nullable NSString *)fileAs role:(nullable NSString *)role;
- (NSString *)addManifestItem:(NSString *)item properties:(nullable NSString *)properties;
- (void)addSpineItem:(NSString *)item properties:(nullable NSString *)properties;

@end

NS_ASSUME_NONNULL_END
