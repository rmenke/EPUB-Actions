//
//  ImagesToEPUBAction.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "ImagesToEPUBAction.h"

@import AppKit.NSColor;

NS_ASSUME_NONNULL_BEGIN

@interface ImagesToEPUBAction ()

@property (nonatomic) NSURL *workingURL;

@end

@implementation ImagesToEPUBAction

- (void)loadParameters {
    NSDictionary<NSString *, id> *parameters = self.parameters;

    for (NSString *property in parameters) {
        if ([self respondsToSelector:NSSelectorFromString(property)]) {
            [self setValue:parameters[property] forKeyPath:property];
        }
    }

    if (_title.length == 0) _title = @"Untitled";

    NSParameterAssert(_pageWidth  > 2 * _pageMargin);
    NSParameterAssert(_pageHeight > 2 * _pageMargin);

    NSColor *backgroundColor = [NSUnarchiver unarchiveObjectWithData:_backgroundColor];
    if (backgroundColor) {
        const uint8_t r = backgroundColor.redComponent * 255.0;
        const uint8_t g = backgroundColor.greenComponent * 255.0;
        const uint8_t b = backgroundColor.blueComponent * 255.0;

        _pageColor = [NSString stringWithFormat:@"#%02"PRIx8"%02"PRIx8"%02"PRIx8, r, g, b];
    }
    else {
        _pageColor = @"#ffffff";
    }

    _outputURL = [NSURL fileURLWithPath:_outputFolder.stringByExpandingTildeInPath isDirectory:YES];
    _outputURL = [NSURL fileURLWithPath:[_title stringByAppendingPathExtension:@"epub"] isDirectory:YES relativeToURL:_outputURL];

    _workingURL = nil;
}

- (BOOL)createWorkingDirectory:(NSError **)error {
    _workingURL = [[NSFileManager defaultManager] URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:_outputURL create:YES error:error];
    return _workingURL != nil;
}

- (nullable NSURL *)copyTemporaryToOutput:(NSError **)error {
    NSURL * __autoreleasing url;
    if (![[NSFileManager defaultManager] replaceItemAtURL:_outputURL withItemAtURL:_workingURL backupItemName:NULL options:0 resultingItemURL:&url error:error]) return nil;
    return url;
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (input.count == 0) return @[];

    [self loadParameters];

    return nil;
}

@end

NS_ASSUME_NONNULL_END
