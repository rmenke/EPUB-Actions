//
//  cf_util.hpp
//  PrepareImagesForEPUBAction
//
//  Created by Rob Menke on 7/11/18.
//  Copyright © 2018 Rob Menke. All rights reserved.
//

#ifndef cf_util_hpp
#define cf_util_hpp

#include <CoreFoundation/CoreFoundation.h>

#include <memory>
#include <stdexcept>
#include <string>
#include <system_error>

/*!
 * @abstract Utilities to bridge between C++ and CoreFoundation.
 */
namespace cf {
#if DEBUG
#define CHECK_CF_TYPE(R,T) if (CFGetTypeID(R) != T##GetTypeID()) throw std::bad_cast { }
#else
#define CHECK_CF_TYPE(R,T)
#endif

    struct __cf_deleter {
        template <typename Ref> void operator ()(Ref ref) const {
            CFRelease(ref);
        }
    };

    template <typename Ref> using managed = std::unique_ptr<std::remove_pointer_t<Ref>, __cf_deleter>;

    /*!
     * @abstract Wrap a CoreFoundation type in an RAII-managed object.
     * @discussion When the @c managed object is destroyed, the underlying CoreFoundation object is released by @c __cf_deleter above.  CoreFoundation objects returned by the get-rule should be retained before passing them to this function.
     */
    template <typename Ref> static inline managed<Ref> make_managed(Ref ref CF_RELEASES_ARGUMENT) {
        return managed<Ref> { ref };
    }

    /*!
     * @abstract Assorted CoreFoundation constants associated with a type.
     * @discussion Many CoreFoundation functions require parameters that specify the type of the pointer being passed into the function.  This struct allows compile-time lookup of these values.
     */
    template <typename Ref> struct cf_typeinfo;

    template <> struct cf_typeinfo<short> {
        static constexpr CFNumberType num_type = kCFNumberShortType;
    };

    template <> struct cf_typeinfo<int> {
        static constexpr CFNumberType num_type = kCFNumberIntType;
    };

    template <> struct cf_typeinfo<long> {
        static constexpr CFNumberType num_type = kCFNumberLongType;
    };

    template <> struct cf_typeinfo<float> {
        static constexpr CFNumberType num_type = kCFNumberFloatType;
    };

    template <> struct cf_typeinfo<double> {
        static constexpr CFNumberType num_type = kCFNumberDoubleType;
    };

