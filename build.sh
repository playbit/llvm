#!/bin/bash
set -euo pipefail
PWD0=$PWD
cd "$(dirname "$0")"
source lib.sh

# targets to build toolchain for (i.e. clang, lld, et al)
TOOLCHAIN_TARGETS=(
  aarch64-macos \
  x86_64-macos \
  aarch64-playbit \
  x86_64-playbit \
  aarch64-linux \
  x86_64-linux \
)
# targets to build sysroots for
SYSROOT_TARGETS=(
  aarch64-macos \
  x86_64-macos \
  aarch64-playbit \
  x86_64-playbit \
  wasm32-playbit \
)

PKG_VERSION=2
LLVM_VERSION=17.0.3
LLVM_SHA256=be5a1e44d64f306bb44fce7d36e3b3993694e8e6122b2348608906283c176db8
LLVM_URL=https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/llvm-project-$LLVM_VERSION.src.tar.xz
LLVM_PATCHDIR=$PWD/patches-llvm

# Link llvm tools statically rather than with libLLVM.so
LLVM_ENABLE_STATIC_LINKING=false

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

NCURSES_VERSION=6.5-20241207
NCURSES_SHA256=b2a1ef3574a191763b0bd19d169c4e6bd235aa25707ef26286c9ba6dbf2e6f82
NCURSES_URL=https://invisible-mirror.net/archives/ncurses/current/ncurses-${NCURSES_VERSION}.tgz

LIBEDIT_VERSION=20240517-3.1
LIBEDIT_SHA256=3a489097bb4115495f3bd85ae782852b7097c556d9500088d74b6fa38dbd12ff
LIBEDIT_URL=https://www.thrysoee.dk/editline/libedit-${LIBEDIT_VERSION}.tar.gz

XZ_VERSION=5.6.1
XZ_SHA256=237284fae40e5f8e9908f0a977e7d0b9a5c7c1c10a41b8e6ed0fb40e930467c8
XZ_URL=https://github.com/tukaani-project/xz/archive/refs/tags/v${XZ_VERSION}/xz-${XZ_VERSION}.tar.gz

BINARYEN_VERSION=117
BINARYEN_SHA256=9acf7cc5be94bcd16bebfb93a1f5ac6be10e0995a33e1981dd7c404dafe83387
BINARYEN_URL=https://github.com/WebAssembly/binaryen/archive/refs/tags/version_$BINARYEN_VERSION.tar.gz

HOST_ARCH=$(uname -m)
HOST_ARCH=${HOST_ARCH/arm64/aarch64}
HOST_SYS=$(uname -s | tr '[:upper:]' '[:lower:]')
HOST_SYS=${HOST_SYS/darwin/macos}

ENABLE_LLVM_DEV_FILES=true
VERBOSE=false
PRINT_CONFIG=false
ENABLE_LTO=true
REBUILD_LLVM=false
NO_PACKAGE=false
NO_ARCHIVE=false
NO_CLEANUP=false
NO_NATIVE_TOOLCHAIN=false
ONLY_TOOLCHAIN_TARGETS=()
ONLY_SYSROOT_TARGETS=()

XZ_COMPRESSION_RATIO=8 # 0-9 (xz default is 6)
# XZ_COMPRESSION_RATIO for toolchain-aarch64-macos on an M1 MacBook:
#   0  61.9 MB  1.3s
#   1  58.6 MB  1.8s
#   2  57.2 MB  2.8s
#   3  56.2 MB  4.9s
#   4  53.3 MB  7.5s
#   5  48.5 MB  11.1s
#   6  47.9 MB  10.4s
#   7  43.3 MB  17.4s
#   8  39.2 MB  29.5s
#   9  36.9 MB  55.2s

# parse command line arguments
while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help)
    cat <<- _HELP_
