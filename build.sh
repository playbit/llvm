#!/bin/bash
set -euo pipefail
PWD0=$PWD
cd "$(dirname "$0")"
source lib.sh

LLVM_VERSION=17.0.3
LLVM_SHA256=be5a1e44d64f306bb44fce7d36e3b3993694e8e6122b2348608906283c176db8
LLVM_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/llvm-project-$LLVM_VERSION.src.tar.xz
LLVM_PATCHDIR=$PWD/patches-llvm

MUSL_VERSION=1.2.4
MUSL_SHA256=99c40dbc9637b66cc3257bcf90decf376053f192440c2a3463a478793cc4397f
MUSL_URL=https://git.musl-libc.org/cgit/musl/snapshot/v$MUSL_VERSION.tar.gz
MUSL_PATCHDIR=$PWD/patches-musl

WASI_GIT_TAG=wasi-sdk-21
WASI_GIT_URL=https://github.com/WebAssembly/wasi-libc.git

MAC_SDK_VERSION=11.3
MAC_SDK_SHA256=196e1acde8bf6a8165f5c826531f3c9ce2bd72b0a791649f5b36ff70ff24b824
MAC_SDK_URL="https://d.rsms.me/macos-sdk/MacOSX${MAC_SDK_VERSION}.sdk.tar.xz"

ZLIB_VERSION=1.3.1
ZLIB_SHA256=38ef96b8dfe510d42707d9c781877914792541133e1870841463bfa73f883e32
ZLIB_URL=https://zlib.net/zlib-$ZLIB_VERSION.tar.xz
ZLIB_PATCHDIR=$PWD/patches-zlib

ZSTD_VERSION=1.5.5
ZSTD_SHA256=9c4396cc829cfae319a6e2615202e82aad41372073482fce286fac78646d3ee4
ZSTD_URL=https://github.com/facebook/zstd/releases/download/v$ZSTD_VERSION/zstd-$ZSTD_VERSION.tar.gz

LIBXML2_VERSION=2.11.5
LIBXML2_SHA256=3727b078c360ec69fa869de14bd6f75d7ee8d36987b071e6928d4720a28df3a6
LIBXML2_URL=https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-$LIBXML2_VERSION.tar.xz

TARGET_TRIPLE= # e.g. x86_64-linux
TARGET_ARCH=   # e.g. x86_64, aarch64
TARGET_SYS=    # e.g. linux
TARGET_TRIPLES=(
  aarch64-unknown-linux-musl \
  x86_64-unknown-linux-musl \
  wasm32-unknown-wasi \
)

BUILD_DIR=

HOST_ARCH=$(uname -m)
HOST_ARCH=${HOST_ARCH/arm64/aarch64}
HOST_SYS=$(uname -s | tr '[:upper:]' '[:lower:]')
HOST_SYS=${HOST_SYS/darwin/macos}

VERBOSE=false
PRINT_CONFIG=false
ENABLE_LTO=false


# parse command line arguments
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help) cat <<- _HELP_
usage: $0 [options] <target>
options:
  --builddir=<dir>  Build in <dir>
  --print-config    Print configuration and exit (don't build anything)
  --lto             Build with LTO
  -v                Verbose logging
  -h, --help        Show help and exit
<target>
  Target triple to build llvm for. One of:
$(_array_println "  " ${TARGET_TRIPLES[@]})
_HELP_
    exit ;;
  --builddir=*) BUILD_DIR=${1:11}; shift ;;
  --print-config) PRINT_CONFIG=true; shift ;;
  --lto) ENABLE_LTO=true; shift ;;
  -v) VERBOSE=true; shift ;;
  -*) _err "unknown option $1 (see $0 -help)" ;;
  *)
    [ -z "$TARGET_TRIPLE" ] || _err "extraneous argument: $1"
    TARGET_TRIPLE=$1; shift
    ;;
esac; done

# _vlog ...
if $VERBOSE; then _vlog() { echo "$@" >&2; }; else _vlog() { return 0; }; fi


# target
[ -n "$TARGET_TRIPLE" ] || _err "Missing <target> (see $0 --help)"
TARGET_FOUND=
for t in "${TARGET_TRIPLES[@]}"; do
  if [ $t = "$TARGET_TRIPLE" ]; then
    TARGET_FOUND=1
    break
  fi
done
[ -n "$TARGET_FOUND" ] ||
  _err "Unknown <target> \"$TARGET_TRIPLE\" (see $0 --help)"