    static inline managed<CFStringRef> string(const char *s) {
        return make_managed(CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8));
    }

    static inline managed<CFStringRef> string(const std::string &s) {
        return make_managed(CFStringCreateWithBytes(kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(s.c_str()), s.size(), kCFStringEncodingUTF8, false));
    }

    static inline std::string get(CFStringRef string) {
        CFRange range = CFRangeMake(0, CFStringGetLength(string));
        CFIndex size;

        // Get the size of the buffer
        CFStringGetBytes(string, range, kCFStringEncodingUTF8, 0, false, NULL, 0, &size);

        std::string result;
        result.resize(size);

        CFStringGetBytes(string, range, kCFStringEncodingUTF8, 0, false, (UInt8 *)(result.c_str()), result.size(), &size);

        return result;
    }

    /*!
     * @abstract Convert a primitive number into a managed CoreFoundation number.
     * @param n The number to wrap.
     * @return A managed pointer to a CoreFoundation number.
     */
    template <typename Number> static inline managed<CFNumberRef> number(const Number &n) {
        return make_managed(CFNumberCreate(kCFAllocatorDefault, cf_typeinfo<Number>::num_type, &n));
    }

    /*!
     * @abstract Convert a CoreFoundation number to a primitive number.
     * @discussion Uses @c CFNumberGetValue to extract the primitive value.
     * @param number The number to unwrap.
     * @return The value contained by the CoreFoundation number.
     */
    template <typename Number> static inline Number get(CFNumberRef number) {
        CHECK_CF_TYPE(number, CFNumber);

        Number result;
        CFNumberGetValue(number, cf_typeinfo<Number>::num_type, &result);
        return result;
    }

    /*!
     * @abstract Convert a managed CoreFoundation number to a primitive number.
     * @discussion Uses @c CFNumberGetValue to extract the primitive value.
     * @param number The number to unwrap as a managed pointer.
     * @return The value contained by the CoreFoundation number.
     */
    template <typename Number> static inline Number get(const managed<CFNumberRef> &number) {
        return get<Number>(number.get());
    }

    template <typename... Args> static inline managed<CFArrayRef> array(Args &&... args) {
        const void *values[] = { std::forward<Args>(args).get()... };
        return make_managed(CFArrayCreate(kCFAllocatorDefault, values, sizeof...(Args), &kCFTypeArrayCallBacks));
    }

    template <typename Function> void apply(CFArrayRef array, Function function) {
        CHECK_CF_TYPE(array, CFArray);

        CFArrayApplierFunction applier = [] (const void *value, void *context) {
            Function *fcn = reinterpret_cast<Function *>(context);
            (*fcn)(value);
        };

        CFArrayApplyFunction(array, CFRangeMake(0, CFArrayGetCount(array)), applier, &function);
    }

    template <typename Function> void apply(CFDictionaryRef dictionary, Function function) {
        CHECK_CF_TYPE(dictionary, CFDictionary);

        CFDictionaryApplierFunction applier = [] (const void *key, const void *value, void *context) {
            Function *fcn = reinterpret_cast<Function *>(context);
            (*fcn)(key, value);
        };

        CFDictionaryApplyFunction(dictionary, applier, &function);
    }

    static inline CFTypeRef _get(CFDictionaryRef dictionary, CFStringRef key) {
        CHECK_CF_TYPE(dictionary, CFDictionary);
        CHECK_CF_TYPE(key, CFString);

        CFTypeRef value;
        if (!CFDictionaryGetValueIfPresent(dictionary, key, &value)) {
            throw std::out_of_range { "No dictionary parameter " + get(key) };
        }
        return value;
    }

    template <typename T> static inline T get(CFDictionaryRef dictionary, CFStringRef key);

    template <> inline double get<double>(CFDictionaryRef dictionary, CFStringRef key) {
        return get<double>(static_cast<CFNumberRef>(_get(dictionary, key)));
    }
    template <> inline short get<short>(CFDictionaryRef dictionary, CFStringRef key) {
        return get<short>(static_cast<CFNumberRef>(_get(dictionary, key)));
    }
    template <> inline int get<int>(CFDictionaryRef dictionary, CFStringRef key) {
        return get<int>(static_cast<CFNumberRef>(_get(dictionary, key)));
    }

    /*!
     * @discussion Use this function for exceptions that are subclasses of @c std::exception.
     */
    static inline CFErrorRef error(const std::exception &ex, CFStringRef domain = CFSTR("GeneralErrorDomain"), CFIndex code = 0) {
        auto what = cf::string(ex.what());

        CFTypeRef keys[] = { kCFErrorLocalizedFailureReasonKey };
        CFTypeRef vals[] = { what.get() };

        return CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, domain, code, keys, vals, 1);
    }

    /*!
     * @discussion Use this function for exceptions that are not subclasses of @c std::exception.
     */
    static inline CFErrorRef error() {
        CFTypeRef keys[] = { kCFErrorLocalizedFailureReasonKey };
        CFTypeRef vals[] = { CFSTR("An unknown internal error has occurred.") };

        return CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, CFSTR("GeneralErrorDomain"), 0, keys, vals, 1);
    }

    /*!
     * @discussion Use this function for exceptions that are subclasses of @c std::system_error.
     *   It will use the POSIX error domain and POSIX error number.
     */
    static inline CFErrorRef system_error(const std::system_error &ex) {
        return error(ex, kCFErrorDomainPOSIX, ex.code().value());
    }
}

#endif /* cf_util_hpp */
