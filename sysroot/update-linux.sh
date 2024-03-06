#!/bin/bash
#
# Replaces all ./*-linux directories
#
set -euo pipefail
cd "$(dirname "$0")"
SYSROOT_DIR=$PWD
cd ..
source lib.sh

KERNEL_VERSION_FILE=../playbit/kernel/version.txt
[ -f "$KERNEL_VERSION_FILE" ] || _err "$KERNEL_VERSION_FILE: file not found"
KERNEL_VERSIONINFO=$(cat "$KERNEL_VERSION_FILE")
KERNEL_VERSION=${KERNEL_VERSIONINFO%% *}
KERNEL_VERSION_MAJOR=${KERNEL_VERSION%%.*}  # e.g. "5"
KERNEL_TARXZ_SHA256=${KERNEL_VERSIONINFO##* }
KERNEL_TARXZ_NAME=linux-$KERNEL_VERSION.tar.xz
KERNEL_TARXZ_URL=https://kernel.org/pub/linux/kernel/v${KERNEL_VERSION_MAJOR}.x/$KERNEL_TARXZ_NAME
KERNEL_SRCDIR="$BUILD_DIR_GENERIC/linux-$KERNEL_VERSION"

DESTDIR_BASE="$BUILD_DIR_GENERIC/linux-$KERNEL_VERSION-headers"

# headers_install runs some sed scripts which are not compatible with BSD sed.
# Even more importantly, the "ARCH=x86 headers_install" target compiles a program
# arch/x86/tools/relocs_32.o which needs elf.h from the host system.
[ "$(uname -s)" = Linux ] || _err "must run this script on Linux"

if [ ! -f "$KERNEL_SRCDIR/Makefile" ]; then
  _download_and_extract_tar \
    "$KERNEL_TARXZ_URL" \
    "$KERNEL_SRCDIR" \
    "$KERNEL_TARXZ_SHA256"
fi

_pushd "$KERNEL_SRCDIR"
rm -rf "$DESTDIR_BASE"
DESTDIRS=()
for arch in arm64 x86; do
  arch2=${arch/arm64/aarch64}
  arch2=${arch2/x86/x86_64}
  arch2=${arch2/riscv/riscv64}
  DESTDIR="$DESTDIR_BASE/${arch2}-linux"
  DESTDIRS+=( "$DESTDIR" )
  # note: do not use -j here!
  echo "make ARCH=$arch headers_install -> ${DESTDIR##$PWD0/}"
  make ARCH=$arch INSTALL_HDR_PATH="$DESTDIR" headers_install
done
_popd

# regenerate sysroot
tools/build.sh
rm -rf "$SYSROOT_DIR"/*-linux
for DESTDIR in "${DESTDIRS[@]}"; do
  DESTDIR2="$SYSROOT_DIR/$(basename "$DESTDIR")"
  rm -rf "$DESTDIR2"
  cp -R "$DESTDIR" "$DESTDIR2"
done
tools/dedup-target-files "$SYSROOT_DIR"
# remove dotfiles and empty directories
find "$SYSROOT_DIR" \( -type f -name '.*' -o -type d -empty \) -delete
