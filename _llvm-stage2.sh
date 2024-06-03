SELF_SCRIPT=$(realpath "${BASH_SOURCE[0]}")
BUILD_DIR=$LLVM_STAGE2_DIR-build
DESTDIR=$LLVM_STAGE2_DIR

# ENABLE_LLVM_DEV_FILES=true -- set in build.sh
ENABLE_STATIC_LINKING=$LLVM_ENABLE_STATIC_LINKING
ENABLE_LLDB=true

if [[ $TARGET == *macos* ]]; then
  # enable static linking for macos for now since I can't figure out why:
  #   ld64.lld: error: undefined symbol: __cxa_thread_atexit_impl
  # even though we link with -lc++abi
  ENABLE_STATIC_LINKING=true
  # don't build lldb
  ENABLE_LLDB=false
fi

DIST_COMPONENTS=(
  clang \
  clang-format \
  clang-resource-headers \
  lld \
  dsymutil \
  llvm-ar \
  llvm-as \
  llvm-config \
  llvm-cov \
  llvm-dlltool \
  llvm-dwarfdump \
  llvm-nm \
  llvm-objcopy \
  llvm-objdump \
  llvm-otool \
  llvm-profdata \
  llvm-ranlib \
  llvm-rc \
  llvm-readobj \
  llvm-size \
  llvm-strings \
  llvm-strip \
  llvm-symbolizer \
  llvm-tblgen \
  llvm-xray \
  llvm-libtool-darwin \
  llvm-lipo \
)
if $ENABLE_LLDB; then
  DIST_COMPONENTS+=( lldb lldb-server liblldb )
fi
# components without install targets
EXTRA_COMPONENTS=()
EXTRA_COMPONENTS+=( clang-tblgen )
if $ENABLE_LLVM_DEV_FILES; then
  DIST_COMPONENTS+=(
    clang-headers \
    clang-libraries \
    llvm-headers \
    llvm-libraries \
  )
  EXTRA_COMPONENTS+=(
    lib/liblldCOFF.a \
    lib/liblldCommon.a \
    lib/liblldELF.a \
    lib/liblldMachO.a \
    lib/liblldMinGW.a \
    lib/liblldWasm.a \
  )
fi

CMAKE_C_FLAGS=( \
  $CFLAGS \
  -Wno-unused-command-line-argument \
)

# Note: We have to provide search path to sysroot headers after libc++ headers
# for include_next to function properly. Additionally, we must (later) make sure
# that CMAKE_CXX_FLAGS preceeds CFLAGS for C++ compilation, so that e.g.
# include <stdlib.h> loads c++/v1/stdlib.h (and then sysroot/usr/include/stdlib.h)
CMAKE_CXX_FLAGS=( \
  "-I$LIBCXX_DIR/usr/include/c++/v1" \
  "-I$LIBCXX_DIR/usr/include" \
  "-isystem$SYSROOT/usr/include" \
)
CMAKE_LD_FLAGS=( $LDFLAGS -L$LIBCXX_DIR/lib -lc++abi )
EXTRA_CMAKE_ARGS=( -Wno-dev )


if $ENABLE_STATIC_LINKING; then
  EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_PIC=OFF )
  EXTRA_CMAKE_ARGS+=( -DLLVM_BUILD_LLVM_DYLIB=OFF )
else
  EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_PIC=ON )
  EXTRA_CMAKE_ARGS+=( -DLLVM_LINK_LLVM_DYLIB=ON )
  EXTRA_CMAKE_ARGS+=( -DLLVM_BUILD_LLVM_DYLIB=ON )
  EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_PLUGINS=OFF )
fi

case $TARGET in
  *linux|*playbit|wasm*)
    if $ENABLE_STATIC_LINKING; then
      CMAKE_C_FLAGS+=( -static )
      CMAKE_LD_FLAGS+=( -static )
    elif [[ $TARGET == *playbit ]]; then
      CMAKE_LD_FLAGS+=( "-Wl,-dynamic-linker,/lib/ld.so.1" )
    fi
    ;;
  *macos*)
    EXTRA_CMAKE_ARGS+=( \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$MAC_TARGET_VERSION \
      -DCMAKE_OSX_SYSROOT="$SYSROOT" \
      -DCMAKE_LIBTOOL="$LIBTOOL" \
    )
    case $TARGET in
      x86_64*)  EXTRA_CMAKE_ARGS+=( -DCMAKE_OSX_ARCHITECTURES=x86_64 ) ;;
      aarch64*) EXTRA_CMAKE_ARGS+=( -DCMAKE_OSX_ARCHITECTURES=arm64 ) ;;
    esac
    ;;
