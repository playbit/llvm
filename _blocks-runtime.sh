SRCDIR=$LLVM_STAGE2_SRC/compiler-rt/lib/BlocksRuntime
BUILDDIR=$BLOCKSRUNTIME_DIR-build
DESTDIR=$BLOCKSRUNTIME_DIR

rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
_pushd "$BUILDDIR"

cat << END > config.h
#ifndef _CONFIG_H_
#define _CONFIG_H_
#ifdef __APPLE__
  #define HAVE_AVAILABILITY_MACROS_H 1
  #define HAVE_TARGET_CONDITIONALS_H 1
  #define HAVE_OSATOMIC_COMPARE_AND_SWAP_INT 1
  #define HAVE_OSATOMIC_COMPARE_AND_SWAP_LONG 1
  #define HAVE_LIBKERN_OSATOMIC_H
#endif
#if defined(__clang__)
  #define HAVE_SYNC_BOOL_COMPARE_AND_SWAP_INT 1
  #define HAVE_SYNC_BOOL_COMPARE_AND_SWAP_LONG 1
#endif
#endif
END

CFLAGS="$CFLAGS -O2 -I."

set -x
$CC $CFLAGS -fblocks -c "$SRCDIR/data.c" -o data.o
$CC $CFLAGS -fblocks -c "$SRCDIR/runtime.c" -o runtime.o

rm -f "$DESTDIR/lib/libBlocksRuntime.a"
mkdir -p "$DESTDIR/lib"
$AR crs "$DESTDIR/lib/libBlocksRuntime.a" data.o runtime.o

set +x

_popd
$NO_CLEANUP || rm -rf "$BUILDDIR"
