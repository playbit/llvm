_download_and_extract_tar "$LIBEDIT_URL" "$LIBEDIT_DIR-build" "$LIBEDIT_SHA256"
_pushd "$LIBEDIT_DIR-build"

CFLAGS="$CFLAGS -I$NCURSES_DIR/include -I$NCURSES_DIR/include/ncursesw"
if [[ $TARGET != *macos ]]; then
  # build fails when __STDC_ISO_10646__ is not defined, which is the case with musl.
  #   error: #error wchar_t must store ISO 10646 characters
  # musl is ISO 10646 compliant so define it ourselves.
  CFLAGS="$CFLAGS -D__STDC_ISO_10646__=201103L"
fi
LDFLAGS="$LDFLAGS -L$NCURSES_DIR/lib"

echo "configure > configure.out"
CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS \
./configure \
  --host=$HOST_TRIPLE \
  --build=$(_clang_triple $TARGET) \
  --prefix= \
  --disable-dependency-tracking \
  --enable-static \
  --disable-shared \
  --disable-examples \
  > configure.out

echo "make > make.out"
make -j$NCPU V=0 > make.out

echo "make install > make-install.out"
rm -rf "$LIBEDIT_DIR"
mkdir -p "$LIBEDIT_DIR"
make DESTDIR="$LIBEDIT_DIR" install > make-install.out

_popd
$NO_CLEANUP || rm -rf "$LIBEDIT_DIR-build"