esac


# LLDB does not use <NAME>_LIBRARY or <NAME>_INCLUDE_DIR vars, so we need to set FLAGS
CMAKE_C_FLAGS+=( -I$ZLIB_DIR/include )
CMAKE_LD_FLAGS+=( -L$ZLIB_DIR/lib )

CMAKE_C_FLAGS+=( -I$ZSTD_DIR/include )
CMAKE_LD_FLAGS+=( -L$ZSTD_DIR/lib )

CMAKE_C_FLAGS+=( -I$LIBXML2_DIR/include/libxml2 )
CMAKE_LD_FLAGS+=( -L$LIBXML2_DIR/lib )

CMAKE_C_FLAGS+=( "-I$NCURSES_DIR/include" "-I$NCURSES_DIR/include/ncursesw" )
CMAKE_LD_FLAGS+=( "-L$NCURSES_DIR/lib" )

CMAKE_C_FLAGS+=( "-I$LIBEDIT_DIR/include" )
CMAKE_LD_FLAGS+=( "-L$LIBEDIT_DIR/lib" )

CMAKE_C_FLAGS+=( "-I$XZ_DIR/include" )
CMAKE_LD_FLAGS+=( "-L$XZ_DIR/lib" )

if $ENABLE_LLDB; then
  EXTRA_CMAKE_ARGS+=(
    -DLLDB_ENABLE_LIBXML2=ON \
    \
    -DLLDB_ENABLE_CURSES=ON \
    -DCURSES_INCLUDE_DIRS="$NCURSES_DIR/include" \
    -DCURSES_LIBRARIES="$NCURSES_DIR/lib/libncursesw.a" \
    -DPANEL_LIBRARIES="$NCURSES_DIR/lib/libpanelw.a" \
    \
    -DLLDB_ENABLE_LIBEDIT=ON \
    -DLibEdit_INCLUDE_DIRS="$LIBEDIT_DIR/include" \
    -DLibEdit_LIBRARIES="$LIBEDIT_DIR/lib/libedit.a" \
    \
    -DLLDB_ENABLE_LZMA=ON \
    -DLIBLZMA_INCLUDE_DIR="$XZ_DIR/include" \
    -DLIBLZMA_LIBRARY="$XZ_DIR/lib/liblzma.a" \
    -DLIBLZMA_HAS_AUTO_DECODER=YES \
    -DLIBLZMA_HAS_EASY_ENCODER=YES \
    -DLIBLZMA_HAS_LZMA_PRESET=YES \
    \
    -DLLDB_ENABLE_SWIG=OFF \
    -DLLDB_ENABLE_LUA=OFF \
    -DLLDB_ENABLE_FBSDVMCORE=OFF \
  )
fi

EXTRA_CMAKE_ARGS+=(
  -DLLVM_ENABLE_TERMINFO=ON \
  -DTerminfo_LIBRARIES="$NCURSES_DIR/lib/libncursesw.a" \
  -DLLVM_ENABLE_LIBEDIT=ON \
)

# this needs to be set even when ENABLE_LLDB=false
EXTRA_CMAKE_ARGS+=( -DLLDB_ENABLE_PYTHON=OFF )

# note: these are clang-specific option, even though it doesn't start with CLANG_
# See: llvm/clang/CMakeLists.txt
#
# DEFAULT_SYSROOT sets the default --sysroot=<path>.
# Note that if sysroot is relative, clang will treat it as relative to itself.
# I.e. sysroot=foo with clang at /bin/clang results in sysroot=/bin/foo.
# See line ~200 of clang/lib/Driver/Driver.cpp
EXTRA_CMAKE_ARGS+=( -DDEFAULT_SYSROOT="" )
# EXTRA_CMAKE_ARGS+=( -DDEFAULT_SYSROOT="../sysroot-${TARGET%%-*}/" )
#
# C_INCLUDE_DIRS is a colon-separated list of paths to search by default.
# Relative paths are relative to sysroot.
# The user can pass -nostdlibinc to disable searching of these paths.
# See line ~600 of clang/lib/Driver/ToolChains/Linux.cpp
#EXTRA_CMAKE_ARGS+=( -DC_INCLUDE_DIRS="include/c++/v1:include" )
EXTRA_CMAKE_ARGS+=( -DC_INCLUDE_DIRS="" )
#
# ENABLE_LINKER_BUILD_ID causes clang to pass --build-id to ld
EXTRA_CMAKE_ARGS+=( -DENABLE_LINKER_BUILD_ID=ON )

