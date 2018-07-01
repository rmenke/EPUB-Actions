//
//  AnalysisTools.cpp
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/17/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#include "AnalysisTools.h"

#include <simd/simd.h>

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <map>
#include <random>
#include <set>
#include <valarray>
#include <vector>

#if CGFLOAT_IS_DOUBLE
#define vector_cgfloat(X) vector_double(X)
#define cgfloat3 double3
#define cgfloat4 double4
#else
#define vector_cgfloat(X) vector_float(X)
#define cgfloat3 float3
#define cgfloat4 float4
#endif

static constexpr simd::float3 D50 { 0.964355f, 1.0f, 0.825195f };

static constexpr double threshold = -16; // ≈ ln(1E-6)
static constexpr unsigned max_gap = 3;

__unused static inline std::ostream &operator <<(std::ostream &o, const simd::float3 &v) {
    return o << '[' << v.x << ',' << v.y << ',' << v.z << ']';
}

__unused static inline std::ostream &operator <<(std::ostream &o, const simd::float4 &v) {
    return o << '[' << v.x << ',' << v.y << ',' << v.z << ',' << v.w << ']';
}

template <typename _Element>
static inline _Element *row_as_array_of(const vImage_Buffer *buffer, vImagePixelCount row) {
    return static_cast<_Element *>(buffer->data) + buffer->rowBytes / sizeof(_Element) * row;
}

namespace cf {
    struct __cf_deleter {
        template <typename Ref> void operator ()(Ref ref) const {
            CFRelease(ref);
        }
    };

    template <typename Ref> using managed = std::unique_ptr<typename std::remove_pointer<Ref>::type, __cf_deleter>;

    template <typename Ref> managed<Ref> make_managed(Ref ref) {
        return managed<Ref> { ref };
    }

    managed<CFStringRef> string(const char *s) {
        return make_managed(CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8));
    }

    managed<CFStringRef> string(const std::string &s) {
        return make_managed(CFStringCreateWithCString(kCFAllocatorDefault, s.c_str(), kCFStringEncodingUTF8));
    }

    managed<CFNumberRef> number(const unsigned short &n) {
        return make_managed(CFNumberCreate(kCFAllocatorDefault, kCFNumberShortType, &n));
    }

    template <typename... Args>
    managed<CFArrayRef> array(Args &&... args) {
        const void *values[] = { args.get()... };
        return make_managed(CFArrayCreate(kCFAllocatorDefault, values, sizeof...(Args), &kCFTypeArrayCallBacks));
    }
}

namespace hough {
    constexpr vImagePixelCount max_theta = 1024;

    using trig_data = std::array<simd::double2, max_theta>;
    
    enum class state : unsigned char {
        unset, pending, voted
    };

    template <typename register_t = uint32_t>
    class analyzer {
        using img_size_t = uint16_t;
        using pixel_t    = std::pair<img_size_t, img_size_t>;
        using queue_t    = std::vector<pixel_t>;

        const trig_data &trig;

        const img_size_t width, height;

        const double rho_scale;
        const uint32_t max_rho;

        std::valarray<hough::state> image;
        std::valarray<register_t> accumulator;

        queue_t queue;
        int voted;

        std::default_random_engine rng { std::random_device{}() };

        static inline auto param(const vImage_Buffer *buffer) {
            assert(buffer->width  < std::numeric_limits<img_size_t>::max());
            assert(buffer->height < std::numeric_limits<img_size_t>::max());

            const double   diagonal  = std::ceil(std::hypot(buffer->width, buffer->height));
            const double   rho_scale = std::exp2(std::round(std::log2(max_theta) - std::log2(diagonal)));
            const uint32_t max_rho   = std::ceil(diagonal * rho_scale);

            return std::make_tuple(buffer->width, buffer->height, rho_scale, max_rho);
        }

        template <typename Param> analyzer(const Param &param, const trig_data &trig) : trig(trig), width(std::get<0>(param)), height(std::get<1>(param)), rho_scale(std::get<2>(param)), max_rho(std::get<3>(param)), image(width * height), accumulator(max_theta * max_rho) { }

