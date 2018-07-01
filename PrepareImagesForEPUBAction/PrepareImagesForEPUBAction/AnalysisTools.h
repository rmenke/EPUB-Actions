//
//  AnalysisTools.h
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/17/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#ifndef AnalysisTools_h
#define AnalysisTools_h

#include <CoreFoundation/CoreFoundation.h>
#include <Accelerate/Accelerate.h>

CF_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
using _Bool = bool;
#else
#define _NOEXCEPT
#endif

/*!
 * @abstract Perform a flood-fill on the border of the image.
 * @discussion Performs a flood-fill based on the given region of interest.  Everything outside the region is automatically discarded.  The source buffer and destination buffer must have the same dimensions.
 * @param source The source buffer in XYZAf format.
 * @param destination The destination buffer in A8 format.
 * @param regionOfInterest The bounds of the content of the image.
 */
void extractBorder(const vImage_Buffer * _Nonnull source, const vImage_Buffer * _Nonnull destination, CGRect regionOfInterest) _NOEXCEPT;

_Bool detectEdges(const vImage_Buffer * _Nonnull buffer, CFErrorRef _Nullable * _Nullable error) _NOEXCEPT;

CF_RETURNS_RETAINED
CFArrayRef _Nullable detectSegments(const vImage_Buffer * _Nonnull buffer, CFErrorRef _Nullable * _Nullable errorPtr) _NOEXCEPT;

#ifdef __cplusplus
}
#else
#undef _NOEXCEPT
#endif

CF_ASSUME_NONNULL_END

#endif /* AnalysisTools_h */