# GENERATOR_IS_MULTI_CONFIG=ON disables generation of ASTNodeAPI.json
# which 1) we don't need, 2) takes a long time, and 3) can't build because the
# tool used to build it will be compiled for the target, not the host.
# See clang/lib/Tooling/CMakeLists.txt
EXTRA_CMAKE_ARGS+=( -DGENERATOR_IS_MULTI_CONFIG=ON )

# LLVM_INSTALL_BINUTILS_SYMLINKS create symlinks that match binutils (nm ar etc)
#EXTRA_CMAKE_ARGS+=( -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON )

# LLVM_INSTALL_TOOLCHAIN_ONLY: Only include toolchain files in the 'install' target
# EXTRA_CMAKE_ARGS+=( -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON )

# CLANG_RESOURCE_DIR: /lib/clang/VERSION by default
EXTRA_CMAKE_ARGS+=( -DCLANG_RESOURCE_DIR=../lib/clang )

# CLANG_REPOSITORY_STRING: set to "" to disable inclusion of git information
# in "clang --version"
EXTRA_CMAKE_ARGS+=( -DCLANG_REPOSITORY_STRING= )

if $ENABLE_LTO; then
  EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_LTO=Thin )
  # enable LTO cache when hacking on llvm, else link times will be very long
  if $LLVM_SRC_CHANGE_TRACKING_ENABLED; then
    case $TARGET in
      *linux|*playbit|*wasm*) # ld.lld, wasm-ld
        CMAKE_LD_FLAGS+=( -Wl,--thinlto-cache-dir="'$BUILD_DIR/lto-cache'" ) ;;
      *macos*) # ld64.lld
        CMAKE_LD_FLAGS+=( -Wl,-cache_path_lto,"'$BUILD_DIR/lto-cache'" ) ;;
    esac
  fi
fi

case "$HOST_SYS" in
  linux) EXTRA_CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Linux ) ;;
  macos) EXTRA_CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Darwin ) ;;
esac
case "$TARGET" in
  *linux|*playbit) EXTRA_CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Linux ) ;;
  *macos*)         EXTRA_CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Darwin ) ;;
esac

# This is a hack!
# llvm's cmake files checks if this is ON, and if it is, llvm will attempt
# to build a "native" (host) version of itself, which will fail.
EXTRA_CMAKE_ARGS+=( -DCMAKE_CROSSCOMPILING=OFF )

EXTRA_CMAKE_ARGS+=(
  -DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON \
  -DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON \
)

case "$TARGET" in
  *playbit) DEFAULT_TARGET_TRIPLE=${TARGET%%-*}-unknown-playbit ;;
  *)        DEFAULT_TARGET_TRIPLE=$(_clang_triple $TARGET) ;;
esac
EXTRA_CMAKE_ARGS+=( -DLLVM_DEFAULT_TARGET_TRIPLE=$DEFAULT_TARGET_TRIPLE )

if [[ $TARGET == *macos ]]; then
  EXTRA_CMAKE_ARGS+=( -DCLANG_DEFAULT_LINKER=lld )
else
  EXTRA_CMAKE_ARGS+=( -DCLANG_DEFAULT_LINKER= )
fi

CMAKE_LD_FLAGS+=( -L"$SYSROOT/lib" )
# CMAKE_LD_FLAGS+=( -L"$LIBCXX_STAGE2/lib" )

# LLVM_ENABLE_ASSERTIONS: Enable assertions (default: ON in Debug mode, else OFF)
#EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_ASSERTIONS=ON )

# LLVM_ENABLE_BACKTRACES: Enable embedding backtraces on crash. (default: ON)
#EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_BACKTRACES=OFF )

# LLVM_INCLUDE_DOCS: Generate build targets for llvm documentation. (default: ON)
# Note: CLANG_INCLUDE_DOCS defaults to LLVM_INCLUDE_DOCS
EXTRA_CMAKE_ARGS+=( -DLLVM_INCLUDE_DOCS=OFF )

EXTRA_CMAKE_ARGS+=( -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON )

