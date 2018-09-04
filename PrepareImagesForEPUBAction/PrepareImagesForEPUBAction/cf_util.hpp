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
 * @macro CHECK_CF_TYPE(Reference, Type)
 * @param Reference The reference to check.
 * @param Type The CoreFoundation base type (e.g., CFArray, CFDictionary).
 * @throw std::bad_cast If the reference is not of the given type and
 *   DEBUG is defined to be true.
 */
#if DEBUG
#define CHECK_CF_TYPE(Reference,Type) if (CFGetTypeID(Reference) != Type##GetTypeID()) throw std::bad_cast { }
#else
#define CHECK_CF_TYPE(Reference,Type)
#endif

/*!
 * @abstract Utilities to bridge between C++ and CoreFoundation.
 */
namespace cf {
    struct __cf_deleter {
        template <typename Ref> void operator ()(Ref ref) const {
            CFRelease(ref);
        }
    };

    template <typename Ref> using managed = std::unique_ptr<std::remove_pointer_t<Ref>, __cf_deleter>;

    /*!
     * @abstract Wrap a CoreFoundation type in an RAII-managed object.
     * @discussion When the @c managed object is destroyed, the
     *   underlying CoreFoundation object is released by @c
     *   __cf_deleter above.  CoreFoundation objects returned by the
     *   get-rule should be retained before passing them to this
     *   function.
     */
    template <typename Ref> static inline managed<Ref> make_managed(Ref ref CF_RELEASES_ARGUMENT) {
        return managed<Ref> { ref };
    }

    /*!
     * @abstract Assorted CoreFoundation constants associated with a type.
     * @discussion Many CoreFoundation functions require parameters
     *   that specify the type of the pointer being passed into the
     *   function.  This struct allows compile-time lookup of these
     *   values.
     */
    template <typename Ref> struct cf_typeinfo;

    template <> struct cf_typeinfo<SInt8> {
        static constexpr bool is_number = true;
        static constexpr CFNumberType num_type = kCFNumberSInt8Type;
    };

    template <> struct cf_typeinfo<SInt16> {
        static constexpr bool is_number = true;
        static constexpr CFNumberType num_type = kCFNumberSInt16Type;
    };

    template <> struct cf_typeinfo<SInt32> {
        static constexpr bool is_number = true;
        static constexpr CFNumberType num_type = kCFNumberSInt32Type;
    };

    template <> struct cf_typeinfo<SInt64> {
        static constexpr bool is_number = true;
        static constexpr CFNumberType num_type = kCFNumberSInt64Type;
    };

    template <> struct cf_typeinfo<Float32> {
        static constexpr bool is_number = true;
        static constexpr CFNumberType num_type = kCFNumberFloat32Type;
    };

    template <> struct cf_typeinfo<Float64> {
        static constexpr bool is_number = true;
        static constexpr CFNumberType num_type = kCFNumberFloat64Type;
    };

    static inline managed<CFStringRef> string(const char *s) {
        return make_managed(CFStringCreateWithCString(kCFAllocatorDefault, s, kCFStringEncodingUTF8));
    }

    static inline managed<CFStringRef> string(const std::string &s) {
        return make_managed(CFStringCreateWithBytes(kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(s.c_str()), s.size(), kCFStringEncodingUTF8, false));
    }

