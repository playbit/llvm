MUSL_BUILD_DIR=$BUILD_DIR/musl-$MUSL_VERSION

_download_and_extract_tar \
  "$MUSL_URL" "$MUSL_BUILD_DIR" "$MUSL_SHA256" \
  "$DOWNLOAD_DIR/musl-$MUSL_VERSION.tar.gz"

_pushd "$MUSL_BUILD_DIR"

for f in $(echo "$MUSL_PATCHDIR"/*.patch | sort); do
  patch -p1 < "$f"
done

ENABLE_EXECINFO=false
CC_TRIPLE=$(_clang_triple $TARGET)

./configure \
  --target=$CC_TRIPLE \
  --build=$HOST_TRIPLE \
  --prefix="" \
  --sysconfdir=/etc \
  --bindir=/bin \
  --libdir=/lib \
  --syslibdir=/lib \
  --includedir=/usr/include \
  --mandir=/share/man \
  --infodir=/share/info \
  --localstatedir=/var \
  CFLAGS="$CFLAGS -fno-lto" \
  LDFLAGS="$LDFLAGS -Wl,-soname,libc.so $BUILTINS_DIR/lib/libclang_rt.builtins.a" \
  CROSS_COMPILE=$LLVM_STAGE1_DIR/bin/

if [ "${MUSL_ONLY_INSTALL_HEADERS:-}" = "1" ]; then
  make DESTDIR="$SYSROOT" install-headers
  exit 0
fi

if $ENABLE_EXECINFO; then
  # install headers
  make DESTDIR=install1 install-headers
  echo "CC libexecinfo_stacktraverse.o"
  $CC $CFLAGS -O2 -fno-strict-aliasing -fstack-protector \
    -Iinstall1/usr/include \
    -c "$MUSL_PATCHDIR/libexecinfo/stacktraverse.c" \
    -o libexecinfo_stacktraverse.o
  echo "CC libexecinfo_execinfo.o"
  $CC $CFLAGS -O2 -fno-strict-aliasing -fstack-protector \
    -Iinstall1/usr/include \
    -c "$MUSL_PATCHDIR/libexecinfo/execinfo.c" \
    -o libexecinfo_execinfo.o
  # patch makefile
  EXECINFO_OBJS="libexecinfo_stacktraverse.o libexecinfo_execinfo.o"
  sed -i '' -E -e "s@^(AOBJS = )@\1${EXECINFO_OBJS} @" Makefile
  sed -i '' -E -e "s@^(LOBJS = )@\1${EXECINFO_OBJS} @" Makefile
fi

make -j$NCPU
make DESTDIR="$SYSROOT" install

# create lld (Dynamic Program Loader) program
mkdir -p "$SYSROOT/bin"
cat <<EOF > "$SYSROOT/bin/ldd"
#!/bin/sh
exec /lib/libc.so --list "\$@"
EOF
chmod 755 "$SYSROOT/bin/ldd"

# provide minimal libssp_nonshared.a so we don't need libssp from gcc
mkdir -p "$SYSROOT/lib"
$CC $CFLAGS \
  -c "$MUSL_PATCHDIR"/__stack_chk_fail_local.c \
  -o /tmp/__stack_chk_fail_local.o
rm -f "$SYSROOT/lib/libssp_nonshared.a"
ar r "$SYSROOT/lib/libssp_nonshared.a" /tmp/__stack_chk_fail_local.o

_popd

# fix dynamic linker symlink
rm "$SYSROOT"/lib/ld-musl-*.so.1
ln -fs libc.so "$SYSROOT/lib/ld.so.1"

# move libc.so aside for now to avoid accidentally linking with it
#mv "$SYSROOT/lib/libc.so" "$SYSROOT/lib/libc-TEMPORARILY_RENAMED.so"

# Installs a few BSD compatibility headers
# (cdefs, queue, tree; known as bsd-compat-headers in alpine)
cd "$MUSL_PATCHDIR"
mkdir -p "$SYSROOT/usr/include/sys"
install -v -m0644 sys-cdefs.h "$SYSROOT/usr/include/sys/cdefs.h"
install -v -m0644 sys-queue.h "$SYSROOT/usr/include/sys/queue.h"
install -v -m0644 sys-tree.h  "$SYSROOT/usr/include/sys/tree.h"

# install execinfo.h
install -v -m0644 \
  "$MUSL_PATCHDIR/libexecinfo/execinfo.h" \
  "$SYSROOT/usr/include/execinfo.h"

$NO_CLEANUP || rm -rf "$MUSL_BUILD_DIR"
