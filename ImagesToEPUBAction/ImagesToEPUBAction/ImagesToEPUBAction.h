//
//  ImagesToEPUBAction.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import <Automator/AMBundleAction.h>

NS_ASSUME_NONNULL_BEGIN

@interface ImagesToEPUBAction : AMBundleAction

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