usage: $0 [options] [<target> ...]
options:
  --print-config  Print configuration and exit (don't build anything)
  --no-lto        Disable LTO
  --no-package    Don't create package of final product (useful when debugging)
  --no-archive    Don't create package archives (saves time when debugging)
  --no-cleanup    Don't remove temporary build directories after successful builds
  --no-native-toolchain
                  Don't setup local toolchain at packages/toolchain
  --compress=<r>  Use this xz compression ratio [0-9] for packages (default: $XZ_COMPRESSION_RATIO)
  --rebuild-llvm  Incrementally (re)build llvm stage 2 even if it's up to date
  --sysroot-target=<target>
                  Only build sysroot for <target>. Can be given multiple times.
                  If not set, build all sysroots (${SYSROOT_TARGETS[*]}).
  -v              Verbose logging
  -h, --help      Show help and exit
<target>
  Only build toolchain for this targets. Many can be provided.
  If not set, build for: ${TOOLCHAIN_TARGETS[*]}
_HELP_
    exit ;;
  --print-config) PRINT_CONFIG=true; shift ;;
  --no-lto) ENABLE_LTO=false; shift ;;
  --no-package) NO_PACKAGE=true; shift ;;
  --no-archive) NO_ARCHIVE=true; shift ;;
  --no-cleanup) NO_CLEANUP=true; shift ;;
  --no-native-toolchain) NO_NATIVE_TOOLCHAIN=true; shift ;;
  --rebuild-llvm) REBUILD_LLVM=true; shift ;;
  --compress=*) XZ_COMPRESSION_RATIO=${1:11}; shift;;
  --sysroot-target=*) ONLY_SYSROOT_TARGETS+=( ${1:17} ); shift;;
  -v) VERBOSE=true; shift ;;
  -*) _err "unknown option $1 (see $0 -help)" ;;
  *) ONLY_TOOLCHAIN_TARGETS+=( $1 ); shift;;
esac; done

# _vlog ...
if $VERBOSE; then _vlog() { echo "$@" >&2; }; else _vlog() { return 0; }; fi


# filter targets to build toolchain for
if [ ${#ONLY_TOOLCHAIN_TARGETS[@]} -gt 0 ]; then
  TOOLCHAIN_TARGETS_FILTERED=()
  for arg in ${ONLY_TOOLCHAIN_TARGETS[@]}; do
    found=
    for TARGET in ${TOOLCHAIN_TARGETS[@]}; do
      if [ "$TARGET" = "$arg" ]; then
        TOOLCHAIN_TARGETS_FILTERED+=( $TARGET )
        found=1
        break
      fi
    done
    [ -n "$found" ] || _err "Invalid <target> \"$arg\" (see $0 --help)"
  done
  TOOLCHAIN_TARGETS=( ${TOOLCHAIN_TARGETS_FILTERED[@]} )
fi


# filter targets to build sysroot for
if [ ${#ONLY_SYSROOT_TARGETS[@]} -gt 0 ]; then
  SYSROOT_TARGETS_FILTERED=()
  for arg in ${ONLY_SYSROOT_TARGETS[@]}; do
    found=
    for TARGET in ${SYSROOT_TARGETS[@]}; do
      if [ "$TARGET" = "$arg" ]; then
        SYSROOT_TARGETS_FILTERED+=( $TARGET )
        found=1
        break
      fi
    done
    [ -n "$found" ] || _err "Invalid <target> \"$arg\" (see $0 --help)"
  done
  SYSROOT_TARGETS=( ${SYSROOT_TARGETS_FILTERED[@]} )
fi


# set build & output directories
BUILD_DIR_S1=${BUILD_DIR_S1:-$PWD/build-host}
BUILD_DIR_S2=${BUILD_DIR_S2:-$PWD/build-target}
PACKAGE_DIR_BASE=${PACKAGE_DIR:-$PWD/packages}

STAGE1_CFLAGS=()
STAGE1_CPPFLAGS=()
STAGE1_LDFLAGS=()
if [ $HOST_ARCH = x86_64 ]; then
  STAGE1_CFLAGS+=( -march=native )
fi
if [ "$HOST_SYS" = "macos" ]; then
  if [ $HOST_ARCH = x86_64 ]; then
    MAC_TARGET_VERSION=10.15
  else
    MAC_TARGET_VERSION=11.0
  fi
  # -platform_version <platform> <min_version> <sdk_version>
  STAGE1_LDFLAGS+=( -Wl,-platform_version,macos,$MAC_TARGET_VERSION,$MAC_SDK_VERSION )
  STAGE1_CFLAGS+=( "-mmacosx-version-min=$MAC_TARGET_VERSION" )
  STAGE1_CPPFLAGS+=( "-mmacosx-version-min=$MAC_TARGET_VERSION" )
fi


# print configuration
if $VERBOSE || $PRINT_CONFIG; then
  cat << EOF
Configuration:
  TOOLCHAIN_TARGETS ${TOOLCHAIN_TARGETS[*]}
    LLVM_VERSION    $LLVM_VERSION
    PKG_VERSION     $PKG_VERSION
    ZLIB_VERSION    $ZLIB_VERSION
    ZSTD_VERSION    $ZSTD_VERSION
    LIBXML2_VERSION $LIBXML2_VERSION
    NCURSES_VERSION $NCURSES_VERSION
    LIBEDIT_VERSION $LIBEDIT_VERSION
    XZ_VERSION      $XZ_VERSION
  SYSROOT_TARGETS   ${SYSROOT_TARGETS[*]}
    MUSL_VERSION    $MUSL_VERSION
    WASI_GIT_TAG    $WASI_GIT_TAG
  BUILD_DIR_S1      $BUILD_DIR_S1
  BUILD_DIR_S2      $BUILD_DIR_S2
  PATH              $PATH
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

_run_script() { # <script> [<label>]
  local SCRIPT=$1
  local LABEL=${2:-}
  [ -n "$LABEL" ] || LABEL=$SCRIPT
  echo "———————————————————————————— $LABEL ————————————————————————————"
  ( set -euo pipefail; source $SCRIPT )
  echo "——————————————————————————————————————————————————————————————————————"
}

_is_missing() { # <testfile> <script>
  local TESTFILE=$1
  local SCRIPT=$2
  [ ! -e "$TESTFILE" ] || [ $REBUILD_LLVM = true -a "$SCRIPT" = _llvm-stage2.sh ]
}

_run_if_missing() { # <testfile> <script> [<label>]
  local TESTFILE=$1
  local SCRIPT=$2
  local LABEL=${3:-}
  if _is_missing "$TESTFILE" "$SCRIPT"; then
    _run_script "$SCRIPT" "$LABEL"
  else
    return 0
  fi
}

_clang_triple() { # <TARGET>
  # for s1 clang
  case $1 in
    aarch64-macos)   echo arm64-apple-darwin20;; # macOS 11
    x86_64-macos)    echo x86_64-apple-darwin19;; # macOS 10
    wasm*)           echo ${1%%-*}-unknown-wasi;;
    *linux|*playbit) echo ${1%%-*}-unknown-linux-musl;;
    *)               echo $1 ;;
  esac
}

