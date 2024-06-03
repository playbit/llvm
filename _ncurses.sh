# because ncurses build is broken for cross compilation (--with-build-cc= is not used
# to build progs/tic which is needed by install), we first have to build ncurses for
# the host.

NCURSES_HOST=$BUILD_DIR_S1/ncurses
if [ ! -f "$NCURSES_HOST/progs/tic" ]; then
  _download_and_extract_tar "$NCURSES_URL" "$NCURSES_HOST" "$NCURSES_SHA256"
  _pushd "$NCURSES_HOST"

  echo "CC $HOST_CC"
  echo "LD $HOST_CC"
  echo "CPP $HOST_CC"
  echo "CFLAGS $HOST_CFLAGS"
  echo "LDFLAGS $HOST_LDFLAGS"

  echo "configure > configure.out"
  CC="$HOST_CC" \
  LD="$HOST_CC" \
  CFLAGS="$HOST_CFLAGS" \
  CPPFLAGS="$HOST_CPPFLAGS" \
  LDFLAGS="$HOST_LDFLAGS" \
  ./configure \
    --prefix= \
    --datarootdir=/usr/share \
    --without-ada \
    --without-tests \
    --disable-termcap \
    --disable-root-access \
    --disable-rpath-hack \
    --disable-setuid-environ \
    --disable-stripping \
    --without-cxx-binding \
    --without-shared \
    --with-terminfo-dirs="/etc/terminfo:/usr/share/terminfo" \
    --enable-widec \
    --without-manpages \
    > configure.out

  echo "make > make.out"
  make -j$NCPU V=0 > make.out

  _popd
fi

# set PATH so that misc/run_tic.sh runs the correct 'tic' program during installation
export PATH=$NCURSES_HOST/progs:$PATH

_download_and_extract_tar "$NCURSES_URL" "$NCURSES_DIR-build" "$NCURSES_SHA256"
_pushd "$NCURSES_DIR-build"

echo "configure > configure.out"
CFLAGS="$CFLAGS" \
./configure \
  --host=$HOST_TRIPLE \
  --build=$(_clang_triple $TARGET) \
  --with-build-cc="$HOST_CC" \
  --with-build-cflags="$HOST_CFLAGS" \
  --with-build-cppflags="$HOST_CFLAGS" \
  --with-build-ldflags="$HOST_LDFLAGS" \
  --prefix= \
  --datarootdir=/usr/share \
  --without-ada \
  --without-tests \
  --disable-termcap \
  --disable-root-access \
  --disable-rpath-hack \
  --disable-setuid-environ \
  --disable-stripping \
  --without-cxx-binding \
  --without-shared \
  --with-terminfo-dirs="/etc/terminfo:/usr/share/terminfo" \
  --enable-widec \
  --without-manpages \
  > configure.out

echo "make > make.out"
make -j$NCPU V=0 > make.out

echo "make install > make-install.out"
rm -rf "$NCURSES_DIR"
mkdir -p "$NCURSES_DIR"
make DESTDIR="$NCURSES_DIR" install > make-install.out

if [ ! -e "$NCURSES_DIR/lib/libncurses.a" ]; then
  _symlink "$NCURSES_DIR/lib/libncurses.a" libncursesw.a
fi

rm -rf "$NCURSES_DIR"/lib/*_g.a

_popd
$NO_CLEANUP || rm -rf "$NCURSES_DIR-build"
