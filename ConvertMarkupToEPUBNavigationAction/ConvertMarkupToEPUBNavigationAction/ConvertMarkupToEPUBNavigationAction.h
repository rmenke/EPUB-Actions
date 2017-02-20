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

- (nullable NSArray<NSXMLElement *> *)processXHTML:(NSURL *)url error:(NSError **)error;
- (BOOL)processEPUBFolder:(NSURL *)url error:(NSError **)error;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
