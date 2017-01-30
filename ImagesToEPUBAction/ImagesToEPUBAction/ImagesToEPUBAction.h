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

@property (nonatomic) NSString *outputFolder;
@property (nonatomic) NSString *title;
@property (nonatomic) NSString *authors;
@property (nonatomic) NSString *publicationID;
@property (nonatomic) NSUInteger pageWidth, pageHeight, pageMargin;
@property (nonatomic) BOOL disableUpscaling;
@property (nonatomic) NSData *backgroundColor;
@property (nonatomic) BOOL doPanelAnalysis;

@property (nonatomic, readonly) NSString *pageColor;
@property (nonatomic, readonly) NSURL *outputURL;

- (void)loadParameters;

- (nullable NSURL *)createWorkingDirectory:(NSError **)error;
- (nullable NSURL *)finalizeWorkingDirectory:(NSURL *)url error:(NSError **)error;

- (nullable NSArray<NSDictionary<NSString *, id> *> *)copyItemsFromPaths:(NSArray<NSString *> *)paths toDirectory:(NSURL *)directory error:(NSError **)error;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
