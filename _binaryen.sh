# Binaryen tools:
# - wasm-opt: Loads WebAssembly and runs Binaryen IR passes on it.
# - wasm-as: Assembles WebAssembly in text format (currently S-Expression format)
#   into binary format (going through Binaryen IR).
# - wasm-dis: Un-assembles WebAssembly in binary format into text format
#   (going through Binaryen IR).
# - wasm2js: A WebAssembly-to-JS compiler. This is used by Emscripten to generate
#   JavaScript as an alternative to WebAssembly.
# - wasm-reduce: A testcase reducer for WebAssembly files. Given a wasm file that is
#   interesting for some reason (say, it crashes a specific VM), wasm-reduce can
#   find a smaller wasm file that has the same property, which is often easier to debug.
# - wasm-shell: A shell that can load and interpret WebAssembly code. It can also
#   run the spec test suite.
# - wasm-emscripten-finalize: Takes a wasm binary produced by llvm+lld and performs
#   emscripten-specific passes over it.
# - wasm-ctor-eval: A tool that can execute functions (or parts of functions) at
#   compile time.
# - wasm-merge: Merges multiple wasm files into a single file, connecting
#   corresponding imports to exports as it does so. Like a bundler for JS, but for wasm.
# - wasm-metadce: A tool to remove parts of Wasm files in a flexible way that
#   depends on how the module is used.
BINARYEN_TOOLS=( wasm-opt )
# BINARYEN_TOOLS+=( wasm-as )
# BINARYEN_TOOLS+=( wasm-dis )
# BINARYEN_TOOLS+=( wasm-ctor-eval )
# BINARYEN_TOOLS+=( wasm-emscripten-finalize )
# BINARYEN_TOOLS+=( wasm-fuzz-lattices )
# BINARYEN_TOOLS+=( wasm-fuzz-types )
# BINARYEN_TOOLS+=( wasm-merge )
# BINARYEN_TOOLS+=( wasm-metadce )
# BINARYEN_TOOLS+=( wasm-reduce )
# BINARYEN_TOOLS+=( wasm-shell )
# BINARYEN_TOOLS+=( wasm-split )
# BINARYEN_TOOLS+=( wasm2js )

BUILD_DIR=$BINARYEN_DIR-build
DESTDIR=$BINARYEN_DIR

CMAKE_ARGS=(
  -DBUILD_TESTS=OFF \
  -DINSTALL_LIBS=OFF \
  -DBYN_ENABLE_ASSERTIONS=OFF \
  -DENABLE_WERROR=OFF \
  -DBUILD_EMSCRIPTEN_TOOLS_ONLY=ON \
  -DBUILD_STATIC_LIB=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX= \
  -DCMAKE_SYSROOT="$SYSROOT" \
)

CMAKE_C_FLAGS=(
  $CFLAGS \
  -Wno-unused-command-line-argument \
)
CMAKE_CXX_FLAGS=(
  "-I$LIBCXX_DIR/usr/include/c++/v1" \
  "-I$LIBCXX_DIR/usr/include" \
  "-isystem$SYSROOT/usr/include" \
)
CMAKE_LD_FLAGS=(
  $LDFLAGS \
  "-L$LIBCXX_DIR/lib" \
  "-L$SYSROOT/lib" \
  -lc++abi \
)

case $TARGET in
  *linux|*playbit|wasm*)
    # CMAKE_C_FLAGS+=( -static )
    CMAKE_LD_FLAGS+=( -static )
    ;;
  *macos*)
    CMAKE_ARGS+=( \
      -DCMAKE_OSX_DEPLOYMENT_TARGET=$MAC_TARGET_VERSION \
      -DCMAKE_OSX_SYSROOT="$SYSROOT" \
    )
    case $TARGET in
      x86_64*)  CMAKE_ARGS+=( -DCMAKE_OSX_ARCHITECTURES=x86_64 ) ;;
      aarch64*) CMAKE_ARGS+=( -DCMAKE_OSX_ARCHITECTURES=arm64 ) ;;
    esac
    ;;
esac

case "$TARGET" in
  aarch64-macos) CMAKE_C_FLAGS+=( -mcpu=apple-m1 ) ;;
  x86_64*)       CMAKE_C_FLAGS+=( -march=x86-64-v2 ) ;;
esac

case "$HOST_SYS" in
  linux) CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Linux ) ;;
  macos) CMAKE_ARGS+=( -DCMAKE_HOST_SYSTEM_NAME=Darwin ) ;;
esac
case "$TARGET" in
  *linux|*playbit) CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Linux ) ;;
  *macos*)         CMAKE_ARGS+=( -DCMAKE_SYSTEM_NAME=Darwin ) ;;
esac

if $ENABLE_LTO; then
  CMAKE_ARGS+=( -DBYN_ENABLE_LTO=ON )
fi

# bake flags (array -> string)
CMAKE_CXX_FLAGS="${CMAKE_CXX_FLAGS[@]:-} ${CMAKE_C_FLAGS[@]:-}"
CMAKE_C_FLAGS="${CMAKE_C_FLAGS[@]:-}"
CMAKE_LD_FLAGS="${CMAKE_LD_FLAGS[@]:-}"

if [ "$(cat "$BUILD_DIR/version.txt" 2>/dev/null)" != $BINARYEN_VERSION ]; then
  _download_and_extract_tar \
    "$BINARYEN_URL" \
    "$BUILD_DIR" \
    "$BINARYEN_SHA256" \
    "$DOWNLOAD_DIR/binaryen-$BINARYEN_VERSION.tar.gz"
fi
_pushd "$BUILD_DIR"
echo $BINARYEN_VERSION > version.txt

cmake -G Ninja . \
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
  "${CMAKE_ARGS[@]}"

ninja

rm -rf "$DESTDIR"
mkdir -p "$DESTDIR/bin"
for f in ${BINARYEN_TOOLS[@]}; do
  echo "install ${DESTDIR##$PWD0/}/bin/$f"
  $STRIP bin/$f
  mv bin/$f "$DESTDIR/bin/$f"
done

_popd
$NO_CLEANUP || rm -rf "$BUILD_DIR"