_cc_triples_list() {
  local CC_TRIPLES=()
  local TARGET
  for TARGET in ${SYSROOT_TARGETS[@]}; do
    case "$TARGET" in
      *linux) ;; # shared with *playbit
      *) CC_TRIPLES+=( $(_clang_triple $TARGET) ) ;;
    esac
  done
  _array_join ";" ${CC_TRIPLES[@]}
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
CPPFLAGS=${STAGE1_CPPFLAGS[@]:-}
LDFLAGS=${STAGE1_LDFLAGS[@]:-}
HOST_CC=$CC
HOST_CXX=$CXX
HOST_AR=$AR
HOST_ASM=$ASM
HOST_LD=$LD
HOST_RANLIB=$RANLIB
HOST_CFLAGS=$CFLAGS
HOST_CPPFLAGS=$CPPFLAGS
HOST_LDFLAGS=$LDFLAGS
HOST_TRIPLE=$($CC -print-target-triple)

BUILD_DIR=$BUILD_DIR_S1
mkdir -p "$BUILD_DIR"

# fetch macOS SDK
if [ $HOST_SYS = macos ]; then
  # Note: macOS SDK dir _must_ be named "MacOSX{version}.sdk"
  MAC_SDK=$BUILD_DIR_GENERIC/MacOSX${MAC_SDK_VERSION}.sdk
  export MAC_SDK
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
_run_if_missing "$LLVM_STAGE1_DIR/bin/clang" _llvm-stage1.sh llvm-s1
echo "Using llvm-stage1 at ${LLVM_STAGE1_DIR##$PWD0/}/"
export PATH=$LLVM_STAGE1_DIR/bin:$PATH

# ————————————————————————————————————————————————————————————————————————————
# stage 2

# stage 1 clang will try to include crtbeginS.o & crtendS.o even though musl
# does not use these "CRunTime" files.
mkdir -p "$BUILD_DIR_S2/phony"
touch "$BUILD_DIR_S2/phony/crtbegin.o"
touch "$BUILD_DIR_S2/phony/crtend.o"
touch "$BUILD_DIR_S2/phony/crtbeginS.o"
touch "$BUILD_DIR_S2/phony/crtendS.o"
touch "$BUILD_DIR_S2/phony/crtbeginT.o"
touch "$BUILD_DIR_S2/phony/crtendT.o"

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

