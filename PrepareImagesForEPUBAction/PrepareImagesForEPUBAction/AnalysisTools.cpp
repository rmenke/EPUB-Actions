//
//  AnalysisTools.cpp
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 6/17/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#include "AnalysisTools.h"
#include "cf_util.hpp"

#include <simd/simd.h>

#include <algorithm>
#include <array>
#include <iostream>
#include <limits>
#include <map>
#include <queue>
#include <random>
#include <set>
#include <tuple>
#include <valarray>
#include <vector>

#pragma mark Type Definitions & Utilities

constexpr float close_path_limit = 25.0f;

using pixel_t   = simd::float2;
using segment_t = std::pair<pixel_t, pixel_t>;

static inline pixel_t make_pixel(float x, float y) {
    return pixel_t { x, y };
}

template <> struct std::less<pixel_t> {
    bool operator ()(pixel_t a, pixel_t b) const {
        if (a.x < b.x) return true;
        if (a.x > b.x) return false;

        return a.y < b.y;
    }
};

struct user_parameters {
    const double sensitivity;
    const int maxGap;
    const int closeGap;

#define PARAM(X,...) X(cf::get<std::remove_cv<decltype(X)>::type>(dictionary, CFSTR(#X)) __VA_ARGS__)
    user_parameters(CFDictionaryRef dictionary) : PARAM(sensitivity), PARAM(maxGap), PARAM(closeGap) { }
#undef PARAM
};

template <typename _Element>
static inline _Element *row_as_array_of(const vImage_Buffer *buffer, vImagePixelCount row) {
    return static_cast<_Element *>(buffer->data) + buffer->rowBytes * row / sizeof(_Element);
}

#pragma mark - Progressive Probabilistic Hough Transform

namespace hough {
    constexpr vImagePixelCount max_theta = 1024;

    template <size_t size>
    class trig_data : public std::array<pixel_t, size> {
    public:
        trig_data() {
            constexpr double scale = 2.0 / static_cast<double>(size);
            for (auto i = 0; i < size; ++i) {
                (*this)[i] = vector2(__cospif(scale * i), __sinpif(scale * i));
            }
        }
    };

    const trig_data<max_theta> trig;

    enum class state : unsigned char {
        unset, pending, voted
    };

    struct candidate_t {
        double z_lo = 0, z_hi = 0;
        std::set<pixel_t> points;

        candidate_t() = default;
        candidate_t(const candidate_t &) = delete;
        candidate_t(candidate_t &&) = default;

        ~candidate_t() = default;

        candidate_t &operator =(const candidate_t &) = delete;
        candidate_t &operator =(candidate_t &&) = default;
    };

    template <typename register_t = uint32_t>
    class analyzer {
        using queue_t = std::vector<pixel_t>;

        const vImagePixelCount width, height;

        const double rho_scale;
        const uint32_t max_rho;

        std::valarray<hough::state> image;
        std::valarray<register_t> accumulator;

        double threshold;
        unsigned max_gap;

        queue_t queue;
        int voted;

        std::default_random_engine rng { std::random_device{}() };

        static inline auto param(const vImage_Buffer *buffer, const user_parameters &p) {
            const double   diagonal  = std::ceil(std::hypot(buffer->width, buffer->height));
            const double   rho_scale = std::exp2(std::round(std::log2(max_theta) - std::log2(diagonal)));
            const uint32_t max_rho   = std::ceil(diagonal * rho_scale);

            return std::make_tuple(buffer->width, buffer->height, rho_scale, max_rho, p.sensitivity * -M_LN10, p.maxGap);
        }

        template <typename Param> analyzer(const Param &param) : width(std::get<0>(param)), height(std::get<1>(param)), rho_scale(std::get<2>(param)), max_rho(std::get<3>(param)), image(width * height), accumulator(max_theta * max_rho), threshold(std::get<4>(param)), max_gap(std::get<5>(param)) { }

