_download_and_extract_tar "$ZSTD_URL" "$ZSTD_DIR/build" "$ZSTD_SHA256"
_pushd "$ZSTD_DIR/build"

set -x
CFLAGS="$CFLAGS" \
make -C lib -j$NCPU DESTDIR="$ZSTD_DIR" BUILD_DIR="$PWD" PREFIX=/ \
  install-static install-includes install-pc

_popd
$NO_CLEANUP || rm -rf "$ZSTD_DIR/build"
