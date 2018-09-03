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

const char * const EPUB_REGION_XATTR = "com_the-wabe_regions";

@interface ImagesToEPUBAction : AMBundleAction

typedef NS_ENUM(NSUInteger, PageLayoutStyle) {
    maximizeInternalSpace = 0,
    distributeInternalSpace = 1,
    minimizeInternalSpace = 2
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
 * @abstract Load all of the XML templates required.
 *
 * @description This creates XML documents that are updated
 *   continuously throughout the workflow.
 *
 * @param url The destination URL.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @throw NSException if any of the templates are missing or damaged.
 */
- (NSURL *)prepareDestinationDirectoryForURL:(NSURL *)url error:(NSError **)error;

/*!
 * @abstract Partition the image files into a dictionary keyed by
 *  chapter directory name.
 *
 * @description The enclosing folder of the image file is used to name
 *   the chapter.  If the images are out-of-order, multiple chapters
 *   may be created with the same preferred name.  Each image will be
 *   renamed according to its order in the input.  If during copying,
 *   it is found that an image does not match its path extension, the
 *   path extension will be updated.  (This keeps certain EPUB
 *   validators happy, even though the type of the image is formally
 *   specified in the container file.)
 *
 * Each chapter encoutered will have its preferred name added to the
 *   navigation document/table of contents.  While the chapter
 *   directory has a unique name, the chapters themselves may not.
 *
 * @param paths A list of absolute paths to images.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns A mapping from chapter directory names to image names.
 */
- (NSDictionary<NSString *, NSArray<Frame *> *> *)createChaptersFromPaths:(NSArray<NSString *> *)paths error:(NSError **)error;

/*!
 * @abstract Create a single page from an array of image frames.
 *
 * @param path The path to the page relative to the content directory.
 * @param frames An array of dictionaries describing the frames.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns @c YES on success; @c NO if an error occurred.
 */
- (BOOL)createPage:(NSString *)path fromFrames:(NSArray<Frame *> *)frames error:(NSError **)error;

/*!
 * @abstract Create the pages for the chapters.
 *
 * @discussion This method assumes that each chapter wrapper contains
 *   the images used for page layout
 *
 * @param chapters A dictionary of arrays of Frame objects
 *   representing chapters.
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns @c YES on success; @c NO if an error occurred.
 */
- (BOOL)createPagesForChapters:(NSDictionary<NSString *, NSArray<Frame *> *> *)chapters error:(NSError **)error;

/*!
 * @abstract Create the metadata files in the EPUB wrapper.
 *
 * @discussion Updates the title, authors, and other identifiers in
 *   the package file, then writes the package file, the table of
 *   contents, and the region-based navigation file to the “Contents”
 *   subdirectory of the output folder.
 *
 * @param error If there is an error generating the data, upon return
 *   contains an NSError object that describes the problem.
 *
 * @returns @c YES on success; @c NO if an error occurred.
 */
- (BOOL)writeMetadataFilesAndReturnError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
