# Note: this addresses CVE-2024-3094
_download_and_extract_tar "$XZ_URL" "$XZ_DIR-build" "$XZ_SHA256"
_pushd "$XZ_DIR-build"

# yes, sadly we have to deal with autoconf because CVE-2024-3094
if ! command -v autoreconf >/dev/null; then
  echo "autoreconf not found in PATH" >&2
  case $HOST_SYS in
    macos) echo "Try: brew install autoconf" >&2;;
    linux) echo "Try: apk add autoconf" >&2;;
  esac
  exit 1
fi

echo "autoreconf > autoreconf.out"
autoreconf -fi > autoreconf.out

echo "configure > configure.out"
CFLAGS="$CFLAGS" \
LDFLAGS=$LDFLAGS \
./configure \
  --host=$HOST_TRIPLE \
  --build=$(_clang_triple $TARGET) \
  --prefix= \
  --disable-dependency-tracking \
  --enable-static \
  --disable-shared \
  --disable-microlzma \
  --disable-lzip-decoder \
  --disable-xz \
  --disable-xzdec \
  --disable-lzmadec \
  --disable-lzmainfo \
  --disable-lzma-links \
  --disable-scripts \
  --disable-doc \
  --disable-nls \
  --disable-rpath \
  --disable-werror \
  > configure.out

echo "make > make.out"
make -j$NCPU V=0 > make.out

echo "make install > make-install.out"
rm -rf "$XZ_DIR"
mkdir -p "$XZ_DIR"
make DESTDIR="$XZ_DIR" install > make-install.out

_popd
$NO_CLEANUP || rm -rf "$XZ_DIR-build"