IFS=- read -r TARGET_ARCH ign <<< "$TARGET_TRIPLE"
case "$TARGET_TRIPLE" in
  *linux*) TARGET_SYS=linux ;;
  *wasi*)  TARGET_SYS=wasi ;;
esac
CBUILD="$TARGET_ARCH-$TARGET_SYS"
CHOST="$HOST_ARCH-$HOST_SYS"


# set build directory
BUILD_DIR_S1=${BUILD_DIR:-$PWD/build-s1}
BUILD_DIR_S2=${BUILD_DIR:-$PWD/build-$TARGET_TRIPLE}

STAGE1_CFLAGS=
STAGE1_LDFLAGS=
if [ "$HOST_SYS" = "macos" ]; then
  # -platform_version <platform> <min_version> <sdk_version>
  if [ $HOST_ARCH = x86_64 ]; then
    MAC_TARGET_VERSION=10.15
    STAGE1_LDFLAGS+=( -Wl,-platform_version,macos,10.15,$MAC_SDK_VERSION )
  else
    MAC_TARGET_VERSION=11.0
    STAGE1_LDFLAGS+=( -Wl,-platform_version,macos,11.0,$MAC_SDK_VERSION )
  fi
fi


# print configuration
if $VERBOSE || $PRINT_CONFIG; then
  cat << EOF
Configuration:
  TARGET_TRIPLE   $TARGET_TRIPLE
  TARGET_ARCH     $TARGET_ARCH
  TARGET_SYS      $TARGET_SYS
  LLVM_VERSION    $LLVM_VERSION
  ZLIB_VERSION    $ZLIB_VERSION
  ZSTD_VERSION    $ZSTD_VERSION
  LIBXML2_VERSION $LIBXML2_VERSION
  BUILD_DIR_S1    $BUILD_DIR_S1
  BUILD_DIR_S2    $BUILD_DIR_S2
  PATH            $PATH
EOF
fi
$PRINT_CONFIG && exit 0

NCPU=$(nproc)

# llvm dependencies
#   Build:
#     cmake
#   Libraries:
#     zlib      libz.a + headers
#     zstd      libzstd.a + headers
#     libxml2   libxml2.a + headers
#

_run_if_missing() { # <testfile> <script>
  local TESTFILE=$1
  local SCRIPT=$2
  [ -e "$TESTFILE" ] && return 0
  echo "——————————————————————————————————————————————————————————————————————"
  ( source $SCRIPT )
  echo "——————————————————————————————————————————————————————————————————————"
}

# ————————————————————————————————————————————————————————————————————————————
# stage 1
# Build clang for host with host libraries

if [ -z "${CC:-}" ]; then
  if [ "$HOST_SYS" = linux ] && command -v gcc >/dev/null; then
    CC=$(command -v gcc)
    CXX=$(command -v g++)
    STAGE1_LDFLAGS="$STAGE1_LDFLAGS -static-libgcc"
  elif [ "$HOST_SYS" = macos ]; then
    CC="$(command -v clang || true)"
    CXX="$(command -v clang++ || true)"
    LD=ld
  fi
fi
CC=${CC:-cc}
CXX=${CXX:-c++}
AR=${AR:-ar}
ASM=${ASM:-$CC}; AS=$ASM
LD=${LD:-$CXX}
RANLIB=${RANLIB:-ranlib}
CFLAGS=$STAGE1_CFLAGS
LDFLAGS=$STAGE1_LDFLAGS

BUILD_DIR=$BUILD_DIR_S1
mkdir -p "$BUILD_DIR"

# fetch macOS SDK
if [ $HOST_SYS = macos ]; then
  # Note: macOS SDK dir _must_ be named "MacOSX{version}.sdk"
  MAC_SDK=$BUILD_DIR_GENERIC/MacOSX${MAC_SDK_VERSION}.sdk
  if [ ! -d "$MAC_SDK" ]; then
    _download_and_extract_tar "$MAC_SDK_URL" "$MAC_SDK" "$MAC_SDK_SHA256"
  fi
fi

# build zlib
ZLIB_DIR=$BUILD_DIR/s1-zlib-$ZLIB_VERSION
_run_if_missing "$ZLIB_DIR/lib/libz.a" _zlib.sh
echo "Using libz.a at ${ZLIB_DIR##$PWD0/}/"

