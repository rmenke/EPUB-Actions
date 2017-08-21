#!/bin/bash

# Created by Rob Menke on 8/19/17.
# Copyright © 2017 Rob Menke. All rights reserved.

export PATH=/bin:/usr/bin:/sbin:/usr/sbin

set -e  # Exit on any error

if ((compressImages)); then
    IMG_SUFFIXES=''
else
    IMG_SUFFIXES='.jpe:.jpeg:.jpg:.tif:.tiff:.png:.gif:.bmp:.svg:.svgz'
fi

while read INPUT; do
    OUTPUT="$(/usr/bin/mktemp "${INPUT}.XXXXXXXX")"

    cd "${INPUT}"

    # The 'mimetype' file MUST be first and MUST NOT be compressed.
    # We cannot use ${OUTPUT} directly because zip will view an empty
    # file as a corrupt archive.
    /usr/bin/zip -0Xq - 'mimetype' >|"${OUTPUT}"

    /usr/bin/find * -type f ! -path 'mimetype' |
        /usr/bin/zip "-${compression}" -n "${IMG_SUFFIXES}" -Xq "${OUTPUT}" -@

    cd /

    /bin/rm -rf "${INPUT}"
    /bin/mv "${OUTPUT}" "${INPUT}"

    echo "${INPUT}"
done