    public:
        analyzer(const vImage_Buffer *buffer, const user_parameters &p) : analyzer(param(buffer, p)) {
            auto iter = std::begin(image);

            for (uint32_t y = 0; y < buffer->height; ++y) {
                const uint8_t *row = row_as_array_of<uint8_t>(buffer, y);

                for (uint32_t x = 0; x < buffer->width; ++x) {
                    if (row[x]) {
                        *iter = state::pending;
                        queue.push_back(make_pixel(x, y));
                    }
                    else {
                        *iter = state::unset;
                    }
                    ++iter;
                }
            }
        };

        bool vote(const pixel_t &pixel, vImagePixelCount *theta, vImagePixelCount *rho) {
            register_t n = 0;

            std::vector<std::pair<vImagePixelCount, vImagePixelCount>> peaks;

            for (vImagePixelCount theta = 0; theta < max_theta; ++theta) {
                vImagePixelCount rho = std::lround(simd::dot(pixel, trig[theta]) * rho_scale);
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

            // For the null hypothesis, the cells are filled (roughly)
            // according to a Poisson model:
            //
            //    p(n) = λⁿ/n!·exp(-λ)
            //         = λⁿ/Γ(n+1)·exp(-λ)
            // ln p(n) = n ln(λ) - lnΓ(n+1) - λ

            const double lnp = n * log(lambda) - lgamma(n + 1) - lambda;

            // lnp is the (log) probability that a bin that was filled
            // randomly would contain a count of n. If the probability
            // is below the significance threshold, we reject the null
            // hypothesis for this point.

            if (lnp <= threshold) {
                if (peaks.size() > 1) {
                    // If there is multiple options for a scan
                    // channel, reduce the options to the ones that
                    // are most orthogonal (i.e., the ones parallel to
                    // the axes, then the ones at π/4, then the ones
                    // at π/8, &c).
                    //
                    // This isn't standard PPHT, but for the purposes
                    // of this project it will do.

                    unsigned int factor = 512;

                    const auto theta_is_multiple_of_factor = [&factor] (const std::pair<vImagePixelCount, vImagePixelCount> &a) -> bool {
                        return (a.first % factor) == 0;
                    };

                    do {
                        factor >>= 1;

                        auto end = std::partition(peaks.begin(), peaks.end(), theta_is_multiple_of_factor);

                        if (end != peaks.begin()) {
                            peaks.erase(end, peaks.end());
                        }
                    } while (peaks.size() > 1 && factor > 1);

                    assert(peaks.size() > 0);
                }

                // In the unlikely event we still have multiple
                // candidates, just pick one at random.
                // std::uniform_int_distribution handles the case
                // where peaks.size() == 1 correctly and efficiently.

                auto index = std::uniform_int_distribution<size_t>(0, peaks.size() - 1)(rng);

                std::tie(*theta, *rho) = peaks[index];

                return true;
            }

            return false;
        }

        void unvote(const pixel_t &pixel) {
            for (vImagePixelCount theta = 0; theta < max_theta; ++theta) {
                vImagePixelCount rho = std::lround(simd::dot(pixel, trig[theta]) * rho_scale);
                if (rho < 0 || rho >= max_rho) continue;

                auto &count = accumulator[theta + rho * max_theta];

                if (count > 0) --count;
            }

            --voted;
        }

        std::vector<segment_t> analyze() {
            std::vector<segment_t> result;

            const auto begin = queue.begin();
            auto end = queue.end();

            voted = 0;

            while (begin != end) {
                auto ix = std::uniform_int_distribution<queue_t::size_type>(0, std::distance(begin, end) - 1)(rng);

                std::swap(queue[ix], *(--end));
                const pixel_t &pixel = *end;

                state &cell = image[static_cast<long>(pixel.x + pixel.y * width)];
                if (cell != state::pending) continue;

                cell = state::voted;

                vImagePixelCount theta, rho;

                if (!vote(pixel, &theta, &rho)) continue;

                // (theta, rho) is the point on the line candidate in
                // polar coordinates perpendicular to a line from the
                // origin.  (p₀.x, p₀.y) is the equivalent point in
                // cartesian coordinates.  Rotating the angle theta by
                // 90° will give ∆ = (∆x, ∆y) in cartesian coordinates.
                // These four values describe the parametric form of
                // the line: p₀ + ∆t

                auto p0 = rho / rho_scale * trig[theta];

                auto delta = trig[(theta + max_theta / 4) % max_theta];

                // A line is infinite.  Find the range of the
                // parameter of the line which defines the points that
                // lie within the image boundary.

                const auto bounds = make_pixel(std::nextafterf(width, 0), std::nextafterf(height, 0));

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

                // This shouldn't happen, but if z_min or z_max are
                // infinite then the line lies entirely outside of the
                // region of interest.

                if (!isfinite(z_min) || !isfinite(z_max)) continue;

                std::vector<candidate_t> segments;

                candidate_t segment { 0, 0, { } };

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
                                segment.points.insert(make_pixel(x, y));
                                hit = true;
                            }
                        }
                    }

