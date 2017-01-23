//
//  ImagesToEPUBAction.m
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#import "ImagesToEPUBAction.h"

@import AppKit.NSColor;
@import AppKit.NSKeyValueBinding;

NS_ASSUME_NONNULL_BEGIN

static NSString * const AMProgressValueBinding = @"progressValue";

@interface ImagesToEPUBAction ()

@property (nonatomic) NSURL *workingURL;

@end

@implementation ImagesToEPUBAction

- (void)dealloc {
    [self unbind:AMProgressValueBinding];
}

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

    NSColor *backgroundColor = _backgroundColor ? [NSUnarchiver unarchiveObjectWithData:_backgroundColor] : nil;

    if (backgroundColor) {
        CGFloat rgba[4];

        [[backgroundColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getComponents:rgba];

        const uint8_t r = rgba[0] * 255.0;
        const uint8_t g = rgba[1] * 255.0;
        const uint8_t b = rgba[2] * 255.0;

        _pageColor = [NSString stringWithFormat:@"#%02"PRIx8"%02"PRIx8"%02"PRIx8, r, g, b];
    }
    else {
        _pageColor = @"#ffffff";
    }

    NSURL *folderURL   = [NSURL fileURLWithPath:_outputFolder.stringByExpandingTildeInPath isDirectory:YES];
    NSString *filename = [[_title stringByReplacingOccurrencesOfString:@"/" withString:@"-"] stringByAppendingPathExtension:@"epub"];

    _outputURL         = [NSURL fileURLWithPath:filename isDirectory:YES relativeToURL:folderURL];
    _workingURL        = nil;
}

- (BOOL)createWorkingDirectory:(NSError **)error {
    _workingURL = [[NSFileManager defaultManager] URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:_outputURL create:YES error:error];
    return _workingURL != nil;
}

- (nullable NSURL *)copyTemporaryToOutput:(NSError **)error {
    NSURL * __autoreleasing url;
    return [[NSFileManager defaultManager] replaceItemAtURL:_outputURL withItemAtURL:_workingURL backupItemName:NULL options:0 resultingItemURL:&url error:error] ? url : nil;
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    if (input.count == 0) return @[];

    [self loadParameters];

    if (![self createWorkingDirectory:error]) return nil;

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:100];

    [self bind:AMProgressValueBinding toObject:progress withKeyPath:@"fractionCompleted" options:nil];

    NSURL *outputURL = [self copyTemporaryToOutput:error];
    return outputURL ? @[outputURL.path] : nil;
}

@end

NS_ASSUME_NONNULL_END
