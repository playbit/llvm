SELF_SCRIPT=$(realpath "${BASH_SOURCE[0]}")
DIST_COMPONENTS=(
  clang \
  clang-format \
  clang-headers \
  clang-libraries \
  clang-resource-headers \
  lld \
  llvm-ar \
  llvm-as \
  llvm-config \
  llvm-cov \
  llvm-dlltool \
  llvm-dwarfdump \
  llvm-headers \
  llvm-libraries \
  llvm-libtool-darwin \
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
)
EXTRA_COMPONENTS=( # components without install targets
  clang-tblgen \
  lib/liblldCOFF.a \
  lib/liblldCommon.a \
  lib/liblldELF.a \
  lib/liblldMachO.a \
  lib/liblldMinGW.a \
  lib/liblldWasm.a \
)

CMAKE_C_FLAGS=( \
  $CFLAGS \
  -Wno-unused-command-line-argument \
)

# Note: We have to provide search path to sysroot headers after libc++ headers
# for include_next to function properly. Additionally, we must (later) make sure
# that CMAKE_CXX_FLAGS preceeds CFLAGS for C++ compilation, so that e.g.
# include <stdlib.h> loads c++/v1/stdlib.h (and then sysroot/include/stdlib.h)
CMAKE_CXX_FLAGS=( \
  "-I$LIBCXX_DIR/usr/include/c++/v1" \
  "-isystem$SYSROOT/usr/include" \
)
CMAKE_LD_FLAGS=( $LDFLAGS -lc++ -lc++abi )
EXTRA_CMAKE_ARGS=( -Wno-dev )
# CMAKE_CXX_FLAGS+=( -nostdinc++ )
# CMAKE_LD_FLAGS+=( -nostdlib++ )

# case "$TARGET_SYS" in
#   linux)
#     CMAKE_LD_FLAGS+=( -static )
#     EXTRA_CMAKE_ARGS+=(
#       -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET_TRIPLE" \
#       -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
#     )
#     ;;
# esac

# note: there are clang-specific option, even though it doesn't start with CLANG_
# See: llvm/clang/CMakeLists.txt
#
# DEFAULT_SYSROOT sets the default --sysroot=<path>.
# Note that if sysroot is relative, clang will treat it as relative to itself.
# I.e. sysroot=foo with clang at /bar/bin/clang results in sysroot=/bar/bin/foo.
# See line ~200 of clang/lib/Driver/Driver.cpp
EXTRA_CMAKE_ARGS+=( -DDEFAULT_SYSROOT="native-sysroot/" )
#
# C_INCLUDE_DIRS is a colon-separated list of paths to search by default.
# Relative paths are relative to sysroot.
# The user can pass -nostdlibinc to disable searching of these paths.
# See line ~600 of clang/lib/Driver/ToolChains/Linux.cpp
EXTRA_CMAKE_ARGS+=( -DC_INCLUDE_DIRS="include/c++/v1:include" )
#
# ENABLE_LINKER_BUILD_ID causes clang to pass --build-id to ld
EXTRA_CMAKE_ARGS+=( -DENABLE_LINKER_BUILD_ID=ON )

# GENERATOR_IS_MULTI_CONFIG=ON disables generation of ASTNodeAPI.json
# which 1) we don't need, 2) takes a long time, and 3) can't build because the
# tool used to build it will be compiled for the target, not the host.
# See clang/lib/Tooling/CMakeLists.txt
EXTRA_CMAKE_ARGS+=( -DGENERATOR_IS_MULTI_CONFIG=ON )

# LLVM_INSTALL_BINUTILS_SYMLINKS create symlinks that match binutils (nm ar etc)
EXTRA_CMAKE_ARGS+=( -DLLVM_INSTALL_BINUTILS_SYMLINKS=ON )

# LLVM_INSTALL_TOOLCHAIN_ONLY: Only include toolchain files in the 'install' target
# EXTRA_CMAKE_ARGS+=( -DLLVM_INSTALL_TOOLCHAIN_ONLY=ON )

# CLANG_RESOURCE_DIR: /lib/clang/VERSION by default
# EXTRA_CMAKE_ARGS+=( -DCLANG_RESOURCE_DIR=clangres )