                    if (hit) {
                        if (gap) segment.z_lo = z;
                        segment.z_hi = z;
                        gap = 0;
                    }
                    else {
                        ++gap;

                        if (gap >= max_gap * 2 && !segment.points.empty()) {
                            segments.emplace_back(std::move(segment));
                            segment.points.clear();
                        }
                    }
                }

                if (!segment.points.empty()) {
                    segments.emplace_back(std::move(segment));
                }

                if (segments.empty()) {
                    return { };
                }

                auto max_iter = std::max_element(segments.begin(), segments.end(), [] (const candidate_t &s1, const candidate_t &s2) {
                    auto l1 = s1.z_hi - s1.z_lo;
                    auto l2 = s2.z_hi - s2.z_lo;
                    return l1 < l2;
                });

                segment = std::move(*max_iter);

                for (const auto &pixel : segment.points) {
                    auto &state = image[pixel.x + pixel.y * width];

                    if (state == state::voted) {
                        unvote(pixel);
                    }

                    state = state::unset;
                }

                const auto p1 = p0 + delta * segment.z_lo;
                const auto p2 = p0 + delta * segment.z_hi;

                if (simd::distance_squared(p1, p2) > 100.0) {
                    result.emplace_back(p1, p2);
                }
            }

            return result;
        }
    };
}

#pragma mark - Flood Fill

namespace fill {
    static constexpr simd::float3 D50 { 0.964355f, 1.0f, 0.825195f };

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

    template <typename _Predicate> void using_predicate(const vImage_Buffer *source, const vImage_Buffer *destination, vImagePixelCount x, vImagePixelCount y, _Predicate is_fillable) {
        std::queue<std::pair<vImagePixelCount, vImagePixelCount>> queue;

        queue.emplace(x, y);

        while (!queue.empty()) {
            std::tie(x, y) = queue.front();

            queue.pop();

            const auto srcRow = row_as_array_of<const simd::float4>(source, y);
            const auto dstRow = row_as_array_of<uint8_t>(destination, y);

#define is_open(x) (!dstRow[x] && is_fillable(srcRow[x]))

            if (!is_open(x)) continue;

            const auto w = source->width - 1;
            const auto h = source->height - 1;

            vImagePixelCount lo = x, hi = x;

            while (lo > 0 && is_open(lo - 1)) --lo;
            while (hi < w && is_open(hi + 1)) ++hi;

#undef is_open

            memset(dstRow + lo, 255, (hi - lo) + 1);

            if (y > 0) {
                for (auto x = lo; x <= hi; ++x) {
                    queue.emplace(x, y - 1);
                }
            }
            if (y < h) {
                for (auto x = lo; x <= hi; ++x) {
                    queue.emplace(x, y + 1);
                }
            }
        }
    }

    static void using_alpha(const vImage_Buffer *source, const vImage_Buffer *destination, const vImagePixelCount x, const vImagePixelCount y) {
        using_predicate(source, destination, x, y, [] (const simd::float4 &pixel) -> bool {
            return pixel.w < 0.5f;
        });
    }

    static void using_color(const vImage_Buffer *source, const vImage_Buffer *destination, const vImagePixelCount x, const vImagePixelCount y) {
        const auto referenceColor = xyzToLab(row_as_array_of<simd::float4>(source, y)[x].xyz);

        using_predicate(source, destination, x, y, [referenceColor] (const simd::float4 &pixel) -> bool {
            return simd::distance_squared(xyzToLab(pixel.xyz), referenceColor) < 6.7f;
        });
    }
}

