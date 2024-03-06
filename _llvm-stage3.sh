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
  lib/liblldCOFF.a \
  lib/liblldCommon.a \
  lib/liblldELF.a \
  lib/liblldMachO.a \
  lib/liblldMinGW.a \
  lib/liblldWasm.a \
)

CMAKE_C_FLAGS=( \
  ${CFLAGS:-} \
  -Wno-unused-command-line-argument \
)
# CMAKE_CXX_FLAGS=( -nostdinc++ -I"$LIBCXX_STAGE2/include/c++/v1" )
# CMAKE_CXX_FLAGS=( -nostdinc++ -I"$LIBCXX_STAGE2/include/c++/v1" )
# CMAKE_LD_FLAGS=( -nostdlib++ )

LLVMBOX_ENABLE_LTO=false
# if $LLVMBOX_ENABLE_LTO; then
#   [ -d "$LIBCXX_STAGE2/lib-lto" ] ||
#     _err "directory not found: $(_relpath "$LIBCXX_STAGE2/lib-lto")"
#   CMAKE_LD_FLAGS=( -L"$LIBCXX_STAGE2/lib-lto" -lc++ -lc++abi )
# else
  # CMAKE_LD_FLAGS=( -L"$LIBCXX_STAGE2/lib" -lc++ -lc++abi )
  CMAKE_LD_FLAGS=( -lc++ -lc++abi )
# fi
EXTRA_CMAKE_ARGS=( -Wno-dev )