    public:
        analyzer(const vImage_Buffer *buffer, const trig_data &trig) : analyzer(param(buffer), trig) {
            auto iter = std::begin(image);

            for (uint32_t y = 0; y < buffer->height; ++y) {
                const uint8_t *row = row_as_array_of<uint8_t>(buffer, y);

                for (uint32_t x = 0; x < buffer->width; ++x) {
                    if (row[x]) {
                        *iter = state::pending;
                        queue.emplace_back(x, y);
                    }
                    else {
                        *iter = state::unset;
                    }
                    ++iter;
                }
            }
        };

        bool vote(const pixel_t &pixel, img_size_t *theta, img_size_t *rho) {
            const simd::double2 p { static_cast<double>(pixel.first), static_cast<double>(pixel.second) };

            register_t n = 0;
            std::vector<pixel_t> peaks;

            for (img_size_t theta = 0; theta < max_theta; ++theta) {
                img_size_t rho = std::lround(simd::dot(p, trig[theta]) * rho_scale);
                if (rho < 0 || rho >= max_rho) continue;

                auto &count = accumulator[theta + rho * max_theta];

                ++count;

                if (n < count) {
                    n = count;
                    peaks.clear();
                }
                if (n == count) {
                    peaks.emplace_back(theta, rho);
                }
            }

            // There are maxTheta * maxRho cells in the register.
            // Each vote will increment maxTheta of these cells, one
            // per column.
            //
            // Assuming the null hypothesis (the image is random noise),
            // E[n] = votes/maxRho for all cells in the register.

            const double lambda = static_cast<double>(++voted) / max_rho;

            // For the null hypothesis, the cells are filled (roughly) according
            // to a Poisson model:
            //
            //    p(n) = λⁿ/n!·exp(-λ)
            //         = λⁿ/Γ(n+1)·exp(-λ)
            // ln p(n) = n ln(λ) - lnΓ(n+1) - λ

            const double lnp = n * log(lambda) - lgamma(n + 1) - lambda;

            // lnp is the (log) probability that a bin that was filled randomly
            // would contain a count of n. If the probability is below the
            // significance threshold, we reject the null hypothesis for this
            // point.

            if (lnp <= threshold) {
                if (peaks.size() > 1) {
                    // If there is multiple options for a scan channel, reduce the options to the ones that are most orthogonal
                    // (i.e., the ones parallel to the axes, then the ones at π/4, then the ones at π/8, &c).
                    //
                    // This isn't standard PPHT, but for the purposes of this project it will do.

                    unsigned int factor = 512;

                    const auto theta_is_multiple_of_factor = [&factor] (const pixel_t &a) {
                        return (a.first % factor) == 0;
                    };

                    do {
                        factor >>= 1;

                        auto end = std::partition(peaks.begin(), peaks.end(), theta_is_multiple_of_factor);

                        if (end != peaks.begin()) {
                            peaks.erase(end, peaks.end());
                        }
                    } while (factor > 1);

                    assert(peaks.size() > 0);
                }

                // In the unlikely event we still have multiple candidates, just pick one at random.
                // std::uniform_int_distribution handles the case where peaks.size() == 1 correctly and efficiently.

                auto index = std::uniform_int_distribution<size_t>(0, peaks.size() - 1)(rng);
                
                std::tie(*theta, *rho) = peaks[index];

                return true;
            }

            return false;
        }

        void unvote(const pixel_t &pixel) {
            const simd::double2 p { static_cast<double>(pixel.first), static_cast<double>(pixel.second) };

            for (img_size_t theta = 0; theta < max_theta; ++theta) {
                img_size_t rho = std::lround(simd::dot(p, trig[theta]) * rho_scale);
                if (rho < 0 || rho >= max_rho) continue;

                auto &count = accumulator[theta + rho * max_theta];

                if (count > 0) --count;
            }

            --voted;
        }