#pragma mark - Polyline utilities

namespace polyline {
    /*!
     * @abstract Find the intersection point of two line segments.
     *
     * @param a The start of the first segment.
     * @param b The end of the first segment.
     * @param c The start of the second segment.
     * @param d The end of the second segment.
     *
     * @return The intersection point of the lines coinciding with the segments.  If the segments are parallel, this solution will contain NaN.
     */
    template <typename _simd> static inline _simd intersection(_simd a, _simd b, _simd c, _simd d) {
        const auto t = (b - a);
        const auto u = (d - c);

        const auto v = t.yx * u;

        if (v.x == v.y) {   // segments are parallel or coincident.
            // r1 and r2 are the distances from the origin to the line segment multiplied by the length of t.
            // No need to normalize because we are only comparing magnitudes.
            const auto r1 = simd::dot(a, t.yx);
            const auto r2 = simd::dot(c, t.yx);

            if (fabs(r1 - r2) < 1E-6) { // coincident or close enough
                return (a + c) / 2;
            }

            return {INFINITY, INFINITY};
        }

        auto p = t.yx * a;
        p = (p.y - p.x) * u;

        auto q = u.yx * c;
        q = (q.y - q.x) * t;

        return (p - q) / (v.y - v.x);
    }

    template <typename FwdIter1, typename FwdIter2> static inline auto intersection(FwdIter1 iter1, FwdIter2 iter2) {
        return intersection(*iter1, *std::next(iter1), *iter2, *std::next(iter2));
    }

    using polyline_t = std::deque<pixel_t>;

    template <typename Iterator, typename PointIterator, typename AppendIterator>
    Iterator grow_polyline(Iterator begin, Iterator end, PointIterator iter, AppendIterator out) {
        if (begin == end) return end;

        const auto p0 = *iter;
        const auto p1 = *std::next(iter);

        auto measure_distance = [&p0] (polyline_t &p) {
            const auto d1 = simd::distance_squared(p0, p.front());
            const auto d2 = simd::distance_squared(p0, p.back());

            return std::make_pair(d1 > d2 ? d2 : d1, d1 > d2);
        };

        auto d = measure_distance(*begin);
        auto distance = d.first;
        if (d.second) std::swap(begin->front(), begin->back());

        auto candidate_iter = begin;

        for (auto iter = std::next(begin); iter != end; ++iter) {
            d = measure_distance(*iter);
            if (distance > d.first) {
                distance = d.first;
                if (d.second) std::swap(iter->front(), iter->back());
                candidate_iter = iter;
            }
        }

        if (distance <= close_path_limit) {
            auto q0 = candidate_iter->front();
            auto q1 = candidate_iter->back();

            auto q2 = intersection(p0, p1, q0, q1);
            auto d  = simd::distance_squared(p0, q2);
            if (d > distance) {
                q2 = (p0 + q0) / 2;
            }

            *candidate_iter = std::move(*(--end));
            *iter = intersection(p0, p1, q2, q1);
            *out  = q1;
        }

        return end;
    }

    std::vector<polyline_t> link_segments(const std::vector<segment_t> &segments, float close_gap) {
        const float close_gap_squared = close_gap * close_gap;

        std::vector<polyline_t> result;

        for (const auto &segment : segments) {
            result.emplace_back();
            result.back().push_back(segment.first);
            result.back().push_back(segment.second);
        }

        auto begin = result.begin();
        auto end   = result.end();

    next_segment:
        while (begin != end) {
            auto longest = std::max_element(begin, end, [] (const polyline_t &a, const polyline_t &b) {
                return simd::distance_squared(a.front(), a.back()) < simd::distance_squared(b.front(), b.back());
            });

            std::swap(*begin, *longest);
            polyline_t &current = *begin;

            ++begin;

            while (begin != end) {
                auto new_end = grow_polyline(begin, end, current.rbegin(), std::back_inserter(current));

                if (new_end == end) break;

                end = new_end;

                if (simd::distance_squared(current.front(), current.back()) <= close_gap_squared) {
                    current.front() = current.back() = intersection(current.begin(), current.rbegin());
                    goto next_segment;
                }
            }

            while (begin != end) {
                auto new_end = grow_polyline(begin, end, current.begin(), std::front_inserter(current));

                if (new_end == end) break;

                end = new_end;

                if (simd::distance_squared(current.front(), current.back()) <= close_gap_squared) {
                    current.front() = current.back() = intersection(current.begin(), current.rbegin());
                    goto next_segment;
                }
            }
        }

        result.erase(end, result.end());

        return result;
    }
}

