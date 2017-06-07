# Automator Actions for EPUB Creation

Automator actions for creating EPUB comic books with panel navigation, compliant with [EPUB 3.0](http://www.idpf.org/epub/30/spec/epub30-overview.html) and [EPUB Region-Based Navigation 1.0](http://www.idpf.org/epub/renditions/region-nav/). These actions are two stages in a workflow that converts a set of comic strips (in EPUB parlance, *panel-groups*) into a fully navigable EPUB folder which may be optionally compressed into an EPUB container (document).

### Installation instructions:

```sh
xcodebuild -workspace 'EPUB Actions.xcworkspace' -scheme 'EPUB Actions' install DSTROOT=/
```

## Images to EPUB

Converts a series of images to pages in a fixed-layout EPUB document. Panel groups and individual panels are labelled using `<div>` elements which are visible in the final product and can be adjusted using a text editor.

Metadata for the EPUB package (title, author, *et cetera*) is supplied by the controls of the action. The user should supply a publication ID once and be consistent across editions. If it is not supplied, the action will generate a UUID-based URN and issue a warning. (To generate one beforehand, execute <code>echo urn:uuid:\`uuidgen\`</code> in the shell and paste the result into the Publication ID field.)

## Convert Markup to EPUB Navigation

Searches the content files of the EPUB folder for `<div>` elements of class `panel-group` or `panel` and builds a region-based navigation file from what it finds. The `<div>` elements are removed from the content files.

The location and size of the `<div>` elements are specified by inline style attributes, and the coordinates are specified as percentages of the page size.

The action supplies no controls.

## Creating Automator Workflows

The action `Images to EPUB` takes files as input and outputs a single path. The action `Convert Markup to EPUB Navigation` does its work in-place. The generated EPUB document will be in uncompressed folder format (org.idpf.epub-folder). To create an EPUB container file (org.idpf.epub-container) which most eBook readers expect, add the following bash script (via `Do Shell Script`) as the **final** step of your workflow:

```bash
set -e                                   # Exit on error

BASE="${1%.epub}"

/bin/rm -rf "$BASE"                      # Remove old build folder (if any)
/bin/mv "$1" "$BASE"                     # Remove suffix

cd "$BASE"                               # Paths must be relative to the archive root

ZIPOPT="-mqTX"; export ZIPOPT            # Move files, quiet, check integrity, no metadata

/usr/bin/zip -0 "$1" "mimetype"          # Must be first with no compression
/usr/bin/zip -r "$1" "META-INF"          # Container information
/usr/bin/zip -r "$1" "Content"           # The images and pages

cd /

/bin/rmdir "$BASE"                       # Should be empty

echo "$1"
```