GENERIC_CFLAGS="-isystem$LLVM_STAGE1_DIR/include"
GENERIC_LDFLAGS="--rtlib=compiler-rt"
# GENERIC_LDFLAGS="--rtlib=compiler-rt --ld-path=$LLVM_STAGE1_DIR/bin/ld.lld"
HOST_TRIPLE=$($LLVM_STAGE1_DIR/bin/clang -print-target-triple)

S1_CLANGRES_DIR=$(realpath $($LLVM_STAGE1_DIR/bin/clang --print-runtime-dir)/../..)

_setenv_for_target() {
  TARGET=$1
  local CC_TRIPLE=$(_clang_triple $TARGET)
  BUILD_DIR=$BUILD_DIR_S2/$TARGET
  SYSROOT=$BUILD_DIR/sysroot
  CFLAGS="$GENERIC_CFLAGS --target=$CC_TRIPLE --sysroot=$SYSROOT"
  CPPFLAGS="$GENERIC_CFLAGS --target=$CC_TRIPLE --sysroot=$SYSROOT"
  LDFLAGS="$GENERIC_LDFLAGS --target=$CC_TRIPLE --sysroot=$SYSROOT"
  case $TARGET in
    aarch64-macos)   MAC_TARGET_VERSION=11.0 ;;
    x86_64-macos)    MAC_TARGET_VERSION=10.15 ;;
    *linux|*playbit) LDFLAGS="$LDFLAGS -B$BUILD_DIR_S2/phony" ;;
  esac
  case $TARGET in
    *-macos)
      CFLAGS="$CFLAGS -mmacosx-version-min=$MAC_TARGET_VERSION"
      LDFLAGS="$LDFLAGS -Wl,-platform_version,macos,$MAC_TARGET_VERSION,$MAC_SDK_VERSION"
      export MAC_TARGET_VERSION
      ;;
  esac
  export TARGET
  export BUILD_DIR
  export SYSROOT
  export CFLAGS
  export CPPFLAGS
  export LDFLAGS
}

# —————————————————————————————————————————————————————————————————————————————
# setup llvm source for stage 2, which includes our patches
#
# LLVM_SRC_CHANGE_TRACKING_ENABLED: if true, track changes to files in
# LLVM_STAGE2_SRC via git. Slow and uses a lot of disk space but useful when
# working on llvm patches.
LLVM_SRC_CHANGE_TRACKING_ENABLED=true
LLVM_STAGE2_SRC=$BUILD_DIR_GENERIC/s2-llvm-$LLVM_VERSION
if _is_missing "$LLVM_STAGE2_SRC/LICENSE.TXT" _llvm-stage2-source.sh; then
  _run_script _llvm-stage2-source.sh "llvm source"
  touch "$LLVM_STAGE2_SRC/LICENSE.TXT"
else
  # check if patches changed
  CANARY=$LLVM_STAGE2_SRC/LICENSE.TXT
  if [ -f $LLVM_STAGE2_SRC/.git/refs/tags/patch1 ]; then
    CANARY=$LLVM_STAGE2_SRC/.git/refs/tags/patch1
  fi
  echo "Checking for changes to LLVM patches"
  NEWER=$(find "$LLVM_PATCHDIR" -type f -newer "$CANARY")
  if [ -n "$NEWER" ]; then
    if [ -f $LLVM_STAGE2_SRC/.git/refs/tags/patch1 ]; then
      echo "—————————————————————————————————————————————————————" >&2
      echo "LLVM patches changed:" >&2
      echo "$NEWER" >&2
      echo "" >&2
      echo "Please:" >&2
      echo "1. Check for any changes you might have made to LLVM and create or update patches." >&2
      echo "2. Run ./llvm-reapply-patches.sh" >&2
      echo "—————————————————————————————————————————————————————" >&2
      exit 1
    else
      echo "LLVM patches changed"
      _run_script _llvm-stage2-source.sh "llvm source"
      touch "$LLVM_STAGE2_SRC/LICENSE.TXT"
    fi
  fi
fi
echo "Using llvm source at ${LLVM_STAGE1_SRC##$PWD0/}"

# —————————————————————————————————————————————————————————————————————————————
BASE_CFLAGS=$CFLAGS
BASE_LDFLAGS=$LDFLAGS

