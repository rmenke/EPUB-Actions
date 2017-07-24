//
//  HoughTransform.cpp
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 6/14/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

#include "HoughTransform.h"

#include <array>
#include <cmath>
#include <iostream>
#include <forward_list>
#include <map>
#include <queue>
#include <random>
#include <set>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>
#include <valarray>
#include <vector>

constexpr vImagePixelCount maxTheta = 1024;

// The maximum absolute cosine before considering that two segments are colinear.
constexpr double cosineTolerance = 0.999;

static CFStringRef kHTErrorDomain = CFSTR("HoughTransformErrorDomain");

static std::array<simd::double2, maxTheta> trig;

/*!
 * @abstract Calculate the cosine of the angle formed by three points.
 *
 * @discussion Use the law of cosines:
 * <code>cos(∠abc) = (|ab|²+|bc|²-|ac|²) / (2|ab||bc|)</code>
 *
 * @param a The first point of the angle
 * @param b The vertex of the angle
 * @param c The third point of the angle
 * @return The cosine of the angle formed by the three points
 */
template <typename _V>
static inline auto cosine(_V a, _V b, _V c) -> typename std::remove_reference<decltype(a.x)>::type {
    auto ab2 = simd::distance_squared(a, b);
    auto bc2 = simd::distance_squared(b, c);
    auto ac2 = simd::distance_squared(a, c);

    auto ab = std::sqrt(ab2);
    auto bc = std::sqrt(bc2);

    return (ab2 + bc2 - ac2) / (2.0 * ab * bc);
}

template <>
struct std::less<simd::uint2> {
    bool operator()(simd::uint2 a, simd::uint2 b) const {
        return (a.x < b.x) || (a.x == b.x && a.y < b.y);
    }
};

namespace cf {      // Core Foundation support
    struct __release {
        void operator()(CFTypeRef r) const {
            CFRelease(r);
        }
    };

    template <typename T> using managed = std::unique_ptr<typename std::remove_pointer<T>::type, struct __release>;

    static inline managed<CFNumberRef> make_number(CGFloat f) {
        return managed<CFNumberRef> { CFNumberCreate(kCFAllocatorDefault, kCFNumberCGFloatType, &f) };
    }

    template <typename... T>
    static inline managed<CFArrayRef> make_array(const T &... args) {
        CFTypeRef refs[] = { args.get()... };
        return managed<CFArrayRef> {
            CFArrayCreate(kCFAllocatorDefault, refs, sizeof...(args), &kCFTypeArrayCallBacks)
        };
    }

    static inline managed<CFErrorRef> make_error_from_exception(const std::system_error &e) {
        managed<CFDictionaryRef> userInfo;

        const char * const reason = e.what();
        const std::error_code &code = e.code();
        const std::error_category &category = code.category();

        if (reason) {
            managed<CFStringRef> description {
                CFStringCreateWithCString(kCFAllocatorDefault, reason, kCFStringEncodingUTF8)
            };

            userInfo.reset(CFDictionaryCreate(kCFAllocatorDefault, (CFTypeRef[]) { kCFErrorLocalizedDescriptionKey }, (CFTypeRef[]) { description.get() }, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks));
        }

        managed<CFStringRef> domain {
            (category == std::system_category() ? kCFErrorDomainPOSIX : CFStringCreateWithCString(kCFAllocatorDefault, category.name(), kCFStringEncodingUTF8))
        };

        return managed<CFErrorRef> { CFErrorCreate(kCFAllocatorDefault, domain.get(), code.value(), userInfo.get()) };
    }

    static inline managed<CFErrorRef> make_error_from_exception(const std::exception &e) {
        managed<CFDictionaryRef> userInfo { nullptr };

        const char * const reason = e.what();

        if (reason) {
            managed<CFStringRef> description {
                CFStringCreateWithCString(kCFAllocatorDefault, reason, kCFStringEncodingUTF8)
            };

            userInfo.reset(CFDictionaryCreate(kCFAllocatorDefault, (CFTypeRef[]) { kCFErrorLocalizedDescriptionKey }, (CFTypeRef[]) { description.get() }, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks));
        }

        return managed<CFErrorRef> { CFErrorCreate(kCFAllocatorDefault, kHTErrorDomain, 0, userInfo.get()) };
    }

