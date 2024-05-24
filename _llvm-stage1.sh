DIST_COMPONENTS=(
  builtins \
  clang \
  clang-resource-headers \
  dsymutil \
  llc \
  llvm-ar \
  llvm-config \
  llvm-cov \
  llvm-dwarfdump \
  llvm-link \
  llvm-nm \
  llvm-objdump \
  llvm-profdata \
  llvm-ranlib \
  llvm-rc \
  llvm-size \
  opt \
  runtimes \
)
CMAKE_C_FLAGS=( -w )
CMAKE_LD_FLAGS=()
EXTRA_CMAKE_ARGS=()

case "$HOST_SYS" in
  macos)
    DIST_COMPONENTS+=( llvm-libtool-darwin )
    BUILD_TARGETS+=( llvm-libtool-darwin )
    EXTRA_CMAKE_ARGS+=( \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$MAC_TARGET_VERSION \
      -DCMAKE_SYSROOT=$MAC_SDK \
      -DCMAKE_OSX_SYSROOT=$MAC_SDK \
    )
    ;;
  linux)
    EXTRA_CMAKE_ARGS+=(
      -DLIBUNWIND_HAS_NODEFAULTLIBS_FLAG=OFF \
      -DCOMPILER_RT_BUILD_MEMPROF=OFF \
      -DCOMPILER_RT_USE_BUILTINS_LIBRARY=OFF \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
      -DLIBCXX_HAS_MUSL_LIBC=ON \
      -DLLVM_DEFAULT_TARGET_TRIPLE=$HOST_ARCH-linux-musl \
    )
    #
    # COMPILER_RT_USE_BUILTINS_LIBRARY
    #   Use compiler-rt builtins instead of libgcc.
    #   Must be OFF during stage 1 since we don't have builtins_* yet.
    #   Test is in llvm/compiler-rt/cmake/Modules/AddCompilerRT.cmake:285
    # COMPILER_RT_BUILD_MEMPROF=OFF
    #   if left enabled, the memprof cmake will try to unconditionally create a shared
    #   lib which will fail with errors like "undefined reference to '_Unwind_GetIP'".
    # LLVM_ENABLE_PER_TARGET_RUNTIME_DIR
    #   When on (default for linux, but not mac), rt libs are installed at
    #   lib/clang/$LLVM_RELEASE/lib/$HOST_ARCH-unknown-linux-gnu/ with plain names
    #   like "libclang_rt.builtins.a".
    #   When off, libs have an arch suffix, e.g. "libclang_rt.builtins-x86_64.a" and
    #   are installed in lib/clang/$LLVM_RELEASE/lib/.
    ;;
esac

CMAKE_C_FLAGS="${CFLAGS:-} ${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${LDFLAGS:-} ${CMAKE_LD_FLAGS[@]:-}"

mkdir -p "$LLVM_STAGE1_DIR/build"
_pushd "$LLVM_STAGE1_DIR/build"

