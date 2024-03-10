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
WASI_SHA256=4a2a3e3b120ba1163c57f34ac79c3de720a8355ee3a753d81f1f0c58c4cf6017
WASI_URL=https://github.com/WebAssembly/wasi-libc/archive/refs/tags/$WASI_GIT_TAG.tar.gz

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

TARGET_TRIPLES=(
  aarch64-unknown-linux-musl \
  x86_64-unknown-linux-musl \
  wasm32-unknown-wasi \
)
# ONLY_BUILD_ARCHS: if non-empty, only build clang for TARGET_TRIPLES with these archs
ONLY_BUILD_ARCHS=()

HOST_ARCH=$(uname -m)
HOST_ARCH=${HOST_ARCH/arm64/aarch64}
HOST_SYS=$(uname -s | tr '[:upper:]' '[:lower:]')
HOST_SYS=${HOST_SYS/darwin/macos}

VERBOSE=false
PRINT_CONFIG=false
ENABLE_LTO=true
REBUILD_LLVM=false
NO_PACKAGE=false
NO_CLEANUP=false


# parse command line arguments
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help)
    VALID_ONLY_BUILD_ARCHS=()
    for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
      [[ $TARGET_TRIPLE == wasm* ]] && continue
      VALID_ONLY_BUILD_ARCHS+=( ${TARGET_TRIPLE%%-*} )
    done
    cat <<- _HELP_
usage: $0 [options] [<target> ...]
options:
  --print-config  Print configuration and exit (don't build anything)
  --no-lto        Disable LTO
  --no-package    Don't create package of final product (useful when debugging)
  --no-cleanup    Don't remove temporary build directories after successful builds
  --rebuild-llvm  Incrementally (re)build llvm stage 2 even if it's up to date
  -v              Verbose logging
  -h, --help      Show help and exit
<target>
  Only build SKD for this target. If none are given, build for all targets.
  Possible values: ${VALID_ONLY_BUILD_ARCHS[*]}
_HELP_
    exit ;;
  --print-config) PRINT_CONFIG=true; shift ;;
  --no-lto) ENABLE_LTO=false; shift ;;
  --no-package) NO_PACKAGE=true; shift ;;
  --no-cleanup) NO_CLEANUP=true; shift ;;
  --rebuild-llvm) REBUILD_LLVM=true; shift ;;
  -v) VERBOSE=true; shift ;;
  -*) _err "unknown option $1 (see $0 -help)" ;;
  *) ONLY_BUILD_ARCHS+=( $1 ); shift;;
esac; done

# _vlog ...
if $VERBOSE; then _vlog() { echo "$@" >&2; }; else _vlog() { return 0; }; fi


# targets to build compiler for (all by default)
BUILD_TARGET_TRIPLES=()
for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  [[ $TARGET_TRIPLE == wasm* ]] && continue
  BUILD_TARGET_TRIPLES+=( $TARGET_TRIPLE )