    static inline managed<CFErrorRef> make_error_from_exception() {
        managed<CFDictionaryRef> userInfo {
            CFDictionaryCreate(kCFAllocatorDefault, (CFTypeRef[]) { kCFErrorLocalizedDescriptionKey }, (CFTypeRef[]) { CFSTR("An unexpected exception occurred.") }, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks)
        };

        return managed<CFErrorRef> { CFErrorCreate(kCFAllocatorDefault, kHTErrorDomain, 0, userInfo.get()) };
    }
}

namespace hough {
    enum class state : unsigned char {
        unset, pending, voted
    };

    class scoreboard {
        using accumulator_type = uint32_t;

        const double rhoScale;
        const unsigned long maxRho;
        const unsigned long width;

        std::valarray<hough::state> image;
        std::valarray<accumulator_type> accumulator;

        std::vector<simd::uint2> queue;

        int voted;
        const double threshold;

        std::default_random_engine rng;

        struct param {
            const vImagePixelCount width, height;

            const double diagonal, rhoScale, maxRho, threshold;

            param(const vImage_Buffer *buffer, double significance) :
                width(buffer->width), height(buffer->height),
                diagonal(std::ceil(std::hypot(width, height))),
                rhoScale(std::exp2(std::ceil(std::log2(maxTheta) - std::log2(diagonal)))),
                maxRho(std::ceil(diagonal * rhoScale)),
                threshold(std::log(significance)) { }
        };

        scoreboard(const param &p) : rhoScale(p.rhoScale), maxRho(p.maxRho), width(p.width), image(hough::state::unset, p.width * p.height), accumulator(p.maxRho * maxTheta), voted(0), threshold(p.threshold) { }

    public:
        scoreboard(const vImage_Buffer *buffer, uint8_t grayThreshold, double significance) : scoreboard(param(buffer, significance)) {
            auto iter = std::begin(image);

            for (unsigned int y = 0; y < buffer->height; ++y) {
                const uint8_t * const srcRow = static_cast<uint8_t *>(buffer->data) + buffer->rowBytes * y;

                for (unsigned int x = 0; x < buffer->width; ++x) {
                    if (srcRow[x] > grayThreshold) {
                        *iter = hough::state::pending;
                        queue.push_back(simd::uint2 { x, y });
                    }
                    ++iter;
                }
            }

            assert(iter == std::end(image));

            std::random_shuffle(queue.begin(), queue.end());
        }

        bool is_set(simd::uint2 p) const {
            if (p.x >= width) return false;

            const auto index = p.x + p.y * width;
            if (index >= image.size()) return false;

            assert(p.x < width && index < image.size());
            return image[index] != state::unset;
        }

