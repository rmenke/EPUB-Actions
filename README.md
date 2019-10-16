# Automator Actions for EPUB Creation

Automator actions for creating EPUB comic books with panel navigation, compliant with [EPUB 3.0](http://www.idpf.org/epub/30/spec/epub30-overview.html) and [EPUB Region-Based Navigation 1.0](http://www.idpf.org/epub/renditions/region-nav/).

These actions are three stages in a workflow that converts a set of comic strips (in EPUB parlance, *panel-groups*) into a navigable EPUB archive.

### Installation instructions:

```sh
xcodebuild -workspace 'EPUB Actions.xcworkspace' \
    -scheme 'EPUB Actions' install DSTROOT=/
```

## Prepare Images for EPUB

Examine the images for panels.  Panels are defined as the edges where the background matting of the image ends.  The bounds of each found panel is stored as a binary property list in the extended file attribute `com.the-wabe.regions` of the image.  This step is optional but helps with reading on small-screen devices.

## Images to EPUB

Converts a series of images to pages in a fixed-layout EPUB document.  Each image is stored as a panel-group element in the navigation document, and if region information is attached via an extended attribute, panel elements are generated as well.

Metadata for the EPUB package (title, author, *et cetera*) is supplied by the controls of the action.  The user should supply a publication ID once and be consistent across editions.  If it is not supplied, the action will issue an error.  (To generate one beforehand, execute <code>echo urn:uuid:\`uuidgen\`</code> in the shell and paste the result into the Publication ID field.)

## Bundle XHTML as EPUB

Takes a collection of XHTML and media files (including CSS) and bundles the result into an EPUB document.  The table of contents will be generated from the `<title/>` elements of the XHTML files, in the order which they are supplied to the action.

## Convert EPUB Folder to EPUB Container

The actions `Images to EPUB` and `Bundle XHTML as EPUB` take files as input and output a single path to the document.  The generated EPUB document will be in uncompressed folder format (`org.idpf.epub-folder`).  To create an EPUB container file (`org.idpf.epub-container`) which most eBook readers expect, use this action to create a ZIP archive that follows EPUB conventions about the order of files within the archive.
