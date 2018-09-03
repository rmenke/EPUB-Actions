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
@import Darwin.POSIX.sys.xattr;

#import "VImageBuffer.h"

#define DEF_DOUBLE_PARAM(X) CGFloat X = [self.parameters[@#X] doubleValue]

NS_ASSUME_NONNULL_BEGIN

@implementation NSURL (Regions)

- (BOOL)setRegions:(id)regions error:(NSError **)error {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:regions format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data) return NO;

    if (setxattr(self.fileSystemRepresentation, EPUB_REGION_XATTR, data.bytes, data.length, 0, 0) < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSURLErrorKey:self}];
        return NO;
    }

    return YES;
}

@end

@implementation PrepareImagesForEPUBAction

- (BOOL)ignoreAlpha {
    return [self.parameters[@"ignoreAlpha"] boolValue];
}

- (NSColor *)backgroundColor {
    return [NSUnarchiver unarchiveObjectWithData:self.parameters[@"backgroundColor"]];
}

- (NSUInteger)openKernelSize {
    NSInteger kernel = [self.parameters[@"openKernel"] integerValue];

    if (kernel < 1) {
        self.parameters[@"openKernel"] = @1;
        [self logMessageWithLevel:AMLogLevelWarn format:@"kernel size of %lu too small; setting to 1", kernel];
        return 1;
    }
    else if (kernel > 9) {
        self.parameters[@"openKernel"] = @9;
        [self logMessageWithLevel:AMLogLevelWarn format:@"kernel size of %lu too large; setting to 9", kernel];
        return 9;
    }
    else if ((kernel & 1) != 1) {
        self.parameters[@"openKernel"] = @(kernel | 1);
        [self logMessageWithLevel:AMLogLevelWarn format:@"kernel size of %ld not odd; setting to %ld", kernel, kernel | 1];
        return kernel | 1;
    }

    return kernel;
}

- (CGRect)cropRectangle:(CGRect)rectangle {
    __unused CGSize size = rectangle.size;

    DEF_DOUBLE_PARAM(cropTop);
    DEF_DOUBLE_PARAM(cropBottom);
    DEF_DOUBLE_PARAM(cropLeft);
    DEF_DOUBLE_PARAM(cropRight);

    rectangle = CGRectStandardize(rectangle);

    if (cropTop > 0) {
        rectangle.origin.y += cropTop;
        rectangle.size.height -= cropTop;
    }
    if (cropBottom > 0) {
        rectangle.size.height -= cropBottom;
    }
    if (cropLeft > 0) {
        rectangle.origin.x += cropLeft;
        rectangle.size.width -= cropLeft;
    }
    if (cropRight > 0) {
        rectangle.size.width -= cropRight;
    }

    assert(cropLeft == CGRectGetMinX(rectangle));
    assert(cropTop == CGRectGetMinY(rectangle));
    assert(size.width - cropRight == CGRectGetMaxX(rectangle));
    assert(size.height - cropBottom == CGRectGetMaxY(rectangle));

    return rectangle;
}

- (nullable NSArray<NSString *> *)runWithInput:(nullable NSArray<NSString *> *)input error:(NSError **)error {
    NSSet<NSString *> *typeIdentifiers = [NSSet setWithArray:CFBridgingRelease(CGImageSourceCopyTypeIdentifiers())];

    NSProgress *progress = [NSProgress discreteProgressWithTotalUnitCount:input.count];
    [self bind:@"fractionCompleted" toObject:progress withKeyPath:@"fractionCompleted" options:nil];

    for (NSString *path in input) {
        if (self.stopped) return nil;

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
        CGImageRelease(cgImage);

        CGRect rect = [self cropRectangle:CGRectMake(0, 0, buffer.width, buffer.height)];

        buffer = [buffer extractBorderMaskInRect:rect error:error];

        NSUInteger openKernel = self.openKernelSize;

        if (openKernel > 1) {
            buffer = [buffer openWithWidth:openKernel height:openKernel error:error];
        }
        if (!buffer) return nil;

        if (![buffer detectEdgesAndReturnError:error]) return nil;

        NSArray<NSArray<NSNumber *> *> *regions = [buffer detectRegionsWithOptions:self.parameters error:error];
        if (!regions) return nil;

        if (![url setRegions:regions error:error]) return nil;

        ++progress.completedUnitCount;
    }

    return input;
}

- (CGFloat)fractionCompleted {
    return self.progressValue;
}

- (void)setFractionCompleted:(CGFloat)fractionCompleted {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progressValue = fractionCompleted;
    });
}

@end

NS_ASSUME_NONNULL_END