namespace region {
    using region_t = simd::float4;
    using range_t  = simd::float2;

    auto overlap(range_t r1, region_t b) {
        const range_t r2 = b.yw;

        auto inter  = std::min(r1.y, r2.y) - std::max(r1.x, r2.x);
        auto length = std::min(r1.y - r1.x, r2.y - r2.x);

        return inter / length;
    }

    auto center(region_t r) {
        return (r.hi + r.lo) / 2.0f;
    }

    inline region_t expand_region(region_t region, float d) {
        simd::float2 offset = vector2(d, d);

        region.lo -= offset;
        region.hi += offset;

        return region;
    }

    inline region_t intersect_region(region_t a, region_t b) {
        region_t region;

        region.lo = simd::max(a.lo, b.lo);
        region.hi = simd::min(a.hi, b.hi);

        return region;
    }

    inline region_t union_region(region_t a, region_t b) {
        region_t region;

        region.lo = simd::min(a.lo, b.lo);
        region.hi = simd::max(a.hi, b.hi);

        return region;
    }

    std::vector<region_t> detect_regions(const std::vector<polyline::polyline_t> &polylines) {
        std::vector<region_t> regions;

        for (const auto &polyline : polylines) {
            auto begin = polyline.begin();
            auto end   = polyline.end();

            simd::float4 region = simd::rint(vector4(*begin, *begin));

            while (++begin != end) {
                auto p = simd::rint(*begin);
                region.lo = simd::min(region.lo, p);
                region.hi = simd::max(region.hi, p);
            }

            regions.push_back(region);
        }

        auto begin = regions.begin();
        auto end   = regions.end();

        for (auto i = begin; i != end; ++i) {
            auto a = *i;

            for (auto j = i + 1; j != end; ++j) {
                const auto b = *j;

                if (simd::all(intersect_region(expand_region(a, 2), b) == b) || simd::all(intersect_region(a, expand_region(b, 2)) == a)) {
                    *i = a = union_region(a, b);
                    *j = std::move(*(--end));
                    j = i;
                }
            }
        }

        std::sort(begin, end, [] (region_t a, region_t b) -> bool {
            return a.y < b.y;
        });

        while (begin != end) {
            auto range = begin->s13;

            auto predicate = [&range] (region_t r) -> bool {
                return overlap(range, r) > 0.90;
            };

            auto row_end = std::next(begin);

            while (row_end != end) {
                auto new_end = std::partition(row_end, end, predicate);
                if (new_end == row_end) break;

                range = std::accumulate(row_end, new_end, range, [] (range_t range, region_t region) {
                    return range_t { std::min(range.x, region.s1), std::max(range.y, region.s3) };
                });

                row_end = new_end;
            }

            std::sort(begin, row_end, [] (region_t a, region_t b) -> bool {
                auto centerline = simd::fabs(center(a) - center(b));

                if (centerline.y > centerline.x) {
                    return a.y < b.y;
                }
                else {
                    return a.x < b.x;
                }
            });

            begin = row_end;
        }

        regions.erase(end, regions.end());

        return regions;
    }
}

#pragma mark - CoreFoundation interfaces