done
if [ ${#ONLY_BUILD_ARCHS[@]} -gt 0 ]; then
  BUILD_TARGET_TRIPLES_FILTERED=()
  for arg in ${ONLY_BUILD_ARCHS[@]}; do
    found=
    for TARGET_TRIPLE in ${BUILD_TARGET_TRIPLES[@]}; do
      IFS=- read -r arch ign <<< "$TARGET_TRIPLE"
      if [ "$arch" = "$arg" ]; then
        BUILD_TARGET_TRIPLES_FILTERED+=( $TARGET_TRIPLE )
        found=1
        break
      fi
    done
    [ -n "$found" ] || _err "Invalid <target> \"$arg\" (see $0 --help)"
  done
  BUILD_TARGET_TRIPLES=( ${BUILD_TARGET_TRIPLES_FILTERED[@]} )
fi


# set build directory
BUILD_DIR_S1=${BUILD_DIR_S1:-$PWD/build-host}
BUILD_DIR_S2=${BUILD_DIR_S2:-$PWD/build-target}

STAGE1_CFLAGS=( -march=native )
STAGE1_LDFLAGS=()
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
  TARGETS          ${TARGET_TRIPLES[*]}
  BUILD_TARGETS    ${BUILD_TARGET_TRIPLES[*]}
  LLVM_VERSION     $LLVM_VERSION
  ZLIB_VERSION     $ZLIB_VERSION
  ZSTD_VERSION     $ZSTD_VERSION
  LIBXML2_VERSION  $LIBXML2_VERSION
  MUSL_VERSION     $MUSL_VERSION
  WASI_GIT_TAG     $WASI_GIT_TAG
  BUILD_DIR_S1     $BUILD_DIR_S1
  BUILD_DIR_S2     $BUILD_DIR_S2
  PATH             $PATH
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
  if [ -e "$TESTFILE" ] && ! [ $REBUILD_LLVM = true -a $SCRIPT = _llvm-stage2.sh ]; then
    return 0
  fi
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
    STAGE1_LDFLAGS+=( -static-libgcc )
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
CFLAGS=${STAGE1_CFLAGS[@]:-}
LDFLAGS=${STAGE1_LDFLAGS[@]:-}

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
ZLIB_DIR=$BUILD_DIR/zlib
_run_if_missing "$ZLIB_DIR/lib/libz.a" _zlib.sh
echo "Using libz.a at ${ZLIB_DIR##$PWD0/}/"

# build zstd
ZSTD_DIR=$BUILD_DIR/zstd
_run_if_missing "$ZSTD_DIR/lib/libzstd.a" _zstd.sh
echo "Using libzstd.a at ${ZSTD_DIR##$PWD0/}/"

# build libxml2
LIBXML2_DIR=$BUILD_DIR/libxml2
_run_if_missing "$LIBXML2_DIR/lib/libxml2.a" _libxml2.sh
echo "Using libxml2.a at ${LIBXML2_DIR##$PWD0/}/"

# fetch llvm source
LLVM_STAGE1_SRC=$BUILD_DIR_GENERIC/s1-llvm-$LLVM_VERSION
_run_if_missing "$LLVM_STAGE1_SRC/LICENSE.TXT" _llvm-stage1-source.sh
echo "Using llvm source at ${LLVM_STAGE1_SRC##$PWD0/}"

# build llvm stage 1 (for host)
LLVM_STAGE1_DIR=$BUILD_DIR/llvm
_run_if_missing "$LLVM_STAGE1_DIR/bin/clang" _llvm-stage1.sh
echo "Using llvm-stage1 at ${LLVM_STAGE1_DIR##$PWD0/}/"
export PATH=$LLVM_STAGE1_DIR/bin:$PATH

HOST_TRIPLE=$($LLVM_STAGE1_DIR/bin/clang -print-target-triple)

# ————————————————————————————————————————————————————————————————————————————
# stage 2

BUILD_DIR=$BUILD_DIR_S2
mkdir -p "$BUILD_DIR"

# stage 1 clang will try to include crtbeginS.o & crtendS.o even though musl
# does not use these "CRunTime" files.
mkdir -p "$BUILD_DIR/phony"
touch "$BUILD_DIR/phony/crtbegin.o"
touch "$BUILD_DIR/phony/crtend.o"
touch "$BUILD_DIR/phony/crtbeginS.o"
touch "$BUILD_DIR/phony/crtendS.o"
touch "$BUILD_DIR/phony/crtbeginT.o"
touch "$BUILD_DIR/phony/crtendT.o"

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

GENERIC_CFLAGS="-isystem$LLVM_STAGE1_DIR/include -fPIC"
GENERIC_LDFLAGS="--rtlib=compiler-rt -B$BUILD_DIR/phony"
# GENERIC_LDFLAGS="--rtlib=compiler-rt --ld-path=$LLVM_STAGE1_DIR/bin/ld.lld"

S1_CLANGRES_DIR=$(realpath $($LLVM_STAGE1_DIR/bin/clang --print-runtime-dir)/../..)

_setenv_for_target() {
  export TARGET_TRIPLE=$1
  export SYSROOT=$BUILD_DIR/sysroot-$TARGET_TRIPLE
  export CFLAGS="$GENERIC_CFLAGS --target=$TARGET_TRIPLE --sysroot=$SYSROOT"
  export LDFLAGS="$GENERIC_LDFLAGS --target=$TARGET_TRIPLE --sysroot=$SYSROOT"
  local arch b c
  IFS=- read -r arch b c ign <<< "$TARGET_TRIPLE"
  case "$TARGET_TRIPLE" in
    *linux*) CBUILD="$arch-linux" ;;
    *)       CBUILD="$arch-$c" ;;
  esac
  export CBUILD
  export CHOST="$HOST_ARCH-$HOST_SYS"
}

