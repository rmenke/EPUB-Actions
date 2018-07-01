//
//  PrepareImagesForEPUBAction.h
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/13/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

@import Automator.AMBundleAction;
@import AppKit.NSColor;

NS_ASSUME_NONNULL_BEGIN

@interface PrepareImagesForEPUBAction : AMBundleAction

@property (nonatomic, readonly) BOOL ignoreAlpha;
@property (nonatomic, readonly, copy, nonnull) NSColor *backgroundColor;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
