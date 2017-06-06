//
//  ImagesToEPUBAction.h
//  ImagesToEPUBAction
//
//  Created by Rob Menke on 1/4/17.
//  Copyright © 2017 Rob Menke. All rights reserved.
//

@import Automator.AMBundleAction;
@import AppKit.NSColor;

@class Frame;

NS_ASSUME_NONNULL_BEGIN

@interface ImagesToEPUBAction : AMBundleAction

typedef NS_ENUM(NSUInteger, PageLayoutStyle) {
    maximizeInternalSpace = 0, distributeInternalSpace = 1, minimizeInternalSpace = 2
};

@property (nonatomic, readonly) NSString *outputFolder;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSString *authors;
@property (nonatomic, readonly) NSString *publicationID;
@property (nonatomic, readonly) NSUInteger pageWidth, pageHeight, pageMargin;
@property (nonatomic, readonly) BOOL disableUpscaling;
@property (nonatomic, readonly) NSColor *backgroundColor;
@property (nonatomic, readonly) enum PageLayoutStyle layoutStyle;
@property (nonatomic, readonly) BOOL doPanelAnalysis;
@property (nonatomic, readonly) BOOL firstIsCover;

@property (nonatomic, readonly) NSURL *outputURL;

/*!
 * @abstract Separate the image files into an array of chapter directories.
 *
 * @description The enclosing folder of the image file is used to name
 *   the chapter. If the images are out-of-order, multiple chapters
 *   may be created with the same preferred name. Each image will be
 *   renamed according to its order in the input.
 *
 * @param paths A list of absolute paths to images.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns An array of @c NSFileWrapper objects representing the
 *   chapters created.
 */
- (nullable NSArray<NSFileWrapper *> *)createChaptersFromPaths:(NSArray<NSString *> *)paths error:(NSError **)error;

/*!
 * @abstract Create the pages for the chapters.
 *
 * @discussion This method assumes that each chapter wrapper contains
 *   the images used for page layout. If during analysis, it is found
 *   that an image does not match its path extension, the path
 *   extension will be renamed. (This keeps certain ePub validators
 *   happy, even though the type of the image is formally specified in
 *   the container file.)
 *
 * @param chapters An array of @c NSFileWrapper objects representing chapters.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns An array of paths to the pages generated, in order. The
 *   paths are relative to the enclosing folder of the chapter; that
 *   is, they contain the name of the @c NSFileWrapper containing the
 *   page.
 */
- (nullable NSArray<NSString *> *)createPagesForChapters:(NSArray<NSFileWrapper *> *)chapters error:(NSError **)error;

/*!
 * @abstract Create a single page from a set of image frames.

 * @param page An array of dictionaries describing the frames.
 * @param number The number of the page.
 * @param directory Where to write the page file.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns The relative path of the generated page, or @c nil if an
 *   error occurred.
 */
- (nullable NSString *)createPage:(NSArray<Frame *> *)page number:(NSUInteger)number inDirectory:(NSFileWrapper *)directory error:(NSError **)error;

/*!
 * @abstract Create the metadata files in the ePub wrapper.
 *
 * @discussion Aside from the title, authors, and other identifiers,
 *   the main component of the package file is the manifest, which
 *   lists the files in the container, and the spine, which lists the
 *   order in which pages are read. The manifest template already has
 *   entries for the metadata files themselves, so the only thing
 *   missing is the images copied and the pages generated.
 *
 * @param directory The root directory of the container.
 * @param chapters An array of directory wrappers representing the
 *   chapters.
 * @param spineItems An array of path strings to the pages, in the
 *   order that they should be read.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns @c YES on success.
 */
- (BOOL)addMetadataToDirectory:(NSFileWrapper *)directory chapters:(NSArray<NSFileWrapper *> *)chapters spineItems:(NSArray<NSString *> *)spineItems error:(NSError **)error;

- (nullable id)runWithInput:(nullable id)input error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
