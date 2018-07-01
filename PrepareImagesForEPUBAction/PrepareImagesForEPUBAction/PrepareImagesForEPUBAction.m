//
//  PrepareImagesForEPUBAction.m
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/13/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#import "PrepareImagesForEPUBAction.h"

@import AppKit;
@import CoreImage;

#import "VImageBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@implementation PrepareImagesForEPUBAction

- (BOOL)ignoreAlpha {
    return [self.parameters[@"ignoreAlpha"] boolValue];
}

- (NSColor *)backgroundColor {
    return [NSUnarchiver unarchiveObjectWithData:self.parameters[@"backgroundColor"]];
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    NSSet<NSString *> *typeIdentifiers = [NSSet setWithArray:CFBridgingRelease(CGImageSourceCopyTypeIdentifiers())];

    for (NSString *path in input) {
        NSURL *url = [NSURL fileURLWithPath:path];
        NSString * __autoreleasing typeIdentifier;

        if (![url getResourceValue:&typeIdentifier forKey:NSURLTypeIdentifierKey error:error]) return nil;

        if (![typeIdentifiers containsObject:typeIdentifier]) {
            [self logMessageWithLevel:AMLogLevelWarn format:@"file %@ is not a usable image file", url.lastPathComponent];
            continue;
        }

        CIImage *image = [CIImage imageWithContentsOfURL:url];

        if (self.ignoreAlpha) {
            [self logMessageWithLevel:AMLogLevelDebug format:@"Flattening image prior to analysis"];
            CIColor *backgroundColor = [[CIColor alloc] initWithColor:self.backgroundColor];
            CIImage *background = [CIImage imageWithColor:backgroundColor];

            CGRect extent = image.extent;
            image = [image imageByCompositingOverImage:background];
            image = [image imageByCroppingToRect:extent];
        }

        CGImageRef cgImage = [[CIContext context] createCGImage:image fromRect:image.extent];

        VImageBuffer *buffer = [[VImageBuffer alloc] initWithCGImage:cgImage error:error];
        if (!buffer) return nil;

        CGImageRelease(cgImage);
    }

    return input;
}

@end

NS_ASSUME_NONNULL_END