        bool vote(simd::uint2 pixel, vImagePixelCount *peakTheta, double *peakRho) {
            const auto index = pixel.x + pixel.y * width;
            assert(pixel.x < width && index < image.size());

            hough::state &cell = image[index];
            assert(cell == state::pending);

            const auto p = vector_double(pixel);

            accumulator_type n { };

            using coord    = std::pair<vImagePixelCount, vImagePixelCount>;
            using peak_vec = std::vector<coord>;

            peak_vec peaks;

            // Increment the values in the register, saving the theta-rho pairs
            // that have the highest value.

            for (vImagePixelCount theta = 0; theta < maxTheta; ++theta) {
                auto rho = std::rint(simd::dot(p, trig[theta]) * rhoScale);
                if (rho < 0 || rho >= maxRho) continue;

                const accumulator_type count = ++accumulator[theta + rho * maxTheta];

                if (n < count) {
                    n = count;
                    peaks.clear();
                }

                if (n == count) {
                    peaks.emplace_back(theta, rho);
                }
            }

            cell = state::voted;

            ++voted;

            // There are maxTheta * maxRho cells in the register.
            // Each vote will increment maxTheta of these cells, one
            // per column.
            //
            // Assuming the null hypothesis (the image is random noise),
            // E[n] = votes/maxRho for all cells in the register.

            const double lambda = static_cast<double>(voted) / maxRho;

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

                    const auto theta_is_multiple_of_factor = [&factor](const coord &a) {
                        return (a.first % factor) == 0;
                    };

                    peak_vec::iterator new_end;

                    do {
                        factor >>= 1;

                        assert(factor > 0);

                        new_end = std::partition(peaks.begin(), peaks.end(), theta_is_multiple_of_factor);
                    } while (new_end == peaks.begin());

                    peaks.erase(new_end, peaks.end());

                    assert(peaks.size() > 0);
                }

                // In the unlikely event we still have multiple candidates, just pick one at random.
                // std::uniform_int_distribution handles the case where peaks.size() == 1 correctly and efficiently.

                auto index = std::uniform_int_distribution<peak_vec::size_type>(0, peaks.size() - 1)(rng);

                std::tie(*peakTheta, *peakRho) = peaks[index];

                *peakRho /= rhoScale;

                return true;
            }

            return false;
        }

        template <class _InputIterator> void unvote(_InputIterator __f, _InputIterator __l) {
            for (auto iter = __f; iter != __l; ++iter) {
                auto &cell = image[iter->x + iter->y * width];

                if (cell == state::voted) {
                    auto p = vector_double(*iter);

                    for (vImagePixelCount theta = 0; theta < maxTheta; ++theta) {
                        auto rho = std::rint(simd::dot(p, trig[theta]) * rhoScale);
                        if (rho < 0 || rho >= maxRho) continue;

                        accumulator_type &cell = accumulator[theta + rho * maxTheta];

                        assert(cell > 0);

                        --cell;
                    }

                    --voted;
                }

                cell = state::unset;
            }
        }

        class iterator {
            using base_iter = std::vector<simd::uint2>::iterator;

            base_iter i;
            const scoreboard &sb;

        public:
            using difference_type = base_iter::difference_type;
            using value_type = base_iter::value_type;
            using pointer = base_iter::pointer;
            using reference = base_iter::reference;
            using iterator_category = std::forward_iterator_tag;

            iterator(const std::vector<simd::uint2>::iterator &iter, const scoreboard &sb) : i(iter), sb(sb) {
                for (auto end = sb.queue.end(); i != end && sb.image[i->x + i->y * sb.width] != state::pending; ++i);
            }

            bool operator!=(const iterator &r) const {
                return i != r.i;
            }

            reference operator*() const {
                return i.operator*();
            }

            pointer operator->() const {
                return i.operator->();
            }

            iterator &operator++() {
                ++i;
                for (auto end = sb.queue.end(); i != end && sb.image[i->x + i->y * sb.width] != state::pending; ++i);
                return *this;
            }

            iterator operator++(int) {
                iterator tmp { *this };
                operator++();
                return tmp;
            }
        };

        iterator begin() {
            return iterator { queue.begin(), *this };
        }

        iterator end() {
            return iterator { queue.end(), *this };
        }
    };

    class image_segment {
        // A vector is fine; duplicate points do not affect the unvoting process.
        using point_vector = std::vector<simd::uint2>;

        simd::double2 start, finish;
        point_vector points;

    public:
        image_segment(simd::uint2 p) : start(vector_double(p)) { }

        template <typename _Vector> void extend(_Vector v) {
            finish = vector_double(v);
        }

        template <typename _ForwardIterator>
        void insert(_ForwardIterator &&__f, _ForwardIterator &&__l) {
            std::copy(std::forward<_ForwardIterator>(__f), std::forward<_ForwardIterator>(__l), std::back_inserter(points));
        }

        double length_squared() const {
            return simd::distance_squared(start, finish);
        }

        point_vector::const_iterator begin() const {
            return points.begin();
        }

        point_vector::const_iterator end() const {
            return points.end();
        }

        simd::double4 segment() const {
            return vector4(start, finish);
        }
    };
}

