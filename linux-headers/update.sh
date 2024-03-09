#!/bin/bash
#
# Replaces all ./*-linux directories
#
set -euo pipefail
cd "$(dirname "$0")"
DESTDIR=${DESTDIR:-$PWD}
cd ..
source lib.sh

if [ -z "${PLAYBIT:-}" ]; then
  if [ "$(id -u)" = "0" ] && [ -f /p/kernel/version.txt ]; then
    PLAYBIT=/p
  elif [ -d $HOME/playbit/playbit ]; then
    PLAYBIT=$HOME/playbit/playbit
  elif [ -d ../playbit ]; then
    PLAYBIT=../playbit
  else
    _err "Cannot find playbit source directory. Set PLAYBIT=<dir>"
  fi
fi

KERNEL_VERSION_FILE=$PLAYBIT/kernel/version.txt
[ -f "$KERNEL_VERSION_FILE" ] || _err "$KERNEL_VERSION_FILE: file not found"
KERNEL_VERSIONINFO=$(cat "$KERNEL_VERSION_FILE")
KERNEL_VERSION=${KERNEL_VERSIONINFO%% *}
KERNEL_VERSION_MAJOR=${KERNEL_VERSION%%.*}  # e.g. "5"
KERNEL_TARXZ_SHA256=${KERNEL_VERSIONINFO##* }
KERNEL_TARXZ_NAME=linux-$KERNEL_VERSION.tar.xz
KERNEL_TARXZ_URL=https://kernel.org/pub/linux/kernel/v${KERNEL_VERSION_MAJOR}.x/$KERNEL_TARXZ_NAME

BUILD_DIR_IS_TEMPORARY=
if [ -z "${BUILD_DIR:-}" ]; then
  BUILD_DIR=/tmp/linux-headers-$KERNEL_VERSION-build
  BUILD_DIR_IS_TEMPORARY=1
fi

if [ -z "${LINUX_SOURCE:-}" ]; then
  LINUX_SOURCE=$BUILD_DIR/src
  if [ "$(id -u)" = "0" ] &&
     [ -f /build/linux/usr/include/linux/version.h ]
  then
    VERSION=$(grep -E 'LINUX_VERSION_(MAJOR|PATCHLEVEL|SUBLEVEL)' \
      /build/linux/usr/include/linux/version.h | cut -d' ' -f3 |
      xargs sh -c "printf \$0.\$1.\$2")
    if [ $VERSION = $KERNEL_VERSION ]; then
      LINUX_SOURCE=/build/linux
    else
      echo "warning: found existing linux source at /build/linux of a different version ($VERSION) than expected ($KERNEL_VERSION); ignoring" >&2
    fi
  fi
fi
echo "Using linux source at $LINUX_SOURCE"

# headers_install runs some sed scripts which are not compatible with BSD sed.
# Even more importantly, the "ARCH=x86 headers_install" target compiles a program
# arch/x86/tools/relocs_32.o which needs elf.h from the host system.
[ "$(uname -s)" = Linux ] || _err "must run this script on Linux"

if [ ! -f "$LINUX_SOURCE/Makefile" ]; then
  _download_and_extract_tar \
    "$KERNEL_TARXZ_URL" \
    "$LINUX_SOURCE" \
    "$KERNEL_TARXZ_SHA256"
fi

_pushd "$LINUX_SOURCE"
HEADERS_DIRS=()
for arch in arm64 x86 riscv; do
  arch2=${arch/arm64/aarch64}
  arch2=${arch2/x86/x86_64}
  arch2=${arch2/riscv/riscv64}
  HEADERS_DIR="$BUILD_DIR/${arch2}-linux"
  HEADERS_DIRS+=( "$HEADERS_DIR" )
  rm -rf "$HEADERS_DIR"
  # note: do not use -j here!
  echo "make ARCH=$arch headers_install -> ${HEADERS_DIR##$PWD0/}"
  make ARCH=$arch INSTALL_HDR_PATH="$HEADERS_DIR" headers_install
done
_popd

# generate minimal directories
TMP_DESTDIR=/tmp/linux-headers-$KERNEL_VERSION-dist
rm -rf $TMP_DESTDIR
mkdir -p $TMP_DESTDIR
for HEADERS_DIR in "${HEADERS_DIRS[@]}"; do
  NAME=$(basename "$HEADERS_DIR")
  DEST_HEADERS_DIR=$TMP_DESTDIR/$NAME
  rm -rf "$DEST_HEADERS_DIR"
  cp -R "$HEADERS_DIR" "$DEST_HEADERS_DIR"
done
tools/build.sh
tools/dedup-target-files $TMP_DESTDIR

# remove dotfiles and empty directories
find $TMP_DESTDIR \
  \( -type f -name '.*' -o -type d -empty \) -delete

# copy to destination
_install_headers() {
  echo "Installing headers at $2"
  mv $1 "$2" 2>/dev/null || cp -R $1 "$2"
}
echo "Clearing old headers at $DESTDIR/*-linux"
rm -rf "$DESTDIR"/*-linux
mkdir -p "$DESTDIR"
if [ -d $TMP_DESTDIR/any-linux ]; then
  _install_headers $TMP_DESTDIR/any-linux "$DESTDIR/any-linux"
fi
for HEADERS_DIR in "${HEADERS_DIRS[@]}"; do
  NAME=$(basename "$HEADERS_DIR")
  _install_headers $TMP_DESTDIR/$NAME "$DESTDIR/$NAME"
done

rm -rf $TMP_DESTDIR
[ -n "$BUILD_DIR_IS_TEMPORARY" ] && rm -rf "$BUILD_DIR"
echo "Done. Headers are available at $DESTDIR"
