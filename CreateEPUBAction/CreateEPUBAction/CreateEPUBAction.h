//
//  CreateEPUBAction.h
//  CreateEPUBAction
//
//  Created by Rob Menke on 8/13/19.
//  Copyright © 2019 Rob Menke. All rights reserved.
//

@import Automator.AMBundleAction;

NS_ASSUME_NONNULL_BEGIN

@interface CreateEPUBAction : AMBundleAction

@property (nonatomic, readonly) NSDictionary *relators;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

- (IBAction)generateIdentifier:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