    static inline std::string get(CFStringRef string) {
        CHECK_CF_TYPE(string, CFString);

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
     * @abstract Convert a primitive number into a managed
     *   CoreFoundation number.
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
     * @throw allow_lossy If @c false, throw an exception if the
     *   number cannot be converted into the requested type without
     *   loss.
     * @return The value contained by the CoreFoundation number.
     * @throw std::bad_cast If the number cannot be converted into the requested type without loss.
     */
    template <typename Number> static inline Number get(CFNumberRef number, bool allow_lossy = true) {
        CHECK_CF_TYPE(number, CFNumber);

        Number result;

        bool success = CFNumberGetValue(number, cf_typeinfo<Number>::num_type, &result);
        if (!allow_lossy && !success) throw std::bad_cast{};

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

    /*!
     * @abstract Create a managed array of managed core foundation objects.
     * @discussion The arguments to this function will be retained.
     * @param args The managed CoreFoundation objects.
     * @return A managed CFArray object.
     */
    template <typename... Args> static inline managed<CFArrayRef> array(Args &&... args) {
        const void *values[] = { std::forward<Args>(args).get()... };
        return make_managed(CFArrayCreate(kCFAllocatorDefault, values, sizeof...(Args), &kCFTypeArrayCallBacks));
    }

    /*!
     * @abstract Call the given function for each element in a
     *   CoreFoundation array.
     * @discussion The single argument of the function should be a
     *   CoreFoundation referece.  Since all CoreFoundation references
     *   are interchangable, it is up to the caller to ensure that the
     *   argument type is correct.
     * @param array The CoreFoundation array.
     * @param function The function to apply to the elements.
     * @see CHECK_CF_TYPE
     */
    template <typename Function> void apply(CFArrayRef array, Function function) {
        CHECK_CF_TYPE(array, CFArray);

        CFArrayApplierFunction applier = [] (const void *value, void *context) {
            Function *fcn = reinterpret_cast<Function *>(context);
            (*fcn)(value);
        };

        CFArrayApplyFunction(array, CFRangeMake(0, CFArrayGetCount(array)), applier, &function);
    }

    /*!
     * @abstract Call the given function for each entry in a
     *   CoreFoundation dictionary.
     * @discussion The arguments of the function should be
     *   CoreFoundation refereces: the key and the value.  Since all
     *   CoreFoundation references are interchangable, it is up to the
     *   caller to ensure that the argument type is correct.
     * @param dictionary The CoreFoundation array.
     * @param function The function to apply to the entries.
     * @see CHECK_CF_TYPE
     */
    template <typename Function> void apply(CFDictionaryRef dictionary, Function function) {
        CHECK_CF_TYPE(dictionary, CFDictionary);

        CFDictionaryApplierFunction applier = [] (const void *key, const void *value, void *context) {
            Function *fcn = reinterpret_cast<Function *>(context);
            (*fcn)(key, value);
        };

        CFDictionaryApplyFunction(dictionary, applier, &function);
    }

    static inline CFTypeRef _get(CFDictionaryRef dictionary, CFTypeRef key) {
        CHECK_CF_TYPE(dictionary, CFDictionary);

        CFTypeRef value;
        if (!CFDictionaryGetValueIfPresent(dictionary, key, &value)) {
            auto description = managed<CFStringRef> { CFCopyDescription(key) };
            throw std::out_of_range { "No dictionary parameter " + get(description.get()) };
        }
        return value;
    }

    /*!
     * @abstract Return a value from a dictionary given its key.
     * @tparam T The type to return.
     * @param dictionary The dictionary.
     * @param key The key.
     * @return A value of type T.
     * @throw std::out_of_range If the key does not exist in the dictionary.
     */
    template <typename T> static inline std::enable_if_t<cf_typeinfo<T>::is_number, T> get(CFDictionaryRef dictionary, CFTypeRef key) {
        return get<T>(static_cast<CFNumberRef>(_get(dictionary, key)));
    }

    /*!
     * @discussion Use this function for exceptions that are
     *   subclasses of @c std::exception.
     */
    static inline CFErrorRef error(const std::exception &ex, CFStringRef domain = CFSTR("GeneralErrorDomain"), CFIndex code = 0) {
        auto what = cf::string(ex.what());

        CFTypeRef keys[] = { kCFErrorLocalizedFailureReasonKey };
        CFTypeRef vals[] = { what.get() };

        return CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, domain, code, keys, vals, 1);
    }

    /*!
     * @discussion Use this function for exceptions that are not
     *   subclasses of @c std::exception.
     */
    static inline CFErrorRef error() {
        CFTypeRef keys[] = { kCFErrorLocalizedFailureReasonKey };
        CFTypeRef vals[] = { CFSTR("An unknown internal error has occurred.") };

        return CFErrorCreateWithUserInfoKeysAndValues(kCFAllocatorDefault, CFSTR("GeneralErrorDomain"), 0, keys, vals, 1);
    }

    /*!
     * @discussion Use this function for exceptions that are
     *   subclasses of @c std::system_error.  It will use the POSIX
     *   error domain and POSIX error number.
     */
    static inline CFErrorRef system_error(const std::system_error &ex) {
        return error(ex, kCFErrorDomainPOSIX, ex.code().value());
    }
}

#endif /* cf_util_hpp */
