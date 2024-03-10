_download_and_extract_tar "$ZSTD_URL" "$ZSTD_DIR/build" "$ZSTD_SHA256"
_pushd "$ZSTD_DIR/build"

CFLAGS="$CFLAGS -O2" \
make -C lib -j$NCPU DESTDIR="$ZSTD_DIR" PREFIX=/ \
  install-static install-includes install-pc

_popd
$NO_CLEANUP || rm -rf "$ZSTD_DIR/build"