ENABLE_BUILTINS=true
if $ENABLE_BUILTINS; then
  # TODO: build all sysroots, then enable runtimes for all targets
  TARGET_TRIPLES=( $TARGET_TRIPLE ) # XXX FIXME
  EXTRA_CMAKE_ARGS+=(
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLLVM_BUILTIN_TARGETS="$(_array_join ";" ${TARGET_TRIPLES[@]})" \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt" \
  )
  DIST_COMPONENTS+=( builtins )
  RUNTIMES_INSTALL_RPATH="\$ORIGIN/../lib;/lib"
  # BUILTINS_CFLAGS=( -fPIC -resource-dir=$BUILTINS_DIR/ -isystem$LIBCXX_DIR/usr/include )
  BUILTINS_CFLAGS=( -fPIC )
  for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
    EXTRA_CMAKE_ARGS+=(
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_BUILD_TYPE=MinSizeRel \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_SYSTEM_NAME=Linux \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_SYSROOT="$SYSROOT" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_INSTALL_RPATH=$RUNTIMES_INSTALL_RPATH \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_BUILD_WITH_INSTALL_RPATH=ON \
      \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_ASM_COMPILER="$CC" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_C_COMPILER="$CC" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_CXX_COMPILER="$CXX" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_AR="$AR" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_RANLIB="$RANLIB" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_LINKER="$LD" \
      \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_C_FLAGS="${BUILTINS_CFLAGS[@]:-} --target=${TARGET_TRIPLE}" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_CXX_FLAGS="${BUILTINS_CFLAGS[@]:-} --target=${TARGET_TRIPLE}" \
      -DBUILTINS_${TARGET_TRIPLE}_CMAKE_ASM_FLAGS="${BUILTINS_CFLAGS[@]:-} --target=${TARGET_TRIPLE}" \
      \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_BUILTINS=ON \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_SANITIZERS=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_XRAY=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_PROFILE=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_CRT=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_ORC=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_INCLUDE_TESTS=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_CAN_EXECUTE_TESTS=OFF \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_USE_BUILTINS_LIBRARY=ON  \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_BUILD_STANDALONE_LIBATOMIC=OFF \
    )
    # EXTRA_CMAKE_ARGS+=(
    #   -DBUILTINS_${TARGET_TRIPLE}_CMAKE_ASM_COMPILER_ID=Clang \
    #   -DBUILTINS_${TARGET_TRIPLE}_CMAKE_C_COMPILER_ID=Clang \
    #   -DBUILTINS_${TARGET_TRIPLE}_CMAKE_CXX_COMPILER_ID=Clang \
    # )
    # EXTRA_CMAKE_ARGS+=(
    #   -DBUILTINS_${TARGET_TRIPLE}_CMAKE_ASM_COMPILER_VERSION=$LLVM_VERSION \
    #   -DBUILTINS_${TARGET_TRIPLE}_CMAKE_C_COMPILER_VERSION=$LLVM_VERSION \
    #   -DBUILTINS_${TARGET_TRIPLE}_CMAKE_CXX_COMPILER_VERSION=$LLVM_VERSION \
    # )
    EXTRA_CMAKE_ARGS+=(
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_CXX_LIBRARY=libcxx \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_USE_LLVM_UNWINDER=ON \
      -DBUILTINS_${TARGET_TRIPLE}_COMPILER_RT_ENABLE_STATIC_UNWINDER=ON \
    )
  done
fi

ENABLE_RUNTIMES=false
if $ENABLE_RUNTIMES; then
  LLVM_ENABLE_RUNTIMES="compiler-rt;libcxx;libcxxabi;libunwind"
  # LLVM_ENABLE_RUNTIMES="compiler-rt"
  DIST_COMPONENTS+=( runtimes )
  EXTRA_CMAKE_ARGS+=(
    -DLLVM_RUNTIME_TARGETS="$(_array_join ";" ${TARGET_TRIPLES[@]})" \
    -DLLVM_ENABLE_RUNTIMES="$LLVM_ENABLE_RUNTIMES" \
  )
  RUNTIMES_CFLAGS=( -fPIC )
  # if $ENABLE_BUILTINS; then
  #   RUNTIMES_CFLAGS+=( -resource-dir=$BUILTINS_DIR/ )
  # fi
  for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
    EXTRA_CMAKE_ARGS+=(
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_BUILD_TYPE=MinSizeRel \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_SYSTEM_NAME=Linux \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_SYSROOT="$SYSROOT" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_INSTALL_RPATH="$RUNTIMES_INSTALL_RPATH" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_BUILD_WITH_INSTALL_RPATH=ON \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_ASM_COMPILER="$CC" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_C_COMPILER="$CC" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_CXX_COMPILER="$CXX" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_AR="$AR" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_RANLIB="$RANLIB" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_LINKER="$LD" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_NM="$LLVM_STAGE1_DIR/bin/llvm-nm" \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_C_FLAGS="${RUNTIMES_CFLAGS[@]:-} --target=${TARGET_TRIPLE}" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_CXX_FLAGS="${RUNTIMES_CFLAGS[@]:-} --target=${TARGET_TRIPLE}" \
      -DRUNTIMES_${TARGET_TRIPLE}_CMAKE_ASM_FLAGS="${RUNTIMES_CFLAGS[@]:-} --target=${TARGET_TRIPLE}" \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_LLVM_ENABLE_RUNTIMES="$LLVM_ENABLE_RUNTIMES" \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_BUILTINS=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_SANITIZERS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_XRAY=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_LIBFUZZER=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_PROFILE=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_CRT=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_ORC=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_DEFAULT_TARGET_ONLY=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_INCLUDE_TESTS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_CAN_EXECUTE_TESTS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_USE_BUILTINS_LIBRARY=ON  \
      -DRUNTIMES_${TARGET_TRIPLE}_COMPILER_RT_BUILD_STANDALONE_LIBATOMIC=OFF \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBUNWIND_USE_COMPILER_RT=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBUNWIND_ENABLE_SHARED=OFF \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_ENABLE_SHARED=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_USE_LLVM_UNWINDER=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_USE_COMPILER_RT=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_INCLUDE_TESTS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXXABI_LINK_TESTS_WITH_SHARED_LIBCXXABI=OFF \
      \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_HAS_MUSL_LIBC=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_USE_COMPILER_RT=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_ENABLE_STATIC=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_ENABLE_SHARED=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_ABI_VERSION=2 \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_CXX_ABI=libcxxabi \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_ENABLE_NEW_DELETE_DEFINITIONS=ON \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_ENABLE_EXPERIMENTAL_LIBRARY=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_INCLUDE_TESTS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_INCLUDE_BENCHMARKS=OFF \
      -DRUNTIMES_${TARGET_TRIPLE}_LIBCXX_LINK_TESTS_WITH_SHARED_LIBCXX=OFF \
    )
  done
fi


# EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_LTO=Thin )

if [ "$CBUILD" != "$CHOST" ]; then
  case "$HOST_SYS" in
    linux) EXTRA_CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Linux ) ;;
    macos) EXTRA_CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Darwin ) ;;
  esac
  case "$TARGET_SYS" in
    linux) EXTRA_CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Linux ) ;;
    macos) EXTRA_CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Darwin ) ;;
  esac