static std::vector<simd::double4> find_segments_in_image(const vImage_Buffer *buffer, uint8_t gray_threshold, double significance, unsigned channel_width, unsigned max_gap) {
    if (buffer->width == 0 && buffer->height == 0) return std::vector<simd::double4> { };

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (vImagePixelCount theta = 0; theta < maxTheta; ++theta) {
            auto angle = static_cast<double>(theta) / (maxTheta / 2);
            trig[theta] = vector2(__cospi(angle), __sinpi(angle));
        }
    });

    hough::scoreboard scoreboard { buffer, gray_threshold, significance };

    std::vector<simd::double4> found_segments;

    for (auto p : scoreboard) {
        vImagePixelCount theta;
        double rho;

        if (scoreboard.vote(p, &theta, &rho)) {
            auto delta = trig[(theta + maxTheta / 4) % maxTheta];
            delta /= vector_reduce_max(simd::fabs(delta));

            const auto offset = trig[theta];

            const auto bounds = simd::double2 { std::nextafter(buffer->width, 0), std::nextafter(buffer->height, 0) };

            auto p0 = rho * offset;

            auto z0 = - p0 / delta;
            auto z1 = (bounds - p0) / delta;

            double zMin = +INFINITY, zMax = -INFINITY;

            if (isfinite(z0.x)) {
                auto y = z0.x * delta.y + p0.y;
                if (y >= 0 && y <= bounds.y) {
                    if (zMin > z0.x) zMin = z0.x;
                    if (zMax < z0.x) zMax = z0.x;
                }
            }
            if (isfinite(z0.y)) {
                auto x = z0.y * delta.x + p0.x;
                if (x >= 0 && x <= bounds.x) {
                    if (zMin > z0.y) zMin = z0.y;
                    if (zMax < z0.y) zMax = z0.y;
                }
            }
            if (isfinite(z1.x)) {
                auto y = z1.x * delta.y + p0.y;
                if (y >= 0 && y <= bounds.y) {
                    if (zMin > z1.x) zMin = z1.x;
                    if (zMax < z1.x) zMax = z1.x;
                }
            }
            if (isfinite(z1.y)) {
                auto x = z1.y * delta.x + p0.x;
                if (x >= 0 && x <= bounds.x) {
                    if (zMin > z1.y) zMin = z1.y;
                    if (zMax < z1.y) zMax = z1.y;
                }
            }

            if (!isfinite(zMin) || !isfinite(zMax)) continue;

            int count = std::ceil(zMax) - std::floor(zMin);

            p0 += delta * zMin;

            std::vector<hough::image_segment> segments;

            bool in_segment = false;

            int gap = 0;

            for (int i = 0; i < count; ++i) {
                std::set<simd::uint2> points;

                for (int c = 1; c <= (channel_width >> 1); ++c) {
                    auto q = vector_uint(simd::rint(p0 + offset * c));

                    if (scoreboard.is_set(q)) {
                        points.insert(q);
                    }

                    q = vector_uint(simd::rint(p0 - offset * c));

                    if (scoreboard.is_set(q)) {
                        points.insert(q);
                    }
                }

                // q is the center of the scan channel and the canonical point on the segment
                auto q = vector_uint(simd::rint(p0));

                if (scoreboard.is_set(q)) {
                    points.insert(q);
                }

                if (!points.empty()) {
                    if (!in_segment) {
                        in_segment = true;
                        segments.emplace_back(q); // starts a new segment
                    }

                    hough::image_segment &segment = segments.back();

                    segment.extend(q);
                    segment.insert(points.begin(), points.end());

                    gap = 0;
                }
                else if (gap < max_gap) {
                    gap++;
                }
                else {
                    in_segment = false;
                }

                p0 += delta;
            }

            auto longest_segment = std::max_element(segments.begin(), segments.end(), [](const hough::image_segment &a, const hough::image_segment &b) {
                return a.length_squared() < b.length_squared();
            });

            if (longest_segment != segments.end()) {
                scoreboard.unvote(longest_segment->begin(), longest_segment->end());
                found_segments.push_back(longest_segment->segment());
            }
        }
    }

    // Post-processing
    //
    // Find segments that are colinear and share an endpoint.
    // If they overlap, remove the smaller one; otherwise, join the segments.

    const auto max_gap_squared = max_gap * max_gap;

    auto end = found_segments.end();

    for (auto i = found_segments.begin(); i != end; ++i) {
        auto a = i->lo, b = i->hi;

        for (auto j = i + 1; j != end; ++j) {
            assert(simd::all(a == i->lo) && simd::all(b == i->hi));

            auto c = j->lo, d = j->hi;

            simd::double2 x, y, z;

            if (simd::distance_squared(a, c) <= max_gap_squared) {
                x = b; y = (a + c) / 2.0; z = d;
            }
            else if (simd::distance_squared(b, c) <= max_gap_squared) {
                x = a; y = (b + c) / 2.0; z = d;
            }
            else if (simd::distance_squared(a, d) <= max_gap_squared) {
                x = b; y = (a + d) / 2.0; z = c;
            }
            else if (simd::distance_squared(b, d) <= max_gap_squared) {
                x = a; y = (b + d) / 2.0; z = c;
            }
            else {
                continue;
            }

            const auto cs = cosine(x, y, z);

            // If the segments are not colinear, nothing else can be done.
            if (cs >= -cosineTolerance && cs <= +cosineTolerance) continue;

            // Segments share only the endpoint...
            if (cs < 0) {
                // y is between x and z; merge the two segments into one segment.
                *i = vector4(a = x, b = z);

                // Delete *j by remove-erase idiom.
                *j = *(--end);

                // After updating *i, restart checks.
                j = i;
            }
            // ...otherwise they overlap and the shorter is redundant.
            else if (simd::distance_squared(a, b) < simd::distance_squared(c, d)) {
                *i = *j; a = i->lo; b = i->hi;

                // Delete *j by remove-erase idiom.
                *j = *(--end);

                // After updating *i, restart checks.
                j = i;
            }
            else {
                // Delete *j by remove-erase idiom.  Since *i is unchanged,
                // the checks need not be restarted.
                *(j--) = *(--end);
            }
        }
    }

    end = std::remove_if(found_segments.begin(), end, [](const simd::double4 &segment) {
        return simd::distance_squared(segment.lo, segment.hi) < 25.0;
    });

    found_segments.erase(end, found_segments.end());

    return found_segments;
}

extern "C" CFArrayRef CreateSegmentsFromImage(const vImage_Buffer *buffer, uint8_t grayThreshold, double significance, unsigned channelWidth, CFErrorRef *errorPtr) noexcept {
    try {
        auto segments = find_segments_in_image(buffer, grayThreshold, significance, channelWidth, 4);

        CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

        for (auto segment : segments) {
            auto a = cf::make_array(cf::make_number(segment.s0), cf::make_number(segment.s1), cf::make_number(segment.s2), cf::make_number(segment.s3));
            CFArrayAppendValue(result, a.get());
        }

        return result;
    }
    catch (std::system_error &ex) {
        if (errorPtr) *errorPtr = cf::make_error_from_exception(ex).release();
        return NULL;
    }
    catch (std::exception &ex) {
        if (errorPtr) *errorPtr = cf::make_error_from_exception(ex).release();
        return NULL;
    }
    catch (...) {
        if (errorPtr) *errorPtr = cf::make_error_from_exception().release();
        return NULL;
    }
}