case "$TARGET" in
  aarch64-macos)
    CMAKE_C_FLAGS+=( -mcpu=apple-m1 )
    ;;
  x86_64*)
    # -march=x86-64    CMOV, CMPXCHG8B, FPU, FXSR, MMX, FXSR, SCE, SSE, SSE2
    # -march=x86-64-v2 (close to Nehalem, ~2008) CMPXCHG16B, LAHF-SAHF, POPCNT,
    #                  SSE3, SSE4.1, SSE4.2, SSSE3
    # -march=x86-64-v3 (close to Haswell ~2013) AVX, AVX2, BMI1, BMI2, F16C, FMA,
    #                  LZCNT, MOVBE, XSAVE
    # -march=x86-64-v4 AVX512F, AVX512BW, AVX512CD, AVX512DQ, AVX512VL
    CMAKE_C_FLAGS+=( -march=x86-64-v2 )
    ;;
esac

LLVM_TARGETS_TO_BUILD=( AArch64 X86 WebAssembly )

# bake flags (array -> string)
CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS[@]:-} ${CMAKE_C_FLAGS[@]:-}"
CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

mkdir -p "$BUILD_DIR"
_pushd "$BUILD_DIR"

if [ -z "${PB_LLVM_SKIP_CONFIG:-}" ] &&
   [ ! -f configured.ok -o \
     ! -f build.ninja -o \
     "$SELF_SCRIPT" -nt configured.ok ]
then
  if [ -f configured.ok ]; then
    echo "configured.ok: 1"; else echo "configured.ok: 0"; fi
  if [ -f build.ninja ]; then
    echo "build.ninja: 1"; else echo "build.ninja: 0"; fi
  if [ "$SELF_SCRIPT" -nt CMakeCache.txt ]; then
    echo "$SELF_SCRIPT -nt CMakeCache.txt: 1"
  else echo "$SELF_SCRIPT -nt CMakeCache.txt: 0"; fi

# [hacking] --fresh: re-configure from scratch.
# This only works for the top-level cmake invocation; does not apply to sub-invocations
# like builtins or runtimes. For a fresh setup of runtimes or builtins:
#   rm -rf build-target/llvm-x86_64-linux-build/runtimes \
#          build-target/llvm-x86_64-linux-build/projects/runtimes* \
#          build-target/llvm-x86_64-linux-build/projects/builtins*
#
# EXTRA_CMAKE_ARGS+=( --fresh )

if $ENABLE_LLDB; then
  LLVM_ENABLE_PROJECTS="clang;lld;lldb"
  EXTRA_CMAKE_ARGS+=( -DLLDB_TABLEGEN_EXE="$LLVM_STAGE1_DIR/bin/lldb-tblgen" )
else
  LLVM_ENABLE_PROJECTS="clang;lld"
fi

cmake -G Ninja "$LLVM_STAGE2_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX= \
  -DLLVM_NATIVE_TOOL_DIR="$LLVM_STAGE1_DIR/bin" \
  \
  -DCMAKE_ASM_COMPILER="$CC" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_AR="$AR" \
  -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_LINKER="$LD" \
  \
  -DCMAKE_ASM_FLAGS="$CFLAGS" \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DCMAKE_SYSROOT="$SYSROOT" \
  \
  -DLLVM_TARGETS_TO_BUILD="$(_array_join ";" "${LLVM_TARGETS_TO_BUILD[@]}")" \
  -DLLVM_ENABLE_PROJECTS="$LLVM_ENABLE_PROJECTS" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${DIST_COMPONENTS[@]}")" \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_INCLUDE_UTILS=OFF -DLLVM_BUILD_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_TOOLS=ON \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_BUILD_LLVM_C_DYLIB=OFF \
  \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=ON \
  -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
  -DCLANG_DEFAULT_RTLIB=compiler-rt \
  -DCLANG_DEFAULT_UNWINDLIB=libunwind \
  -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
  -DCLANG_PLUGIN_SUPPORT=OFF \
  -DCLANG_VENDOR=Playbit \
  -DLIBCLANG_BUILD_STATIC=ON \
  \
  -DLLVM_TABLEGEN="$LLVM_STAGE1_DIR/bin/llvm-tblgen" \
  -DCLANG_TABLEGEN="$LLVM_STAGE1_DIR/bin/clang-tblgen" \
  \
  -DLLVM_ENABLE_ZLIB=FORCE_ON \
  -DZLIB_LIBRARY="$ZLIB_DIR/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_DIR/include" \
  -DHAVE_ZLIB=ON \
  \
  -DLLVM_ENABLE_ZSTD=FORCE_ON \
  -DLLVM_USE_STATIC_ZSTD=TRUE \
  -Dzstd_LIBRARY="$ZSTD_DIR/lib/libzstd.a" \
  -Dzstd_INCLUDE_DIR="$ZSTD_DIR/include" \
  \
  -DLLVM_ENABLE_LIBXML2=FORCE_ON \
  -DLIBXML2_LIBRARY="$LIBXML2_DIR/lib/libxml2.a" \
  -DLIBXML2_INCLUDE_DIR="$LIBXML2_DIR/include/libxml2" \
  -DHAVE_LIBXML2=ON \
  \
  -DLLVM_HAVE_LIBXAR=0 \
  \
  "${EXTRA_CMAKE_ARGS[@]:-}"