for TARGET in ${SYSROOT_TARGETS[@]}; do
  echo "~~~~~~~~~~~~~~~~~~~~ sysroot $TARGET ~~~~~~~~~~~~~~~~~~~~"
  _setenv_for_target $TARGET
  CFLAGS="$CFLAGS -isystem$SYSROOT/usr/include"
  CFLAGS="$CFLAGS -isystem$S1_CLANGRES_DIR/include"  # compiler headers (e.g. stdint.h)
  CFLAGS_NOLTO=$CFLAGS
  BUILTINS_DIR=$BUILD_DIR/builtins
  BUILTINS_DIR_FOR_S1_CC=$BUILD_DIR/builtins-for-s1-cc

  # system headers
  case "$TARGET" in
  *wasi|wasm*playbit)
    _run_if_missing "$SYSROOT/usr/include/stdlib.h" _wasi.sh
    ;;
  *linux|*playbit)
    _run_if_missing "$SYSROOT/usr/include/linux/version.h" _linux-headers.sh
    MUSL_ONLY_INSTALL_HEADERS=1
    _run_if_missing "$SYSROOT/usr/include/stdlib.h" _musl.sh
    MUSL_ONLY_INSTALL_HEADERS=
    ;;
  *macos)
    _run_if_missing "$SYSROOT/usr/include/stdlib.h" _macos-sdk.sh
    ;;
  esac

  # builtins
  _run_if_missing "$BUILTINS_DIR/lib/libclang_rt.builtins.a" _builtins.sh
  echo "Using builtins.a at ${BUILTINS_DIR##$PWD0/}"
  CFLAGS="$CFLAGS -resource-dir=$BUILTINS_DIR_FOR_S1_CC/"
  LDFLAGS="$LDFLAGS -resource-dir=$BUILTINS_DIR_FOR_S1_CC/"

  # libc (musl needs builtins)
  case "$TARGET" in
  *wasi|wasm*playbit)
    ;;
  *linux|*playbit)
    _run_if_missing "$SYSROOT/lib/libc.a" _musl.sh
    ;;
  esac

  $ENABLE_LTO && CFLAGS="$CFLAGS -flto=thin"

  # libc++
  LIBCXX_DIR=$BUILD_DIR/libcxx
  _run_if_missing "$LIBCXX_DIR/lib/libc++.a" _libcxx.sh
  echo "Using libc++.a at ${LIBCXX_DIR##$PWD0/}"
  # CFLAGS="$CFLAGS -I$LIBCXX_DIR/usr/include/c++/v1 -I$LIBCXX_DIR/usr/include"
  # CXXFLAGS="$CFLAGS -I$LIBCXX_DIR/usr/include/c++/v1 -I$LIBCXX_DIR/usr/include"
  LDFLAGS="$LDFLAGS -L$LIBCXX_DIR/lib" # for libunwind

  # libBlocksRuntime
  BLOCKSRUNTIME_DIR=$BUILD_DIR/blocks-runtime
  _run_if_missing "$BLOCKSRUNTIME_DIR/lib/libBlocksRuntime.a" _blocks-runtime.sh
  echo "Using libBlocksRuntime.a at ${BLOCKSRUNTIME_DIR##$PWD0/}/"

  # disable LTO for compiler-rt
  CFLAGS=$CFLAGS_NOLTO

  # the rest of this loop body is for building compiler-rt

  # compiler-rt (excluding builtins, which we built earlier)
  # compiler-rt's cmake setup requires a configured general LLVM, so we need
  # to build all llvm prerequisites and then configure llvm.
  COMPILER_RT_DIR=$BUILD_DIR/compiler-rt
  case $TARGET in
    *macos) CANARY="$COMPILER_RT_DIR/lib/libclang_rt.asan_abi_osx.a" ;;
    *)      CANARY="$COMPILER_RT_DIR/lib/libclang_rt.asan.a" ;;
  esac
  # Skip compiler-rt for wasm targets and skip already-built compiler-rt
  if [[ $TARGET == wasm* ]] || [ -e "$CANARY" -a "$CANARY" -nt _compiler-rt.sh ]; then
    continue
  fi

  if $ENABLE_LTO; then
    CFLAGS="$CFLAGS -flto=thin"
    if ! $LLVM_ENABLE_STATIC_LINKING; then
      # all these supporting libs must be built with -fPIC when LTO is enabled
      # Also set default optimization level
      CFLAGS="$CFLAGS -fPIC"
    fi
  fi

  # zlib
  ZLIB_DIR=$BUILD_DIR/zlib
  _run_if_missing "$ZLIB_DIR/lib/libz.a" _zlib.sh
  echo "Using libz.a at ${ZLIB_DIR##$PWD0/}/"

  # zstd
  ZSTD_DIR=$BUILD_DIR/zstd
  _run_if_missing "$ZSTD_DIR/lib/libzstd.a" _zstd.sh
  echo "Using libzstd.a at ${ZSTD_DIR##$PWD0/}/"

  # libxml2
  LIBXML2_DIR=$BUILD_DIR/libxml2
  _run_if_missing "$LIBXML2_DIR/lib/libxml2.a" _libxml2.sh
  echo "Using libxml2.a at ${LIBXML2_DIR##$PWD0/}/"

  # ncurses
  NCURSES_DIR=$BUILD_DIR/ncurses
  _run_if_missing "$NCURSES_DIR/lib/libncurses.a" _ncurses.sh
  echo "Using libncurses.a at ${NCURSES_DIR##$PWD0/}/"

  # libedit
  LIBEDIT_DIR=$BUILD_DIR/libedit
  _run_if_missing "$LIBEDIT_DIR/lib/libedit.a" _libedit.sh
  echo "Using libedit.a at ${LIBEDIT_DIR##$PWD0/}/"

  # xz
  XZ_DIR=$BUILD_DIR/xz
  _run_if_missing "$XZ_DIR/lib/liblzma.a" _xz.sh
  echo "Using liblzma.a at ${XZ_DIR##$PWD0/}/"

  LLVM_STAGE2_DIR=$BUILD_DIR/llvm
  ( LLVM_STAGE2_ONLY_CONFIGURE=1
    echo "—————— configuring llvm stage2 for compiler-rt ——————"
    source _llvm-stage2.sh )

  _run_script _compiler-rt.sh "compiler-rt $TARGET"
  echo "Using compiler-rt at ${COMPILER_RT_DIR##$PWD0/}/lib/"