void extractBorder(const vImage_Buffer *source, const vImage_Buffer *destination, CGRect rect) _NOEXCEPT {
    assert(source->width == destination->width && source->height == destination->height);

    const vImagePixelCount min_x = CGRectGetMinX(rect);
    const vImagePixelCount min_y = CGRectGetMinY(rect);
    const vImagePixelCount max_x = CGRectGetMaxX(rect) - 1;
    const vImagePixelCount max_y = CGRectGetMaxY(rect) - 1;

    if (min_x == 0 && min_y == 0 && max_x == source->width - 1 && max_y == source->height - 1) {
        memset(destination->data, 0x00, destination->rowBytes * destination->height);
    }
    else {
        memset(destination->data, 0xff, destination->rowBytes * destination->height);
        for (auto y = min_y; y <= max_y; ++y) {
            auto row = row_as_array_of<uint8_t>(destination, y);
            memset(row + min_x, 0x00, CGRectGetWidth(rect));
        }
    }

    const auto first_row = row_as_array_of<const simd::float4>(source, min_y);
    const auto last_row  = row_as_array_of<const simd::float4>(source, max_y);

    void (*fill)(const vImage_Buffer *source, const vImage_Buffer *destination, vImagePixelCount x, vImagePixelCount y);

    if (first_row[min_x].w != 1.0f || first_row[max_x].w != 1.0f || last_row[min_x].w != 1.0f || last_row[max_x].w != 1.0f) {
        fill = &fill::using_alpha;
    }
    else {
        fill = &fill::using_color;
    }

    fill(source, destination, min_x, min_y);
    fill(source, destination, max_x, min_y);
    fill(source, destination, min_x, max_y);
    fill(source, destination, max_x, max_y);
}

CFArrayRef _Nullable detectSegments(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT {
    try {
        auto segments = hough::analyzer<uint32_t>(buffer, user_parameters{parameters}).analyze();

        CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

        for (const auto &segment : segments) {
            auto x1 = segment.first.x;
            auto y1 = segment.first.y;
            auto x2 = segment.second.x;
            auto y2 = segment.second.y;

            auto seg = cf::array(cf::number(x1), cf::number(y1), cf::number(x2), cf::number(y2));

            CFArrayAppendValue(result, seg.get());
        }

        return result;
    }
    catch (std::system_error &ex) {
        if (error) *error = cf::system_error(ex);
        return NULL;
    }
    catch (std::exception &ex) {
        if (error) *error = cf::error(ex);
        return NULL;
    }
    catch (...) {
        if (error) *error = cf::error();
        return NULL;
    }
}

CFArrayRef _Nullable detectPolylines(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT {
    try {
        user_parameters params { parameters };

        auto segments = hough::analyzer<uint32_t>(buffer, params).analyze();
        auto polylines = polyline::link_segments(segments, params.closeGap);

        CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

        for (const auto &polyline : polylines) {
            CFMutableArrayRef array = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

            for (const pixel_t &pixel : polyline) {
                CFArrayAppendValue(array, cf::number(pixel.x).get());
                CFArrayAppendValue(array, cf::number(pixel.y).get());
            }

            CFArrayAppendValue(result, array);

            CFRelease(array);
        }

        return result;
    }
    catch (std::system_error &ex) {
        if (error) *error = cf::system_error(ex);
        return NULL;
    }
    catch (std::exception &ex) {
        if (error) *error = cf::error(ex);
        return NULL;
    }
    catch (...) {
        if (error) *error = cf::error();
        return NULL;
    }
}

CFArrayRef _Nullable detectRegions(const vImage_Buffer *buffer, CFDictionaryRef parameters, CFErrorRef *error) _NOEXCEPT {
    try {
        user_parameters params { parameters };

        const auto segments = hough::analyzer<uint32_t>(buffer, params).analyze();
        const auto polylines = polyline::link_segments(segments, params.closeGap);
        const auto regions = region::detect_regions(polylines);

        CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, regions.size(), &kCFTypeArrayCallBacks);

        for (const auto &region : regions) {
            const auto size = region.hi - region.lo;

            const auto array = cf::array(cf::number(region.x), cf::number(region.y), cf::number(size.x), cf::number(size.y));

            CFArrayAppendValue(result, array.get());
        }

        return result;
    }
    catch (std::system_error &ex) {
        if (error) *error = cf::system_error(ex);
        return NULL;
    }
    catch (std::exception &ex) {
        if (error) *error = cf::error(ex);
        return NULL;
    }
    catch (...) {
        if (error) *error = cf::error();
        return NULL;
    }
}