case "$TARGET_SYS" in
  macos)
    case "$TARGET_SYSVER" in
      10|10.*)
        EXTRA_CMAKE_ARGS+=( -DCMAKE_OSX_DEPLOYMENT_TARGET=10.15 )
        TARGET_DARWIN_VERSION=19.0.0
        ;;
      11|11.*)
        EXTRA_CMAKE_ARGS+=( -DCMAKE_OSX_DEPLOYMENT_TARGET=11.1 )
        TARGET_DARWIN_VERSION=20.1.0
        ;;
      *)
        EXTRA_CMAKE_ARGS+=( -DCMAKE_OSX_DEPLOYMENT_TARGET=$TARGET_SYSVER )
        # default to major version (macos 10.x = darwin 19.x, 11.x = 20.x, ...)
        TARGET_DARWIN_VERSION=$(( ${TARGET_SYSVER%%.*} + 9 ))
        ;;
    esac
    if [ $TARGET_ARCH = x86_64 ]; then
      CMAKE_LD_FLAGS+=( -Wl,-platform_version,macos,$TARGET_SYSVER,$TARGET_SYSVER )
    else
      CMAKE_LD_FLAGS+=( -Wl,-platform_version,macos,$TARGET_SYSVER,$TARGET_SYSVER )
    fi
    EXTRA_CMAKE_ARGS+=(
      -DCMAKE_OSX_SYSROOT="$SYSROOT" \
      -DOSX_SYSROOT="$SYSROOT" \
      -DDARWIN_osx_CACHED_SYSROOT="$SYSROOT" \
      -DDARWIN_macosx_CACHED_SYSROOT="$SYSROOT" \
      -DDARWIN_iphonesimulator_CACHED_SYSROOT=/dev/null \
      -DDARWIN_iphoneos_CACHED_SYSROOT=/dev/null \
      -DDARWIN_watchsimulator_CACHED_SYSROOT=/dev/null \
      -DDARWIN_watchos_CACHED_SYSROOT=/dev/null \
      -DDARWIN_appletvsimulator_CACHED_SYSROOT=/dev/null \
      -DDARWIN_appletvos_CACHED_SYSROOT=/dev/null \
      -DCOMPILER_RT_ENABLE_IOS=OFF \
      -DCOMPILER_RT_ENABLE_WATCHOS=OFF \
      -DCOMPILER_RT_ENABLE_TVOS=OFF \
      -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET_ARCH-apple-darwin$TARGET_DARWIN_VERSION" \
      -DCOMPILER_RT_COMMON_CFLAGS="-isystem$SYSROOT/include" \
      -DCOMPILER_RT_BUILTIN_CFLAGS="-isystem$SYSROOT/include" \
      -DLLVM_TOOLCHAIN_TOOLS=llvm-libtool-darwin \
      -DCMAKE_LIBTOOL="$LLVM_STAGE1_DIR/bin/llvm-libtool-darwin" \
    )
    # to find out supported archs: ld -v 2>&1 | grep 'support archs:'
    if [ "$TARGET_ARCH" == x86_64 ]; then
      # Needed to exclude i386 target, which won't work in our sysroot
      EXTRA_CMAKE_ARGS+=(
        -DDARWIN_osx_BUILTIN_ARCHS="x86_64;x86_64h" \
        -DDARWIN_macosx_BUILTIN_ARCHS="x86_64;x86_64h" \
      )
    elif [ "$TARGET_ARCH" == aarch64 ]; then
      # Needed on aarch64 since cmake will try 'clang -v' (which it expects to be ld)
      # to discover supported architectures.
      EXTRA_CMAKE_ARGS+=(
        -DDARWIN_osx_BUILTIN_ARCHS="arm64" \
        -DDARWIN_macosx_BUILTIN_ARCHS="arm64" \
      )
      # Note: macOS 11 and/or apple arm64 executables must be built with PIE
      # (LLVM_ENABLE_PIC=ON). Otherwise the resulting executables are simply killed
      # by the kernel when started without an error message or information.
    fi
    # all: asan;dfsan;msan;hwasan;tsan;safestack;cfi;scudo;ubsan_minimal;gwp_asan
    EXTRA_CMAKE_ARGS+=(
      -DCOMPILER_RT_SANITIZERS_TO_BUILD="asan;msan;safestack;scudo;ubsan_minimal" \
    )
    # -DLLVM_BUILTIN_TARGETS=$TARGET_ARCH-darwin-apple
    CMAKE_C_FLAGS+=(
      -w \
      -DTARGET_OS_EMBEDDED=0 \
      -DTARGET_OS_IPHONE=0 \
    )
    # required for CoreFoundation/CFBase.h which is used by compiler-rt/tsan
    CMAKE_C_FLAGS+=( -Wno-elaborated-enum-base )
    # required for linking with CoreFoundation, required by dsymutil
    CMAKE_LD_FLAGS+=( -F"$MAC_SDK/System/Library/Frameworks" )
    ;;

  linux)
    CMAKE_LD_FLAGS+=( -static )
    EXTRA_CMAKE_ARGS+=(
      -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET_ARCH-linux-musl" \
      -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=OFF \
    )
    ;;
esac

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
# Relative paths are relative to sysroot. The user can pass -nostdlibinc to disable
# searching of these paths.
# See line ~600 of clang/lib/Driver/ToolChains/Linux.cpp
EXTRA_CMAKE_ARGS+=( -DC_INCLUDE_DIRS="include/c++/v1:include" )
#
# ENABLE_LINKER_BUILD_ID causes clang to pass --build-id to ld
EXTRA_CMAKE_ARGS+=( -DENABLE_LINKER_BUILD_ID=ON )

if $LLVMBOX_ENABLE_LTO; then
  EXTRA_CMAKE_ARGS+=( -DLLVM_ENABLE_LTO=Thin )
fi

if [ "$CBUILD" != "$CHOST" ]; then
  case "$HOST_SYS" in
    linux) EXTRA_CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Linux ) ;;
    macos) EXTRA_CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Darwin ) ;;
  esac
  case "$TARGET_SYS" in
    linux) EXTRA_CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Linux ) ;;
    macos) EXTRA_CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Darwin ) ;;
  esac
  #EXTRA_CMAKE_ARGS+=( -DLIBUNWIND_SYSROOT=$SYSROOT )
fi

EXTRA_CMAKE_ARGS+=(
  -DHAVE_CXX_ATOMICS_WITHOUT_LIB=ON \
  -DHAVE_CXX_ATOMICS64_WITHOUT_LIB=ON \
)


CMAKE_LD_FLAGS+=( -L"$SYSROOT/lib" )
# CMAKE_LD_FLAGS+=( -L"$LIBCXX_STAGE2/lib" )

# TODO -DCMAKE_ASM_COMPILER="$AS"

# bake flags (array -> string)
CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS[@]:-}"
CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

mkdir -p "$LLVM_STAGE2_DIR"
_pushd "$LLVM_STAGE2_DIR"