done



for TARGET in ${TOOLCHAIN_TARGETS[@]}; do
  echo "~~~~~~~~~~~~~~~~~~~~ toolchain $TARGET ~~~~~~~~~~~~~~~~~~~~"
  _setenv_for_target $TARGET
  CFLAGS="$CFLAGS -isystem$S1_CLANGRES_DIR/include"  # compiler headers (e.g. stdint.h)
  $ENABLE_LTO && CFLAGS="$CFLAGS -flto=thin"

  BUILTINS_DIR=$BUILD_DIR/builtins
  BUILTINS_DIR_FOR_S1_CC=$BUILD_DIR/builtins-for-s1-cc
  LIBCXX_DIR=$BUILD_DIR/libcxx
  COMPILER_RT_DIR=$BUILD_DIR/compiler-rt
  BLOCKSRUNTIME_DIR=$BUILD_DIR/blocks-runtime

  CFLAGS="$CFLAGS -resource-dir=$BUILTINS_DIR_FOR_S1_CC/"
  LDFLAGS="$LDFLAGS -resource-dir=$BUILTINS_DIR_FOR_S1_CC/"
  LDFLAGS="$LDFLAGS -L$LIBCXX_DIR/lib" # for libunwind

  CFLAGS_TOOLS_SAVE=$CFLAGS
  if ! $LLVM_ENABLE_STATIC_LINKING && $ENABLE_LTO; then
    # all these supporting libs must be built with -fPIC when LTO is enabled
    # Also set default optimization level
    CFLAGS="$CFLAGS -O2 -fPIC"
  fi

  ZLIB_DIR=$BUILD_DIR/zlib
  ZSTD_DIR=$BUILD_DIR/zstd
  LIBXML2_DIR=$BUILD_DIR/libxml2
  NCURSES_DIR=$BUILD_DIR/ncurses
  LIBEDIT_DIR=$BUILD_DIR/libedit
  XZ_DIR=$BUILD_DIR/xz

  # ARCH-linux shares most parts with ARCH-playbit
  if [[ "$TARGET" == *linux ]]; then
    ARCH=${TARGET%%-*}
    mkdir -p "$BUILD_DIR"
    for dir in \
      builtins \
      builtins-for-s1-cc \
      blocks-runtime \
      sysroot \
      compiler-rt \
      libcxx \
      zlib \
      zstd \
      libxml2 \
      ncurses \
      libedit \
      xz \
    ;do
      rm -f "$BUILD_DIR/$dir"
      ln -s "../$ARCH-playbit/$dir" "$BUILD_DIR/$dir"
    done
  else
    # zlib
    _run_if_missing "$ZLIB_DIR/lib/libz.a" _zlib.sh
    echo "Using libz.a at ${ZLIB_DIR##$PWD0/}/"

    # zstd
    _run_if_missing "$ZSTD_DIR/lib/libzstd.a" _zstd.sh
    echo "Using libzstd.a at ${ZSTD_DIR##$PWD0/}/"

    # libxml2
    _run_if_missing "$LIBXML2_DIR/lib/libxml2.a" _libxml2.sh
    echo "Using libxml2.a at ${LIBXML2_DIR##$PWD0/}/"

    # ncurses
    _run_if_missing "$NCURSES_DIR/lib/libncurses.a" _ncurses.sh
    echo "Using libncurses.a at ${NCURSES_DIR##$PWD0/}/"

    # libedit
    _run_if_missing "$LIBEDIT_DIR/lib/libedit.a" _libedit.sh
    echo "Using libedit.a at ${LIBEDIT_DIR##$PWD0/}/"

    # xz
    _run_if_missing "$XZ_DIR/lib/liblzma.a" _xz.sh
    echo "Using liblzma.a at ${XZ_DIR##$PWD0/}/"
  fi

  # restore CFLAGS
  CFLAGS=$CFLAGS_TOOLS_SAVE

  # llvm (stage 2; for target, not host)
  LLVM_STAGE2_DIR=$BUILD_DIR/llvm
  _run_if_missing "$LLVM_STAGE2_DIR/bin/clang" _llvm-stage2.sh
  echo "Using llvm-stage2 at ${LLVM_STAGE2_DIR##$PWD0/}/"

  # binaryen
  BINARYEN_DIR=$BUILD_DIR/binaryen
  _run_if_missing "$BINARYEN_DIR/bin/wasm-opt" _binaryen.sh
  echo "Using binaryen at ${BINARYEN_DIR##$PWD0/}/"
