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
 * @param destination The destination buffer in Planar8 format.
 * @param regionOfInterest The bounds of the content of the image.
 */
void extractBorder(const vImage_Buffer *source, const vImage_Buffer *destination, CGRect regionOfInterest) _NOEXCEPT;

/*!
 * @abstract Use PPHT to find line segments in an image.
 * @discussion The image is assumed to be in Planar8 format.
 * @param buffer The buffer to analyze.
 * @param error If not <code>NULL</code> and an error occurs, will be filled with the error information.
 * @return A CFArrayRef of CFArrayRefs of four CFNumberRefs.
 */
CF_RETURNS_RETAINED
CFArrayRef _Nullable detectSegments(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT;

CF_RETURNS_RETAINED
CFArrayRef _Nullable detectPolylines(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT;

CF_RETURNS_RETAINED
CFArrayRef _Nullable detectRegions(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT;

#ifdef __cplusplus
}
#else
#undef _NOEXCEPT
#endif

CF_ASSUME_NONNULL_END

#endif /* AnalysisTools_h */
