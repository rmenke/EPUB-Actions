//
//  ConvertMarkupToEPUBNavigationAction.h
//  ConvertMarkupToEPUBNavigationAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import Automator.AMBundleAction;

NS_ASSUME_NONNULL_BEGIN

@interface ConvertMarkupToEPUBNavigationAction : AMBundleAction

/*!
 * @abstract Process an individual page of an EPUB folder.
 *
 * @param page A file wrapper holding an individual page.
 * @param chapter The name of the chapter to which this page belongs.
 * @param regions A mutable array to collect the region links for the
 *   @c data-nav.xhtml document.
 * @param error If there is an error processing the page, upon return
 *   contains an @c NSError object that describes the problem.
 *
 * @return The replacement data for the page, or @c nil if an error
 *   occurred.
 */
- (nullable NSData *)processPage:(NSFileWrapper *)page chapter:(NSString *)chapter updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError **)error;

/*!
 * @abstract Process a chapter of an EPUB folder.
 *
 * @param chapter A file wrapper holding an individual chapter.
 * @param regions A mutable array to collect the region links for the
 *   @c data-nav.xhtml document.
 * @param error If there is an error processing the chapter, upon
 *   return contains an @c NSError object that describes the problem.
 *
 * @return @c YES on success; @c NO if an error occurred.
 */
- (BOOL)processChapter:(NSFileWrapper *)chapter updating:(NSMutableArray<NSXMLElement *> *)regions error:(NSError **)error;

/*!
 * @abstract Process an EPUB folder.
 *
 * @param url The URL of the EPUB folder.
 * @param error If there is an error processing the EPUB, upon return
 *   contains an @c NSError object that describes the problem.
 *
 * @return @c YES on success; @c NO if an error occurred.
 */
- (BOOL)processFolder:(NSURL *)url error:(NSError **)error;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