fi

# This is a hack!
# llvm's cmake files checks if this is ON, and if it is, llvm will attempt
# to build a "native" (host) version of itself, which will fail.
EXTRA_CMAKE_ARGS+=( -DCMAKE_CROSSCOMPILING=OFF )

EXTRA_CMAKE_ARGS+=(
  -DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON \
  -DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON \
)

CMAKE_LD_FLAGS+=( -L"$SYSROOT/lib" )
# CMAKE_LD_FLAGS+=( -L"$LIBCXX_STAGE2/lib" )

# TODO -DCMAKE_ASM_COMPILER="$AS"

# bake flags (array -> string)
CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS[@]:-} ${CMAKE_C_FLAGS[@]:-}"
CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

BUILD_DIR=$LLVM_STAGE2_DIR-build
DESTDIR=$LLVM_STAGE2_DIR
mkdir -p "$BUILD_DIR"
_pushd "$BUILD_DIR"

if [ ! -f CMakeCache.txt ] || [ "$SELF_SCRIPT" -nt CMakeCache.txt ]; then
# if false; then

# --fresh: re-configure from scratch.
# This only works for the top-level cmake invocation; does not apply to sub-invocations
# like builtins or runtimes. For a fresh setup of runtimes or builtins:
#   rm -rf build-x86_64-unknown-linux-musl/s2-llvm-build/runtimes \
#          build-x86_64-unknown-linux-musl/s2-llvm-build/projects/runtimes* \
#          build-x86_64-unknown-linux-musl/s2-llvm-build/projects/builtins*
#
# EXTRA_CMAKE_ARGS+=( --fresh )