# build zstd
ZSTD_DIR=$BUILD_DIR/s1-zstd-$ZSTD_VERSION
_run_if_missing "$ZSTD_DIR/lib/libzstd.a" _zstd.sh
echo "Using libzstd.a at ${ZSTD_DIR##$PWD0/}/"

# build libxml2
LIBXML2_DIR=$BUILD_DIR/s1-libxml2-$LIBXML2_VERSION
_run_if_missing "$LIBXML2_DIR/lib/libxml2.a" _libxml2.sh
echo "Using libxml2.a at ${LIBXML2_DIR##$PWD0/}/"

# fetch llvm source
LLVM_STAGE1_SRC=$BUILD_DIR_GENERIC/s1-llvm-$LLVM_VERSION
_run_if_missing "$LLVM_STAGE1_SRC/LICENSE.TXT" _llvm-stage1-source.sh
echo "Using llvm source at ${LLVM_STAGE1_SRC##$PWD0/}"

# build llvm stage 1
LLVM_STAGE1_DIR=$BUILD_DIR/s1-llvm
_run_if_missing "$LLVM_STAGE1_DIR/bin/llvm-tblgen" _llvm-stage1.sh
echo "Using llvm-stage1 at ${LLVM_STAGE1_DIR##$PWD0/}/"
export PATH=$LLVM_STAGE1_DIR/bin:$PATH

# ————————————————————————————————————————————————————————————————————————————
# stage 2
# Build clang for target

# export LD=$CC
if [ $TARGET_SYS = wasi ]; then
  export LD=wasm-ld
else
  export LD=ld.lld
fi

SYSROOT=$BUILD_DIR_S2/sysroot
STAGE2_CFLAGS=(
  --target=$TARGET_TRIPLE \
  --sysroot=$SYSROOT \
  -isystem$LLVM_STAGE1_DIR/include \
  -fPIC \
)
STAGE2_LDFLAGS=(
  --target=$TARGET_TRIPLE \
  --sysroot=$SYSROOT \
  --rtlib=compiler-rt \
  --ld-path=$LLVM_STAGE1_DIR/bin/$LD \
)

if [ $TARGET_SYS = linux ]; then
  # stage 1 clang will try to include crtbeginS.o & crtendS.o even though musl
  # does not use these "C RunTime" files.
  mkdir -p "$BUILD_DIR_S2/phony"
  touch "$BUILD_DIR_S2/phony/crtbegin.o"
  touch "$BUILD_DIR_S2/phony/crtend.o"
  touch "$BUILD_DIR_S2/phony/crtbeginS.o"
  touch "$BUILD_DIR_S2/phony/crtendS.o"
  touch "$BUILD_DIR_S2/phony/crtbeginT.o"
  touch "$BUILD_DIR_S2/phony/crtendT.o"
  STAGE2_LDFLAGS+=( -B"$BUILD_DIR_S2/phony" )
fi

export PATH=$LLVM_STAGE1_DIR/bin:$PATH
export CC=$LLVM_STAGE1_DIR/bin/clang
export CXX=$LLVM_STAGE1_DIR/bin/clang++
export ASM=$LLVM_STAGE1_DIR/bin/clang; AS=$ASM
export RC=$LLVM_STAGE1_DIR/bin/llvm-rc
export AR=$LLVM_STAGE1_DIR/bin/llvm-ar
export RANLIB=$LLVM_STAGE1_DIR/bin/llvm-ranlib
export LIBTOOL=$LLVM_STAGE1_DIR/bin/llvm-libtool-darwin
export OPT=$LLVM_STAGE1_DIR/bin/opt
export LLC=$LLVM_STAGE1_DIR/bin/llc
export LLVM_LINK=$LLVM_STAGE1_DIR/bin/llvm-link
export STRIP=$LLVM_STAGE1_DIR/bin/llvm-strip

export CFLAGS=${STAGE2_CFLAGS[@]}
export LDFLAGS=${STAGE2_LDFLAGS[@]}

BUILD_DIR=$BUILD_DIR_S2
mkdir -p "$BUILD_DIR"

if $VERBOSE || $PRINT_CONFIG; then
  cat << EOF
Stage 3 environment variables:
  CC        $CC
  CXX       $CXX
  ASM       $ASM
  LD        $LD
  RC        $RC
  AR        $AR
  RANLIB    $RANLIB
  LIBTOOL   $LIBTOOL
  OPT       $OPT
  LLC       $LLC
  LLVM_LINK $LLVM_LINK
  STRIP     $STRIP
  RANLIB    $RANLIB
  CFLAGS    $CFLAGS
  LDFLAGS   $LDFLAGS
  PATH      $PATH