touch configured.ok

fi


# fix an issue with llvm's cmake files trying to alter the RPATH in executables
# during installation, which will fail with error
#   "No valid ELF RPATH or RUNPATH entry exists in the file"
# when linking statically
if $ENABLE_STATIC_LINKING; then
  for f in $(find . -name cmake_install.cmake); do
    sed -E -i '' -e 's/file\(RPATH_CHANGE/message(DEBUG/' $f
  done
fi

if [ -n "${LLVM_STAGE2_ONLY_CONFIGURE:-}" ]; then
  exit 0
fi

echo "———————————————————————— build ————————————————————————"
ninja -j$NCPU distribution ${EXTRA_COMPONENTS[@]:-}


if [ -n "${PB_LLVM_STOP_AFTER_BUILD:-}" ]; then
  exit 0
fi


echo "———————————————————————— install ————————————————————————"
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"
DESTDIR="$DESTDIR" ninja -j$NCPU install-distribution-stripped

# rename clang-VERSION to clang
rm "$DESTDIR/bin/clang"
mv "$DESTDIR/bin/clang-${LLVM_VERSION%%.*}" "$DESTDIR/bin/clang"

# no install target for clang-tblgen
install -vm 0755 bin/clang-tblgen "$DESTDIR/bin/clang-tblgen"

if ! $ENABLE_STATIC_LINKING; then
  mkdir -p "$DESTDIR/lib"
  cp -v -a lib/libLLVM-17.so $DESTDIR/lib/
  cp -v -a lib/libclang*.so* $DESTDIR/lib/
  $STRIP "$(realpath "$DESTDIR/lib/libLLVM-17.so")"
  $STRIP "$(realpath "$DESTDIR/lib/libclang-cpp.so")"
fi

if $ENABLE_LLVM_DEV_FILES; then
  # no install targets for lld libs, so do it ourselves
  mkdir -p "$DESTDIR/lib"
  for f in lib/liblld*.a; do
    install -vm 0644 $f "$DESTDIR/lib/$(basename "$f")"
  done

  # copy lld headers from source (they are not affected by build)
  mkdir -p "$DESTDIR/usr/include"
  cp -av "$LLVM_STAGE2_SRC/lld/include/lld" "$DESTDIR/usr/include/lld"
fi

# create binutils-compatible symlinks
#   ack --type=cmake 'add_llvm_tool_symlink\(' build/s2-llvm-17.0.3 | cat
BINUTILS_SYMLINKS=( # "alias target"
  cc                clang \
  c++               clang \
  ld                lld \
  addr2line         llvm-symbolizer \
  ar                llvm-ar \
  bitcode_strip     llvm-bitcode-strip \
  c++filt           llvm-cxxfilt \
  debuginfod        llvm-debuginfod \
  debuginfod-find   llvm-debuginfod-find \
  dlltool           llvm-ar \
  dwp               llvm-dwp \
  install_name_tool llvm-install-name-tool \
  lipo              llvm-lipo \
  nm                llvm-nm \
  objcopy           llvm-objcopy \
  objdump           llvm-objdump \
  otool             llvm-objdump \
  ranlib            llvm-ar \
  readelf           llvm-readobj \
  size              llvm-size \
  strings           llvm-strings \
  strip             llvm-objcopy \
  windres           llvm-rc \
)
_pushd "$DESTDIR/bin"
for ((i = 0; i < ${#BINUTILS_SYMLINKS[@]}; i += 2)); do
  name=${BINUTILS_SYMLINKS[i]}
  target=${BINUTILS_SYMLINKS[$(( i+1 ))]}
  [ -e $target ] || continue
  _symlink $name $target
done
_popd
