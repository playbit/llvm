_download_and_extract_tar "$ZLIB_URL" "$ZLIB_DIR/build" "$ZLIB_SHA256"
_pushd "$ZLIB_DIR/build"
for f in $(echo "$ZLIB_PATCHDIR"/*.patch | sort); do
  patch -p1 < "$f"
done

CFLAGS="$CFLAGS -O2 -Wno-macro-redefined" \
./configure --static --prefix=

# make
# make -j$NCPU
make -j$NCPU DESTDIR="$ZLIB_DIR" install

_popd
rm -rf "$ZLIB_DIR/build"
