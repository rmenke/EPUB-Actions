//
//  ImagesToEPUBAction.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import Automator.AMBundleAction;

NS_ASSUME_NONNULL_BEGIN

@interface ImagesToEPUBAction : AMBundleAction

@property (nonatomic, readonly) NSString *outputFolder;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *authors;
@property (nonatomic, readonly) NSString *publicationID;
@property (nonatomic, readonly) NSUInteger pageWidth, pageHeight, pageMargin;
@property (nonatomic, readonly) BOOL disableUpscaling;
@property (nonatomic, readonly) NSData *backgroundColor;
@property (nonatomic, readonly) BOOL doPanelAnalysis;

@property (nonatomic, readonly) NSString *pageColor;
@property (nonatomic, readonly) NSURL *outputURL;

- (void)loadParameters;

- (nullable NSURL *)createWorkingDirectory:(NSError **)error;
- (nullable NSURL *)finalizeWorkingDirectory:(NSURL *)url error:(NSError **)error;

- (nullable NSArray<NSDictionary<NSString *, id> *> *)copyItemsFromPaths:(NSArray<NSString *> *)paths toDirectory:(NSURL *)directory error:(NSError **)error;
- (nullable NSArray<NSURL *> *)createChapters:(NSArray<NSDictionary<NSString *, id> *> *)chapters error:(NSError **)error;
- (nullable NSURL *)createPage:(NSArray<NSDictionary<NSString *, id> *> *)page number:(NSUInteger)number inDirectory:(NSURL *)directory error:(NSError **)error;

- (BOOL)addMetadataToDirectory:(NSURL *)url manifestItems:(NSArray<NSString *> *)manifestItems spineItems:(NSArray<NSString *> *)spineItems error:(NSError **)error;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