cmake -G Ninja "$LLVM_STAGE2_SRC/llvm" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DCMAKE_INSTALL_PREFIX= \
  \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_AR="$AR" \
  -DCMAKE_RANLIB="$RANLIB" \
  -DCMAKE_LINKER="$LD" \
  \
  -DCMAKE_C_FLAGS="$CMAKE_C_FLAGS" \
  -DCMAKE_CXX_FLAGS="$CMAKE_CXX_FLAGS" \
  -DCMAKE_EXE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_SHARED_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  -DCMAKE_MODULE_LINKER_FLAGS="$CMAKE_LD_FLAGS" \
  \
  -DLLVM_TARGETS_TO_BUILD="X86;ARM;AArch64;RISCV;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS="clang;lld;compiler-rt" \
  -DLLVM_DISTRIBUTION_COMPONENTS="$(_array_join ";" "${DIST_COMPONENTS[@]}")" \
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
  -DLLVM_INCLUDE_GO_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_ENABLE_OCAMLDOC=OFF \
  -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=OFF \
  -DLLVM_BUILD_LLVM_C_DYLIB=OFF \
  -DLLVM_ENABLE_PIC=ON \
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
  -DCLANG_VENDOR=compis \
  -DLIBCLANG_BUILD_STATIC=ON \
  \
  -DLLDB_ENABLE_CURSES=OFF \
  -DLLDB_ENABLE_FBSDVMCORE=OFF \
  -DLLDB_ENABLE_LIBEDIT=OFF \
  -DLLDB_ENABLE_LUA=OFF \
  -DLLDB_ENABLE_PYTHON=OFF \
  \
  -DLIBCXX_ENABLE_SHARED=OFF \
  -DLIBCXXABI_ENABLE_SHARED=OFF \
  -DLIBUNWIND_ENABLE_SHARED=OFF \
  \
  -DCOMPILER_RT_BUILD_LIBFUZZER=OFF \
  -DCOMPILER_RT_CAN_EXECUTE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_CRT=ON \
  -DCOMPILER_RT_INCLUDE_TESTS=OFF \
  -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
  -DCOMPILER_RT_USE_BUILTINS_LIBRARY=OFF \
  -DCOMPILER_RT_ENABLE_STATIC_UNWINDER=ON \
  -DCOMPILER_RT_STATIC_CXX_LIBRARY=ON \
  -DSANITIZER_USE_STATIC_CXX_ABI=ON \
  -DSANITIZER_USE_STATIC_LLVM_UNWINDER=ON \
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

echo "———————————————————————— build ————————————————————————"
ninja -j$(nproc) distribution "${EXTRA_COMPONENTS[@]}"


exit 0



echo "———————————————————————— install ————————————————————————"
rm -rf "$LLVM_STAGE2"
mkdir -p "$LLVM_STAGE2"
DESTDIR="$LLVM_STAGE2" ninja -j$NCPU install-distribution-stripped

# no install target for clang-tblgen
install -vm 0755 bin/clang-tblgen "$LLVM_STAGE2/bin/clang-tblgen"

# no install targets for lld libs
for f in lib/liblld*.a; do
  install -vm 0644 $f "$LLVM_STAGE2/lib/$(basename "$f")"
done

# copy lld headers from source (they are not affected by build)
cp -av "$LLVM_STAGE2_SRC/lld/include/lld" "$LLVM_STAGE2/include/lld"

# bin/ fixes
_pushd "$LLVM_STAGE2"/bin

# create binutils-compatible symlinks
for name_target in "${BINUTILS_SYMLINKS[@]}"; do
  IFS=' ' read -r name target <<< "$name_target"
  [ -e $target ] || continue
  _symlink $name $target
done

# strip (yes, one more time :-)
#STRIP_VERBOSE=1 # uncomment to print file size changes
EXES=()
for f in *; do
  [ -f "$f" ] || continue
  EXES+=( "$(basename "$(realpath "$f")")" )
done
IFS=$'\n' EXES=( $(sort -u <<< "${EXES[*]}") ); unset IFS
for f in "${EXES[@]}"; do
  if [ -z "${STRIP_VERBOSE:-}" ]; then
    echo "strip $f"
    "$LLVM_STAGE1/bin/llvm-strip" "$f" 2>/dev/null || true &
  else
    Z1=$(_human_filesize "$f")
    echo -n "strip $f"
    "$LLVM_STAGE1/bin/llvm-strip" "$f" 2>/dev/null || true
    echo -e ":\t$Z1 -> $(_human_filesize "$f")"
  fi
done
wait

# Having trouble?
#   Missing headers on macOS?
#     1. Open import-macos-headers.c and add them
#     2. Run ./import-macos-libc.sh on a mac with SDKs installed
#     3. Recreate your build sysroot (bash 020-sysroot.sh)
#     4. Try again