        std::vector<std::pair<pixel_t, pixel_t>> analyze() {
            std::vector<std::pair<pixel_t, pixel_t>> result;

            const auto begin = queue.begin();
            auto end = queue.end();

            voted = 0;

            while (begin != end) {
                auto ix = std::uniform_int_distribution<queue_t::size_type>(0, std::distance(begin, end) - 1)(rng);

                std::swap(queue[ix], *(--end));
                const pixel_t &pixel = *end;

                state &cell = image[pixel.first + pixel.second * width];
                if (cell != state::pending) continue;

                cell = state::voted;

                img_size_t theta, rho;

                if (!vote(pixel, &theta, &rho)) continue;

                // (theta, rho) is the point on the line candidate in polar coordinates perpendicular to a line from the origin.
                // (p₀.x, p₀.y) is the equivalent point in cartesian coordinates.
                // Rotating the angle theta by 90° will give (∆x, ∆y) in cartesian coordinates.
                // These four values describe the parametric form of the line: p₀ + ∆t

                auto p0 = rho / rho_scale * trig[theta];

                auto delta = trig[(theta + max_theta / 4) % max_theta];

                // A line is infinite.  Find the range of the parameter of the line which defines the points
                // that lie within the image boundary.

                const auto bounds = simd::double2 { std::nextafter(width, 0), std::nextafter(height, 0) };

                auto z0 = - p0 / delta;
                auto z1 = (bounds - p0) / delta;

                double z_min = +INFINITY, z_max = -INFINITY;

                if (isfinite(z0.x)) {
                    auto y = z0.x * delta.y + p0.y;
                    if (y >= 0 && y <= bounds.y) {
                        if (z_min > z0.x) z_min = z0.x;
                        if (z_max < z0.x) z_max = z0.x;
                    }
                }
                if (isfinite(z0.y)) {
                    auto x = z0.y * delta.x + p0.x;
                    if (x >= 0 && x <= bounds.x) {
                        if (z_min > z0.y) z_min = z0.y;
                        if (z_max < z0.y) z_max = z0.y;
                    }
                }
                if (isfinite(z1.x)) {
                    auto y = z1.x * delta.y + p0.y;
                    if (y >= 0 && y <= bounds.y) {
                        if (z_min > z1.x) z_min = z1.x;
                        if (z_max < z1.x) z_max = z1.x;
                    }
                }
                if (isfinite(z1.y)) {
                    auto x = z1.y * delta.x + p0.x;
                    if (x >= 0 && x <= bounds.x) {
                        if (z_min > z1.y) z_min = z1.y;
                        if (z_max < z1.y) z_max = z1.y;
                    }
                }

                // This shouldn't happen, but if z_min or z_max are infinite then the line lies entirely outside of the region of interest.
                if (!isfinite(z_min) || !isfinite(z_max)) continue;

                using segment_t = std::tuple<double, double, std::set<pixel_t>>;

                std::vector<segment_t> segments;

                segment_t segment { 0, 0, { } };

                int gap = 1;

                for (auto z = z_min; z <= z_max; z += 0.5) {
                    auto p  = p0 + delta * z;

                    auto lo = vector_short(simd::floor(p) - 1.0);
                    auto hi = vector_short(simd::ceil(p)  + 1.0);

                    bool hit = false;

                    for (auto y = lo.y; y <= hi.y; ++y) {
                        if (y < 0 || y >= height) continue;
                        for (auto x = lo.x; x <= hi.x; ++x) {
                            if (x < 0 || x >= width) continue;
                            if (image[x + y * width] != state::unset) {
                                std::get<2>(segment).emplace(x, y);
                                hit = true;
                            }
                        }
                    }

                    if (hit) {
                        if (gap) std::get<0>(segment) = z + 0.5;
                        std::get<1>(segment) = z - 0.5;
                        gap = 0;
                    }
                    else {
                        ++gap;

                        if (gap >= max_gap * 2 && !std::get<2>(segment).empty()) {
                            segments.emplace_back(std::move(segment));
                            std::get<2>(segment).clear();
                        }
                    }
                }

                if (!std::get<2>(segment).empty()) {
                    segments.emplace_back(std::move(segment));
                }

                if (segments.empty()) {
                    return { };
                }

                auto max_iter = std::max_element(segments.begin(), segments.end(), [] (const segment_t &s1, const segment_t &s2) {
                    auto l1 = std::get<1>(s1) - std::get<0>(s1);
                    auto l2 = std::get<1>(s2) - std::get<0>(s2);
                    return l1 < l2;
                });

                segment = std::move(*max_iter);

                for (const auto &pixel : std::get<2>(segment)) {
                    auto &state = image[pixel.first + pixel.second * width];

                    if (state == state::voted) {
                        unvote(pixel);
                    }

                    state = state::unset;
                }

                const auto p1 = p0 + delta * std::get<0>(segment);
                const auto p2 = p0 + delta * std::get<1>(segment);

                const pixel_t s1 { std::lround(p1.x), std::lround(p1.y) };
                const pixel_t s2 { std::lround(p2.x), std::lround(p2.y) };

                result.emplace_back(s1, s2);
            }

            return result;
        }
    };
}

