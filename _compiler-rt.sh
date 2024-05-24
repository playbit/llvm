SRCDIR=$LLVM_STAGE2_SRC/compiler-rt
BUILDDIR=$COMPILER_RT_DIR-build
DESTDIR=$COMPILER_RT_DIR

# see https://llvm.org/docs/HowToCrossCompileBuiltinsOnArm.html

C_FLAGS=( -fPIC )
CXX_FLAGS=( -fPIC )
LD_FLAGS=(
  -fuse-ld=lld \
  -B"$BUILD_DIR_S2/phony" \
  -resource-dir="$BUILTINS_DIR_FOR_S1_CC/" \
  -L$LIBCXX_DIR/lib \
)
# LD_FLAGS+=( -Wl,-z,notext )
# LD_FLAGS+=( -fPIC )
CMAKE_ARGS=()

# CMAKE_ARGS+=( -DLLVM_ENABLE_LTO=Thin ); C_FLAGS+=( -flto=thin )
# C_FLAGS+=( -fno-lto )

# C_FLAGS+=( -isystem$LIBCXX_DIR/usr/include )
C_FLAGS+=( -isystem$S1_CLANGRES_DIR/include )
CXX_FLAGS+=(
  "-I$LIBCXX_DIR/usr/include/c++/v1" \
  "-isystem$SYSROOT/usr/include" \
  -isystem$LIBCXX_DIR/usr/include \
  -isystem$S1_CLANGRES_DIR/include \
)

CMAKE_ARGS+=( -DCOMPILER_RT_CXX_LIBRARY=libcxx )

# CMAKE_ARGS+=( -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON )
# CMAKE_ARGS+=( -DCOMPILER_RT_USE_LLVM_UNWINDER=ON )
# CMAKE_ARGS+=( -DCOMPILER_RT_ENABLE_STATIC_UNWINDER=ON )

# see ALL_SANITIZERS in compiler-rt/cmake/config-ix.cmake
SANITIZERS_TO_BUILD=(
  asan \
  tsan \
  asan_abi \
  ubsan_minimal \
  cfi \
)
# SANITIZERS_TO_BUILD+=( scudo_standalone )
case $TARGET in
  *linux|*playbit)
    SANITIZERS_TO_BUILD+=(
      dfsan \
      msan \
      hwasan \
      safestack \
      gwp_asan \
    )
    CMAKE_ARGS+=( -DCMAKE_INSTALL_RPATH="\$ORIGIN/../lib;/lib" )
    CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Linux )
    ;;
  *macos*)
    CMAKE_ARGS+=( \
      -DCMAKE_SYSTEM_NAME=Darwin \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$MAC_TARGET_VERSION \
      -DCMAKE_OSX_SYSROOT=$SYSROOT \
    )
    # COMPILER_RT_OS_DIR: this is a bit of a hack to get compiler-rt libs installed
    # at lib/TARGET instead of the default "lib/darwin"
    # We will move it back to lib/darwin when packaging, since clang's Darwin driver
    # expects rt libs at that location.
    CMAKE_ARGS+=( -DCOMPILER_RT_OS_DIR= )
    case $TARGET in
      aarch64*)
        CMAKE_ARGS+=( -DLLVM_TARGETS_TO_BUILD=AArch64 )
        CMAKE_ARGS+=( -DDARWIN_osx_ARCHS=arm64 )
        ;;
      x86_64*)
        CMAKE_ARGS+=( -DLLVM_TARGETS_TO_BUILD=X86 )
        CMAKE_ARGS+=( -DDARWIN_osx_ARCHS=x86_64 )
        ;;
    esac
    ;;
esac

CMAKE_ARGS+=( -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON )

if [ $HOST_SYS = macos ]; then
  CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Darwin )
else
  CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Linux )
fi

CMAKE_ARGS+=( -DLLVM_CMAKE_DIR="$LLVM_STAGE2_DIR-build" )
# CMAKE_ARGS+=( -DLLVM_PATH="$LLVM_STAGE2_SRC/llvm" )

# CMAKE_ARGS+=( --fresh )
CC_TRIPLE=$(_clang_triple $TARGET)

# fix for broken cmake tests
if [ -e "$SYSROOT/lib/libc.so" ]; then
  mv "$SYSROOT/lib/libc.so" "$SYSROOT/lib/libc-TEMPORARILY-DISABLED.so"
  trap "mv '$SYSROOT/lib/libc-TEMPORARILY-DISABLED.so' '$SYSROOT/lib/libc.so'" EXIT
fi

rm -f "$BUILDDIR/CMakeCache.txt"
mkdir -p "$BUILDDIR"
cmake -G Ninja -S "$LLVM_STAGE2_SRC/compiler-rt" -B "$BUILDDIR" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_SYSROOT="$SYSROOT" \
  -DCMAKE_INSTALL_PREFIX="$DESTDIR" \
  \
  -DCMAKE_AR="$AR" \
  -DCMAKE_NM="$LLVM_STAGE1_DIR/bin/llvm-nm" \
  -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CC" \
  -DCMAKE_LIBTOOL="$LIBTOOL" \
  \
  -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
  -DLLVM_BUILTIN_TARGETS="$(_cc_triples_list ${SYSROOT_TARGETS[@]})" \
  \
  -DCMAKE_ASM_COMPILER_TARGET="$CC_TRIPLE" \
  -DCMAKE_ASM_FLAGS="${C_FLAGS[*]}" \
  \
  -DCMAKE_C_COMPILER_TARGET="$CC_TRIPLE" \
  -DCMAKE_C_FLAGS="${C_FLAGS[*]}" \
  \
  -DCMAKE_CXX_COMPILER_TARGET="$CC_TRIPLE" \
  -DCMAKE_CXX_FLAGS="${CXX_FLAGS[*]}" \
  \
  -DCMAKE_EXE_LINKER_FLAGS="${LD_FLAGS[*]}" \
  -DCMAKE_SHARED_LINKER_FLAGS="${LD_FLAGS[*]}" \
  -DCMAKE_MODULE_LINKER_FLAGS="${LD_FLAGS[*]}" \
  \
  -DCOMPILER_RT_BUILD_BUILTINS=OFF \
  -DCOMPILER_RT_BUILD_SANITIZERS=ON \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_BUILD_MEMPROF=OFF \
  -DCOMPILER_RT_BUILD_PROFILE=OFF \
  -DCOMPILER_RT_BUILD_XRAY=OFF \
  -DCOMPILER_RT_BUILD_CRT=OFF \
  -DCOMPILER_RT_BUILD_ORC=OFF \
  -DCOMPILER_RT_BUILD_SCUDO=OFF \
  -DCOMPILER_RT_BUILD_STANDALONE_LIBATOMIC=OFF \
  \
  -DCOMPILER_RT_SANITIZERS_TO_BUILD="$(_array_join ";" "${SANITIZERS_TO_BUILD[@]}")" \
  -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DCOMPILER_RT_HAS_VERSION_SCRIPT=OFF \
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
  ${CMAKE_ARGS[@]:-}

export NINJA_STATUS="[compiler-rt $TARGET %f/%t] "
ninja -C "$BUILDDIR" compiler-rt
ninja -C "$BUILDDIR" install

if [ -d "$DESTDIR/lib/$CC_TRIPLE" ]; then
  mv "$DESTDIR/lib" "$DESTDIR/libx"
  mv "$DESTDIR/libx/$CC_TRIPLE" "$DESTDIR/lib"
  rmdir "$DESTDIR/libx"
fi

$NO_CLEANUP || rm -rf "$BUILDDIR"
