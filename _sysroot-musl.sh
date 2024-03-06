MUSL_BUILD_DIR=$BUILD_DIR/s2-musl-$MUSL_VERSION

_download_and_extract_tar \
  "$MUSL_URL" "$MUSL_BUILD_DIR" "$MUSL_SHA256" \
  "$DOWNLOAD_DIR/musl-$MUSL_VERSION.tar.gz"

_pushd "$MUSL_BUILD_DIR"

for f in $(echo "$MUSL_PATCHDIR"/*.patch | sort); do
  patch -p1 < "$f"
done

LDFLAGS="$LDFLAGS -Wl,-soname,libc.so" \
./configure \
  --prefix="" \
  --sysconfdir=/etc \
  --bindir=/bin \
  --libdir=/lib \
  --syslibdir=/lib \
  --includedir=/usr/include \
  --mandir=/usr/share/man \
  --infodir=/usr/share/info \
  --localstatedir=/var

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
rm -rf "$MUSL_BUILD_DIR"

# fix dynamic linker symlink
rm "$SYSROOT/lib/ld-musl-x86_64.so.1"
ln -s libc.so "$SYSROOT/lib/ld"

# Installs a few BSD compatibility headers
# (cdefs, queue, tree; known as bsd-compat-headers in alpine)
cd "$MUSL_PATCHDIR"
mkdir -p "$SYSROOT/usr/include/sys"
install -v -m0644 sys-cdefs.h "$SYSROOT/usr/include/sys/cdefs.h"
install -v -m0644 sys-queue.h "$SYSROOT/usr/include/sys/queue.h"
install -v -m0644 sys-tree.h  "$SYSROOT/usr/include/sys/tree.h"