class vimage_exception : public std::exception {
    vImage_Error errc;

    static inline const char *errc_to_string(vImage_Error errc) {
        switch (errc) {
            case kvImageNoError:
                return "No error.";
            case kvImageRoiLargerThanInputBuffer:
                return "The ROI was larger than input buffer.";
            case kvImageInvalidKernelSize:
                return "The kernel size was invalid.";
            case kvImageInvalidEdgeStyle:
                return "The edge style was invalid.";
            case kvImageInvalidOffset_X:
                return "The x offset was invalid.";
            case kvImageInvalidOffset_Y:
                return "The y offset was invalid.";
            case kvImageMemoryAllocationError:
                return "An error occurred while allocating memory.";
            case kvImageNullPointerArgument:
                return "The argument was a null pointer.";
            case kvImageInvalidParameter:
                return "A parameter was invalid.";
            case kvImageBufferSizeMismatch:
                return "The buffer sizes did not match.";
            case kvImageUnknownFlagsBit:
                return "An unknown flag was set.";
            case kvImageInternalError:
                return "An unknown internal error occurred.";
            case kvImageInvalidRowBytes:
                return "The number of bytes per row was invalid.";
            case kvImageInvalidImageFormat:
                return "The image format was invalid.";
            case kvImageColorSyncIsAbsent:
                return "ColorSync is absent.";
            case kvImageOutOfPlaceOperationRequired:
                return "An out-of-place operation was required but the request was for an in-place operation.";
            case kvImageInvalidImageObject:
                return "The image object was invalid.";
            case kvImageInvalidCVImageFormat:
                return "The CVimage format was invalid.";
            case kvImageUnsupportedConversion:
                return "The requested conversion is not supported.";
            case kvImageCoreVideoIsAbsent:
                return "CoreVideo is absent.";
        }

        return "An unknown error occurred.";
    }

public:
    vimage_exception(vImage_Error errc) : errc(errc) { }

    virtual ~vimage_exception() { }

    vImage_Error error_code() const {
        return errc;
    }

    const char* what() const _NOEXCEPT override {
        return errc_to_string(errc);
    }
};

struct managed_buffer : vImage_Buffer {
    managed_buffer(vImagePixelCount height, vImagePixelCount width, uint32_t bitsPerPixel) {
        const vImage_Error errc = vImageBuffer_Init(this, height, width, bitsPerPixel, kvImageNoFlags);
        if (errc != kvImageNoFlags) throw vimage_exception(errc);
    }

    managed_buffer(const managed_buffer &) = delete;
    managed_buffer(managed_buffer &&r) : vImage_Buffer(r) {
        r.data = nullptr;
    }

    ~managed_buffer() {
        free(data);
    }

    managed_buffer &operator =(const managed_buffer &) = delete;
    managed_buffer &operator =(managed_buffer &&r) {
        *static_cast<vImage_Buffer *>(this) = r;
        r.data = nullptr;
        return *this;
    }
};

template <typename Exception>
CFErrorRef CreateErrorFromException(const std::string &type, CFIndex code, const Exception &ex) {
    auto domain = cf::string(type);
    auto what   = cf::string(ex.what());

    const void *keys[] = { kCFErrorLocalizedFailureReasonKey };
    const void *vals[] = { what.get() };

    return CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, (CFErrorDomain)(domain.get()), code, keys, vals, 1);
}

