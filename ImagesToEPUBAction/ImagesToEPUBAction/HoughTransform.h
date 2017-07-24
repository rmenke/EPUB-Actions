//
//  HoughTransform.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 6/14/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#ifndef HoughTransform_h
#define HoughTransform_h

#include <CoreFoundation/CoreFoundation.h>
#include <Accelerate/Accelerate.h>
#include <simd/simd.h>

#if defined(__cplusplus)
#define NOEXCEPT_SPECIFIER noexcept
extern "C" {
#else
#define NOEXCEPT_SPECIFIER
#endif

CFArrayRef _Nullable CreateSegmentsFromImage(const vImage_Buffer * _Nonnull buffer, uint8_t grayThreshold, double significance, unsigned channelWidth, CFErrorRef _Nullable * _Nullable errorPtr) NOEXCEPT_SPECIFIER;

#if defined(__cplusplus)
} // extern "C"
#endif

#undef NOEXCEPT_SPECIFIER

#endif /* HoughTransform_h */
