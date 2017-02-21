//
//  ConvertMarkupToEPUBNavigationAction.h
//  ConvertMarkupToEPUBNavigationAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import <Automator/AMBundleAction.h>

NS_ASSUME_NONNULL_BEGIN

@interface ConvertMarkupToEPUBNavigationAction : AMBundleAction

- (BOOL)processPage:(NSURL *)url updating:(NSMutableArray<NSXMLElement *> *)elements error:(NSError **)error;
- (BOOL)processChapter:(NSURL *)url updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError **)error;
- (BOOL)processFolder:(NSURL *)url error:(NSError **)error;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