template <>
struct std::less<simd::float4> {
    bool operator ()(simd::float4 a, simd::float4 b) const {
        if (a.x < b.x) return true;
        if (a.x > b.x) return false;
        if (a.y < b.y) return true;
        if (a.y > b.y) return false;
        if (a.z < b.z) return true;
        if (a.z > b.z) return false;
        
        return a.w < b.w;
    }
};

static inline simd::float3 xyzToLab(simd::float3 xyz) {
    constexpr float epsilon = 0.008856f;
    constexpr float kappa = 903.3f;

    constexpr matrix_float4x3 M {
        vector_float3 { 116.0f,  500.0f,    0.0f },
        vector_float3 {   0.0f, -500.0f,  200.0f },
        vector_float3 {   0.0f,    0.0f, -200.0f },
        vector_float3 { -16.0f,    0.0f,    0.0f }
    };

    const simd::float3 r = simd::clamp<simd::float3>(xyz / D50, 0.0f, 1.0f);

    const simd::int3 selector = r > epsilon;

    const simd::float4 f = {
        selector.x ? cbrtf(r.x) : (kappa * r.x + 16.0f) / 116.0f,
        selector.y ? cbrtf(r.y) : (kappa * r.y + 16.0f) / 116.0f,
        selector.z ? cbrtf(r.z) : (kappa * r.z + 16.0f) / 116.0f,
        1.0f
    };

    return matrix_multiply(M, f);
}

template <typename _Predicate>
static inline vImagePixelCount extractBorderUsingPredicate(const vImage_Buffer *source, const vImage_Buffer *destination, const vImagePixelCount x, const vImagePixelCount y, _Predicate fcn) {
    const auto srcRow = row_as_array_of<const simd::float4>(source, y);
    const auto dstRow = row_as_array_of<uint8_t>(destination, y);

#define is_open(x) (!dstRow[x] && fcn(srcRow[x]))

    uint16_t lo, hi;

    const auto max_w = source->width - 1;
    const auto max_h = source->height - 1;

    if (!is_open(x)) {
        for (hi = x; hi < max_w && !is_open(hi + 1); ++hi);
        return hi;
    }

    for (lo = x; lo > 0 && is_open(lo - 1); --lo);
    for (hi = x; hi < max_w && is_open(hi + 1); ++hi);

    for (auto x = lo; x <= hi; ++x) dstRow[x] = 255;

    if (y > 0) {
        for (auto x = lo; x <= hi; ++x) {
            x = extractBorderUsingPredicate(source, destination, x, y - 1, fcn);
        }
    }
    if (y < max_h) {
        for (auto x = lo; x <= hi; ++x) {
            x = extractBorderUsingPredicate(source, destination, x, y + 1, fcn);
        }
    }

#undef is_open

    return hi;
}

static void extractBorderUsingAlpha(const vImage_Buffer *source, const vImage_Buffer *destination, const vImagePixelCount x, const vImagePixelCount y) {
    extractBorderUsingPredicate(source, destination, x, y, [] (simd::float4 pixel) -> bool { return pixel.w < 1.0f; });
}

static void extractBorderUsingInitialColor(const vImage_Buffer *source, const vImage_Buffer *destination, const vImagePixelCount x, const vImagePixelCount y) {
    const auto srcRow = row_as_array_of<simd::float4>(source, y);
    const auto referenceColor = xyzToLab(srcRow[x].xyz);

    extractBorderUsingPredicate(source, destination, x, y, [referenceColor] (simd::float4 pixel) -> bool {
        return simd::distance_squared(xyzToLab(pixel.xyz), referenceColor) < 6.7f;
    });
}