done
CFLAGS=$BASE_CFLAGS
LDFLAGS=$BASE_LDFLAGS

[ -n "${PB_LLVM_STOP_AFTER_BUILD:-}" ] && exit 0

# ——————————————————————————————————————————————————————————————————————————————
# step 3: package
if $NO_PACKAGE; then
  exit 0
fi

_cpmerge() {
  echo "copy <projectroot>/${1##$PWD0/} -> $2"
  $TOOLS/cpmerge -v "$@" >> "$BUILD_DIR/package-$PKGNAME.log"
  # mkdir -p "$(dirname "$2")"
  # cp -RpT "$1" "$2" >> "$BUILD_DIR/package-$PKGNAME.log"
}

_create_package() { # <package-name> <script>
  local PKGNAME=$1
  local SCRIPT=$PWD/$2

  _setenv_for_target $TARGET

  BUILTINS_DIR=$BUILD_DIR/builtins
  COMPILER_RT_DIR=$BUILD_DIR/compiler-rt
  BLOCKSRUNTIME_DIR=$BUILD_DIR/blocks-runtime
  BINARYEN_DIR=$BUILD_DIR/binaryen
  LIBCXX_DIR=$BUILD_DIR/libcxx
  LIBEDIT_DIR=$BUILD_DIR/libedit
  LIBXML2_DIR=$BUILD_DIR/libxml2
  LLVM_STAGE2_DIR=$BUILD_DIR/llvm
  NCURSES_DIR=$BUILD_DIR/ncurses
  XZ_DIR=$BUILD_DIR/xz
  ZLIB_DIR=$BUILD_DIR/zlib
  ZSTD_DIR=$BUILD_DIR/zstd

  PACKAGE_TARGET=$TARGET
  PACKAGE_DIR=$PACKAGE_DIR_BASE/$PKGNAME-$PACKAGE_TARGET
  PACKAGE_ARCHIVE=$PACKAGE_DIR_BASE/llvm-$LLVM_VERSION-$PKG_VERSION-$PKGNAME-$PACKAGE_TARGET.tar.xz

  echo "~~~~~~~~~~~~~~~~~~~~ package $PKGNAME-$PACKAGE_TARGET ~~~~~~~~~~~~~~~~~~~~"
  rm -f "$BUILD_DIR/package-$PKGNAME.log"

  rm -rf "$PACKAGE_DIR"
  mkdir -p "$PACKAGE_DIR"
  _pushd "$PACKAGE_DIR"

  if [ $PKGNAME != toolchain ]; then
    # for all packages but toolchain, prefix with sysroot/SYS/ARCH (included in tar)
    local arch sys
    IFS=- read -r arch sys <<< "$TARGET"
    if [ $sys = playbit ]; then
      mkdir -p sysroot/$arch
      _pushd sysroot/$arch
    else
      mkdir -p sysroot/$sys/$arch
      _pushd sysroot/$sys/$arch
    fi
  fi

  set -euo pipefail; source "$SCRIPT"

  # remove empty directories
  find . -type d -empty -delete

  if [ $PKGNAME != toolchain ]; then
    _popd
  fi

  if $NO_ARCHIVE; then
    return 0
  fi

  echo "Creating ${PACKAGE_ARCHIVE##$PWD0/}"
  COPYFILE_DISABLE=1 tar -c --no-xattrs --exclude='._*' . \
  | xz --compress -F xz -$XZ_COMPRESSION_RATIO --stdout --threads=0 \
  > "$PACKAGE_ARCHIVE"
}