# —————————————————————————————————————————————————————————————————————————————
# build sysroot for every TARGET_TRIPLE, consisting of:
# - compiler builtins (e.g. lib/linux/libclang_rt.builtins-aarch64.a)
# - libc
# - libc++ & libc++abi
# - libunwind
#
echo "~~~~~~~~~~~~~~~~~~~~ sysroot ~~~~~~~~~~~~~~~~~~~~"

# build sysroots
for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  _setenv_for_target $TARGET_TRIPLE
  case "$TARGET_TRIPLE" in
  *-linux*)
    _run_if_missing "$SYSROOT/include/linux/version.h" _linux-headers.sh
    _run_if_missing "$SYSROOT/include/stdlib.h" _musl.sh
    ;;
  *-wasi*)
    _run_if_missing "$SYSROOT/include/stdlib.h" _wasi.sh
    ;;
  esac
done
echo "Using sysroots at $BUILD_DIR/sysroot-*/"

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

# build compiler builtins
BUILTINS_DIR=$BUILD_DIR/builtins
_run_if_missing \
  "$BUILTINS_DIR/lib/${TARGET_TRIPLES[0]}/libclang_rt.builtins.a" _builtins.sh
echo "Using builtins.a at ${BUILTINS_DIR##$PWD0/}/lib/*"

# build libunwind, libc++ and libc++abi
LIBCXX_DIR=$BUILD_DIR/libcxx
_run_if_missing "$LIBCXX_DIR/lib-${TARGET_TRIPLES[0]}/libc++.a" _libcxx.sh
echo "Using libc++.a at ${LIBCXX_DIR##$PWD0/}/lib-*/"

# —————————————————————————————————————————————————————————————————————————————
# build llvm for every BUILD_TARGET_TRIPLES
BASE_CFLAGS=$CFLAGS
BASE_LDFLAGS=$LDFLAGS
for TARGET_TRIPLE in ${BUILD_TARGET_TRIPLES[@]}; do
  _setenv_for_target $TARGET_TRIPLE
  $ENABLE_LTO && CFLAGS="$CFLAGS -flto=thin"
  # builtins
  CFLAGS="$CFLAGS -resource-dir=$BUILTINS_DIR/"
  LDFLAGS="$LDFLAGS -resource-dir=$BUILTINS_DIR/"
  # libc++
  CFLAGS="$CFLAGS -I$LIBCXX_DIR/include/c++/v1 -I$LIBCXX_DIR/include"
  LDFLAGS="$LDFLAGS -L$LIBCXX_DIR/lib-$TARGET_TRIPLE"
  # compiler headers (e.g. stdint.h)
  CFLAGS="$CFLAGS -isystem$S1_CLANGRES_DIR/include"

  echo "~~~~~~~~~~~~~~~~~~~~ llvm ${TARGET_TRIPLE%%-*} ~~~~~~~~~~~~~~~~~~~~"
  echo "SYSROOT $SYSROOT"
  echo "CFLAGS  $CFLAGS"
  echo "LDFLAGS $LDFLAGS"

  # build zlib
  ZLIB_DIR=$BUILD_DIR/zlib-$TARGET_TRIPLE
  _run_if_missing "$ZLIB_DIR/lib/libz.a" _zlib.sh
  echo "Using libz.a at ${ZLIB_DIR##$PWD0/}/"

  # build zstd
  ZSTD_DIR=$BUILD_DIR/zstd-$TARGET_TRIPLE
  _run_if_missing "$ZSTD_DIR/lib/libzstd.a" _zstd.sh
  echo "Using libzstd.a at ${ZSTD_DIR##$PWD0/}/"

  # build libxml2
  LIBXML2_DIR=$BUILD_DIR/libxml2-$TARGET_TRIPLE
  _run_if_missing "$LIBXML2_DIR/lib/libxml2.a" _libxml2.sh
  echo "Using libxml2.a at ${LIBXML2_DIR##$PWD0/}/"

  # build llvm stage 2 (for target, not host)
  LLVM_STAGE2_DIR=$BUILD_DIR/llvm-$TARGET_TRIPLE
  _run_if_missing "$LLVM_STAGE2_DIR/bin/clang" _llvm-stage2.sh
  echo "Using llvm-stage2 at ${LLVM_STAGE2_DIR##$PWD0/}/"