void extractBorder(const vImage_Buffer *source, const vImage_Buffer *destination, CGRect roi) _NOEXCEPT {
    assert(source->width == destination->width && source->height == destination->height);

    roi = CGRectIntegral(CGRectStandardize(roi));

    const vImagePixelCount min_x = roi.origin.x;
    const vImagePixelCount min_y = roi.origin.y;
    const vImagePixelCount max_x = min_x + roi.size.width - 1;
    const vImagePixelCount max_y = min_y + roi.size.height - 1;

    if (min_x == 0 && min_y == 0 && max_x == source->width - 1 && max_y == source->height - 1) {
        memset(destination->data, 0x00, destination->rowBytes * destination->height);
    }
    else {
        memset(destination->data, 0xFF, destination->rowBytes * destination->height);
        for (auto y = min_y; y <= max_y; ++y) {
            auto row = row_as_array_of<uint8_t>(destination, y);
            memset(row + min_x, 0x00, roi.size.width);
        }
    }

    const auto first_row = row_as_array_of<const simd::float4>(source, min_y);
    const auto last_row  = row_as_array_of<const simd::float4>(source, max_y);

    if (first_row[min_x].w != 1.0f || first_row[max_x].w != 1.0f || last_row[min_x].w != 1.0f || last_row[max_x].w != 1.0f) {
        extractBorderUsingAlpha(source, destination, min_x, min_y);
        extractBorderUsingAlpha(source, destination, max_x, min_y);
        extractBorderUsingAlpha(source, destination, min_x, max_y);
        extractBorderUsingAlpha(source, destination, max_x, max_y);
    }
    else {
        extractBorderUsingInitialColor(source, destination, min_x, min_y);
        extractBorderUsingInitialColor(source, destination, max_x, min_y);
        extractBorderUsingInitialColor(source, destination, min_x, max_y);
        extractBorderUsingInitialColor(source, destination, max_x, max_y);
    }
}

_Bool detectEdges(const vImage_Buffer *buffer, CFErrorRef *error) _NOEXCEPT {
    try {
        __block managed_buffer minima { buffer->height, buffer->width, 8 };

        vImage_Error errc = vImageMin_Planar8(buffer, &minima, NULL, 0, 0, 3, 3, kvImageNoFlags);
        if (errc != kvImageNoError) throw vimage_exception(errc);

        dispatch_apply(buffer->height, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^(size_t y) {
            auto src = row_as_array_of<simd::uchar16>(buffer, y);
            auto min = row_as_array_of<const simd::uchar16>(&minima, y);
            auto end = min + (minima.width + 15) / 16;

            assert((end - min) * sizeof(*min) <= minima.rowBytes);
            assert(reinterpret_cast<const uint8_t *>(end) <= static_cast<const uint8_t *>(minima.data) + minima.rowBytes * minima.height);

            do {
                *src -= *min;
            } while (++src, ++min < end);
        });

        return true;
    }
    catch (vimage_exception &ex) {
        if (error) *error = CreateErrorFromException("VImageErrorDomain", ex.error_code(), ex);
        return false;
    }
    catch (std::exception &ex) {
        if (error) *error = CreateErrorFromException("UnknownErrorDomain", 0, ex);
        return false;
    }
    catch (...) {
        return false;
    }
}

CFArrayRef _Nullable detectSegments(const vImage_Buffer *buffer, CFErrorRef *error) _NOEXCEPT {
    try {
        static hough::trig_data trig;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            constexpr double scale = 2.0 / static_cast<double>(trig.size());
            for (auto i = 0; i < trig.size(); ++i) {
                trig[i] = vector2(__cospi(scale * i), __sinpi(scale * i));
            }
        });

        hough::analyzer<uint32_t> analyzer { buffer, trig };

        auto segments = analyzer.analyze();

        CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

        for (const auto &segment : segments) {
            auto x1 = segment.first.first;
            auto y1 = segment.first.second;
            auto x2 = segment.second.first;
            auto y2 = segment.second.second;

            auto seg = cf::array(cf::number(x1), cf::number(y1), cf::number(x2), cf::number(y2));

            CFArrayAppendValue(result, seg.get());
        }

        return result;
    }
    catch (vimage_exception &ex) {
        if (error) *error = CreateErrorFromException("VImageErrorDomain", ex.error_code(), ex);
        return NULL;
    }
    catch (std::exception &ex) {
        if (error) *error = CreateErrorFromException("GenericErrorDomain", 0, ex);
        return NULL;
    }
    catch (...) {
        return NULL;
    }
}