EOF
fi

# sysroot
case "$TARGET_SYS" in
linux)
  _run_if_missing "$SYSROOT/usr/include/linux/version.h" _sysroot-linux.sh
  _run_if_missing "$SYSROOT/usr/include/stdlib.h" _sysroot-musl.sh
  ;;
wasi)
  _run_if_missing "$SYSROOT/usr/include/stdlib.h" _sysroot-wasi.sh
  ;;
esac
echo "Using sysroot at ${SYSROOT##$PWD0/}/"

# setup llvm source
#
# LLVM_SRC_CHANGE_TRACKING_ENABLED: if true, track changes to files in
LLVM_SRC_CHANGE_TRACKING_ENABLED=true
# LLVM_STAGE2_SRC via git. Slow and uses a lot of disk space but useful when
# working on llvm patches.
#
LLVM_STAGE2_SRC=$BUILD_DIR_GENERIC/s2-llvm-$LLVM_VERSION
_run_if_missing "$LLVM_STAGE2_SRC/LICENSE.TXT" _llvm-stage2-source.sh
echo "Using llvm source at ${LLVM_STAGE1_SRC##$PWD0/}"

# build builtins.a
BUILTINS_DIR=$BUILD_DIR/s2-builtins
_run_if_missing "$BUILTINS_DIR/builtins.a" _llvm-builtins.sh
echo "Using builtins.a at ${BUILTINS_DIR##$PWD0/}/"
CFLAGS="$CFLAGS -resource-dir=$BUILTINS_DIR/"
LDFLAGS="$LDFLAGS -resource-dir=$BUILTINS_DIR/"

# build libcxx (libc++.a, libc++abi.a, libunwind.a)
LIBCXX_DIR=$BUILD_DIR/s2-libcxx
_run_if_missing "$LIBCXX_DIR/lib/libc++.a" _llvm-libcxx.sh
echo "Using libc++.a & libunwind.a at ${LIBCXX_DIR##$PWD0/}/"
CFLAGS="$CFLAGS -isystem$LIBCXX_DIR/usr/include"
LDFLAGS="$LDFLAGS -L$LIBCXX_DIR/lib"

# must explicitly specify search path for "clang headers"
# or else zstd will fail to build, not finding emmintrin.h.
S1_CLANGRES_DIR=$(realpath $($LLVM_STAGE1_DIR/bin/clang --print-runtime-dir)/../..)
CFLAGS="$CFLAGS -isystem$S1_CLANGRES_DIR/include"

# build zlib
ZLIB_DIR=$BUILD_DIR/s2-zlib-$ZLIB_VERSION
_run_if_missing "$ZLIB_DIR/lib/libz.a" _zlib.sh
echo "Using libz.a at ${ZLIB_DIR##$PWD0/}/"

# build zstd
ZSTD_DIR=$BUILD_DIR/s2-zstd-$ZSTD_VERSION
_run_if_missing "$ZSTD_DIR/lib/libzstd.a" _zstd.sh
echo "Using libzstd.a at ${ZSTD_DIR##$PWD0/}/"

# build libxml2
LIBXML2_DIR=$BUILD_DIR/s2-libxml2-$LIBXML2_VERSION
_run_if_missing "$LIBXML2_DIR/lib/libxml2.a" _libxml2.sh
echo "Using libxml2.a at ${LIBXML2_DIR##$PWD0/}/"

# build llvm stage 2
LLVM_STAGE2_DIR=$BUILD_DIR/s2-llvm
_run_if_missing "$LLVM_STAGE2_DIR/bin/clang-xxx" _llvm-stage2.sh
echo "Using llvm-stage2 at ${LLVM_STAGE2_DIR##$PWD0/}/"
exit

# # build llvm runtimes
# LLVM_RUNTIMES_DIR=$BUILD_DIR/llvm-runtimes
# _run_if_missing "$LLVM_RUNTIMES_DIR/lib/libx.a" _llvm-runtimes.sh
# echo "Using llvm-runtimes at ${LLVM_RUNTIMES_DIR##$PWD0/}/"
# exit


# build llvm
LLVM_DIR=$BUILD_DIR/llvm-stage1
source _llvm-stage1.sh

exit 0



# build llvm
LLVM_DIR=$BUILD_DIR/llvm-stage2
source _llvm-build.sh