cmake -G Ninja "$LLVM_STAGE2_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX= \
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
  -DLLVM_TARGETS_TO_BUILD="X86;AArch64;RISCV;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${DIST_COMPONENTS[@]}")" \
  -DLLVM_DEFAULT_TARGET_TRIPLE=$TARGET_TRIPLE \
  -DLLVM_APPEND_VC_REV=OFF \
  -DLLVM_ENABLE_MODULES=OFF \
  -DLLVM_ENABLE_BINDINGS=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_ENABLE_EH=OFF \
  -DLLVM_ENABLE_RTTI=OFF \
  -DLLVM_ENABLE_FFI=OFF \
  -DLLVM_ENABLE_BACKTRACES=OFF \
  -DLLDB_ENABLE_PYTHON=OFF \
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
  -DLLVM_INCLUDE_TOOLS=ON \
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
  -DCLANG_VENDOR=Playbit \
  -DLIBCLANG_BUILD_STATIC=ON \
  \
  -DLLDB_ENABLE_CURSES=OFF \
  -DLLDB_ENABLE_FBSDVMCORE=OFF \
  -DLLDB_ENABLE_LIBEDIT=OFF \
  -DLLDB_ENABLE_LUA=OFF \
  -DLLDB_ENABLE_PYTHON=OFF \
  -DLLDB_INCLUDE_TESTS=OFF \
  -DLLDB_TABLEGEN_EXE="$LLVM_STAGE1_DIR/bin/lldb-tblgen" \
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

fi

echo "———————————————————————— build ————————————————————————"
ninja -j$NCPU distribution "${EXTRA_COMPONENTS[@]}"



echo "———————————————————————— install ————————————————————————"
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR"
DESTDIR="$DESTDIR" ninja -j$NCPU install-distribution-stripped

# no install target for clang-tblgen
install -vm 0755 bin/clang-tblgen "$DESTDIR/bin/clang-tblgen"

# no install targets for lld libs
for f in lib/liblld*.a; do
  install -vm 0644 $f "$DESTDIR/lib/$(basename "$f")"
done

# # copy lld headers from source (they are not affected by build)
cp -av "$LLVM_STAGE2_SRC/lld/include/lld" "$DESTDIR/include/lld"

# bin/ fixes
_pushd "$DESTDIR"/bin

# # create binutils-compatible symlinks
# # ack --type=cmake 'add_llvm_tool_symlink\(' build/s2-llvm-17.0.3 | cat
# BINUTILS_SYMLINKS=( # "alias target"
#   addr2line         llvm-symbolizer \
#   ar                llvm-ar \
#   bitcode_strip     llvm-bitcode-strip \
#   c++filt           llvm-cxxfilt \
#   debuginfod        llvm-debuginfod \
#   debuginfod-find   llvm-debuginfod-find \
#   dlltool           llvm-ar \
#   dwp               llvm-dwp \
#   install_name_tool llvm-install-name-tool \
#   libtool           llvm-libtool-darwin \
#   lipo              llvm-lipo \
#   nm                llvm-nm \
#   objcopy           llvm-objcopy \
#   objdump           llvm-objdump \
#   otool             llvm-objdump \
#   ranlib            llvm-ar \
#   readelf           llvm-readobj \
#   size              llvm-size \
#   strings           llvm-strings \
#   strip             llvm-objcopy \
#   windres           llvm-rc \
# )
# for ((i = 0; i < ${#BINUTILS_SYMLINKS[@]}; i += 2)); do
#   name=${BINUTILS_SYMLINKS[i]}
#   target=${BINUTILS_SYMLINKS[$(( i+1 ))]}
#   [ -e $target ] || continue
#   _symlink $name $target
# done