# make sure cpmerge is available
tools/build.sh
TOOLS=$PWD/tools
export TOOLS

for TARGET in ${TOOLCHAIN_TARGETS[@]}; do
  (_create_package toolchain _package-toolchain.sh)
  if $ENABLE_LLVM_DEV_FILES; then
    (_create_package llvmdev _package-llvmdev.sh)
  fi
done
for TARGET in ${SYSROOT_TARGETS[@]}; do
  (_create_package compiler-rt _package-compiler-rt.sh)
  (_create_package libcxx _package-libcxx.sh)
  (_create_package sysroot _package-sysroot.sh)
done

# create local test dir for native toolchain
NATIVE_TOOLCHAIN=
if ! $NO_NATIVE_TOOLCHAIN; then
  for TARGET in ${TOOLCHAIN_TARGETS[@]}; do
    [ $TARGET = "$HOST_ARCH-$HOST_SYS" ] || continue
    echo "~~~~~~~~~~~~~~~~~~~~ setup native toolchain ~~~~~~~~~~~~~~~~~~~~"
    unset _cpmerge
    _cpmerge() {
      echo "cpmerge ${1##$PWD0/} -> ${2##$PWD0/}"
      $TOOLS/cpmerge "$@"
    }
    TOOLS_DIR=$PACKAGE_DIR_BASE/toolchain-$TARGET
    NATIVE_TOOLCHAIN=$PACKAGE_DIR_BASE/toolchain
    rm -rf "$NATIVE_TOOLCHAIN"
    echo "copy ${TOOLS_DIR##$PWD0/}/ -> ${NATIVE_TOOLCHAIN##$PWD0/}/"
    cp -a "$TOOLS_DIR" "$NATIVE_TOOLCHAIN"
    for TARGET in ${SYSROOT_TARGETS[@]}; do
      IFS=- read -r arch sys <<< "$TARGET"
      if [ $sys = playbit ]; then
        SUFFIX=/sysroot/$arch
      else
        SUFFIX=/sysroot/$sys/$arch
      fi
      DSTDIR=$NATIVE_TOOLCHAIN$SUFFIX
      mkdir -p "$DSTDIR"
      # note: must copy sysroot first since macos sysroot contains symlinks to usr
      _cpmerge $PACKAGE_DIR_BASE/sysroot-$TARGET$SUFFIX     "$DSTDIR"
      _cpmerge $PACKAGE_DIR_BASE/compiler-rt-$TARGET$SUFFIX "$DSTDIR"
      _cpmerge $PACKAGE_DIR_BASE/libcxx-$TARGET$SUFFIX      "$DSTDIR"
    done
  done
fi

# test native toolchain
if [ -n "$NATIVE_TOOLCHAIN" ]; then
  echo "~~~~~~~~~~~~~~~~~~~~ test native toolchain ~~~~~~~~~~~~~~~~~~~~"
  _test_cc() {
    echo "${NATIVE_TOOLCHAIN##$PWD0/}/bin/clang $@"
    "$NATIVE_TOOLCHAIN/bin/clang" "$@"
  }
  _test_cxx() {
    echo "${NATIVE_TOOLCHAIN##$PWD0/}/bin/clang++ $@"
    "$NATIVE_TOOLCHAIN/bin/clang++" "$@"
  }
  for TARGET in ${SYSROOT_TARGETS[@]}; do
    case $TARGET in
      *playbit) CC_TRIPLE=$TARGET;;
      *)        CC_TRIPLE=$(_clang_triple $TARGET);;
    esac
    _test_cc --target=$CC_TRIPLE hello.c -o hello_c_$TARGET
    _test_cxx --target=$CC_TRIPLE hello.cc -o hello_cc_$TARGET
    set +x
  done
fi

if ! $NO_ARCHIVE; then
  echo
  echo "You can upload the archives to files.playb.it: ./upload-packages.sh"
fi