done

[ -n "${PB_LLVM_STOP_AFTER_BUILD:-}" ] && exit 0

# —————————————————————————————————————————————————————————————————————————————
# build compiler runtimes (e.g. sanitizers) for every TARGET_TRIPLE
# Note: we built libclang_rt.builtins.a earlier
echo "~~~~~~~~~~~~~~~~~~~~ compiler-rt ~~~~~~~~~~~~~~~~~~~~"
COMPILER_RT_DIR=$BUILD_DIR/compiler-rt
for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  [[ $TARGET_TRIPLE == wasm* ]] && continue
  _setenv_for_target $TARGET_TRIPLE
  _run_if_missing \
    "$COMPILER_RT_DIR/lib/$TARGET_TRIPLE/libclang_rt.asan.a" _compiler-rt.sh
  echo "Using compiler-rt at ${COMPILER_RT_DIR##$PWD0/}/lib/$TARGET_TRIPLE/"
done

# # build compiler-rt for every TARGET_TRIPLE
# # COMPILER_RT_DIR=$BUILD_DIR/compiler-rt-$TARGET_TRIPLE
# # _run_if_missing "$COMPILER_RT_DIR/xxx" _compiler-rt.sh
# #
# # ( TARGET_TRIPLE=aarch64-unknown-linux-musl
# #   COMPILER_RT_DIR=$BUILD_DIR/compiler-rt-$TARGET_TRIPLE
# #   SYSROOT=$BUILD_DIR/sysroot-$TARGET_TRIPLE
# #   _run_if_missing "$COMPILER_RT_DIR/xxx" _compiler-rt.sh
# # )
# #
# COMPILER_RT_DIR=$BUILD_DIR/compiler-rt
# for TARGET_TRIPLE2 in ${TARGET_TRIPLES[@]}; do
#   # only builtins for wasm (built earliear), no sanitizers et al
#   [[ $TARGET_TRIPLE2 == wasm* ]] && continue
#   TARGET_TRIPLE=$TARGET_TRIPLE2 \
#   SYSROOT=$BUILD_DIR/sysroot-$TARGET_TRIPLE2 \
#   _run_if_missing \
#     "$COMPILER_RT_DIR/lib/$TARGET_TRIPLE2/libclang_rt.asan.a" \
#     _compiler-rt.sh
# done
# echo "Using compiler-rt at ${COMPILER_RT_DIR##$PWD0/}/"

# ——————————————————————————————————————————————————————————————————————————————
# step 3: package
if ! $NO_PACKAGE; then
  for TARGET_TRIPLE in ${BUILD_TARGET_TRIPLES[@]}; do
    TARGET_ARCH=${TARGET_TRIPLE%%-*}
    PACKAGE_DIR=$BUILD_DIR/package-$TARGET_ARCH
    PACKAGE_ARCHIVE=$BUILD_DIR/playbit-sdk-$TARGET_ARCH.tar.xz
    LLVM_STAGE2_DIR=$BUILD_DIR/llvm-$TARGET_TRIPLE
    echo "~~~~~~~~~~~~~~~~~~~~ package $TARGET_ARCH ~~~~~~~~~~~~~~~~~~~~"
    ( source _package.sh )
  done
fi