cmake -G Ninja -Wno-dev "$LLVM_STAGE1_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$LLVM_STAGE1_DIR" \
  -DCMAKE_PREFIX_PATH="$LLVM_STAGE1_DIR" \
  \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_ASM_COMPILER="$CC" \
  -DCMAKE_AR="$AR" \
  -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_LINKER="$LD" \
  \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD="X86;AArch64;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt;lldb" \
  -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi;libunwind" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${DIST_COMPONENTS[@]:-}")" \
  -DLLVM_ENABLE_MODULES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_ZSTD=OFF \
  -DLLVM_ENABLE_ZLIB=FORCE_ON \
  -DZLIB_LIBRARY="$ZLIB_DIR/lib/libz.a" \
  -DZLIB_INCLUDE_DIR="$ZLIB_DIR/include" \
  -DHAVE_ZLIB=ON \
  -DLLVM_HAVE_LIBXAR=0 \
  -DLLVM_ENABLE_BACKTRACES=OFF \
  -DLLVM_INCLUDE_UTILS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=OFF \
  -DLLVM_BUILD_LLVM_C_DYLIB=OFF \
  -DLLVM_ENABLE_PIC=OFF \
  \
  -DCLANG_INCLUDE_DOCS=OFF \
  -DCLANG_ENABLE_OBJC_REWRITER=OFF \
  -DCLANG_ENABLE_ARCMT=OFF \
  -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
  -DCLANG_DEFAULT_CXX_STDLIB=libc++ \
  -DCLANG_DEFAULT_RTLIB=compiler-rt \
  -DCLANG_DEFAULT_UNWINDLIB=libunwind \
  -DCLANG_DEFAULT_LINKER=lld \
  -DCLANG_DEFAULT_OBJCOPY=llvm-objcopy \
  -DCLANG_PLUGIN_SUPPORT=OFF \
  -DCLANG_VENDOR=playbit \
  \
  -DLLDB_ENABLE_CURSES=OFF \
  -DLLDB_ENABLE_FBSDVMCORE=OFF \
  -DLLDB_ENABLE_LIBEDIT=OFF \
  -DLLDB_ENABLE_LUA=OFF \
  -DLLDB_ENABLE_LZMA=OFF \
  -DLLDB_ENABLE_PYTHON=OFF \
  \
  -DLIBCXX_ENABLE_STATIC=ON \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
  -DLIBCXX_INCLUDE_TESTS=OFF \
  -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
  -DLIBCXX_LINK_TESTS_WITH_SHARED_LIBCXX=OFF \
  -DLIBCXX_CXX_ABI=libcxxabi \
  -DLIBCXX_ABI_VERSION=1 \
  -DLIBCXX_USE_COMPILER_RT=ON \
  \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBCXXABI_INCLUDE_TESTS=OFF \
  -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
  -DLIBCXXABI_LINK_TESTS_WITH_SHARED_LIBCXXABI=OFF \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  \
  -DCOMPILER_RT_BUILD_XRAY=OFF \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_CAN_EXECUTE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_CRT=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_SANITIZERS=OFF \
  -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DSANITIZER_USE_STATIC_LLVM_UNWINDER=ON \
  \
  "${EXTRA_CMAKE_ARGS[@]:-}"

# note: the "distribution" target builds LLVM_DISTRIBUTION_COMPONENTS
ninja -j$NCPU \
  distribution \
  lld \
  builtins \
  compiler-rt \
  llvm-objcopy \
  llvm-tblgen \
  llvm-libraries \
  llvm-headers \
  clang-tblgen \
  lldb-tblgen \
  cxxabi

ninja -j$NCPU \
  install-distribution-stripped \
  install-lld-stripped \
  install-builtins-stripped \
  install-compiler-rt-stripped \
  install-llvm-objcopy-stripped \
  install-llvm-tblgen-stripped \
  install-llvm-libraries-stripped \
  install-llvm-headers \
  install-llvm-libtool-darwin-stripped \
  install-cxxabi-stripped

cp -av bin/clang-tblgen "$LLVM_STAGE1_DIR/bin/clang-tblgen"
cp -av bin/lldb-tblgen "$LLVM_STAGE1_DIR/bin/lldb-tblgen"
ln -fsv llvm-objcopy "$LLVM_STAGE1_DIR/bin/llvm-strip"
ln -fsv llvm-libtool-darwin "$LLVM_STAGE1_DIR/bin/libtool"

if [ "$HOST_SYS" = "linux" ]; then
  # [linux] Sometimes(??) the rtlibs are installed at lib instead of lib/linux
  # Check for that now to pervent hard-to-debug errors later
  CLANG_LIB_DIR="$LLVM_STAGE1/lib/clang/$LLVM_RELEASE/lib"
  EXPECT_FILE="$CLANG_LIB_DIR/linux/libclang_rt.builtins-$HOST_ARCH.a"
  [ -e "$EXPECT_FILE" ] ||
    _err "expected file not found: $EXPECT_FILE"

  # Fix for LLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON
  # # [linux] Somehow clang looks for compiler-rt builtins lib in a different place
  # # than where it actually installs it. This is an ugly workaround.
  # mkdir -p "$CLANG_LIB_DIR/linux"
  # _pushd "$CLANG_LIB_DIR/${HOST_ARCH}-unknown-linux-gnu"
  # for lib in *.a; do
  #   ln -vs "../${HOST_ARCH}-unknown-linux-gnu/${lib}" \
  #     "$CLANG_LIB_DIR/linux/$(basename "$lib" .a)-${HOST_ARCH}.a"
  # done
fi
