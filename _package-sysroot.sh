_cpmerge() {
  echo "copy <projectroot>/${1##$PWD0/} -> $2"
  $TOOLS/cpmerge -v "$@" >> "$BUILD_DIR/package-sysroot.log"
}

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
_pushd "$PACKAGE_DIR"

_cpmerge $SYSROOT .

if [[ $TARGET != wasm* ]]; then
  _cpmerge $COMPILER_RT_DIR/include lib/clang/include
  _cpmerge $COMPILER_RT_DIR/share   lib/clang/share
  if [ -d $COMPILER_RT_DIR/bin ]; then
    _cpmerge $COMPILER_RT_DIR/bin bin
  fi
fi

case $TARGET in
  *macos*)
    # Clang's darwin toolchain impl assumes rt libs are at ResourceDir/lib/darwin/.
    # See MachO::AddLinkRuntimeLib in clang/lib/Driver/ToolChains/Darwin.cpp
    _cpmerge $BUILTINS_DIR/lib    lib/clang/lib/darwin
    _cpmerge $COMPILER_RT_DIR/lib lib/clang/lib/darwin
    ;;
  wasm*)
    _cpmerge $BUILTINS_DIR/lib    lib/clang/lib
    ;;
  *linux|*playbit)
    _cpmerge $BUILTINS_DIR/lib    lib/clang/lib
    _cpmerge $COMPILER_RT_DIR/lib lib/clang/lib
    # libc.so may have a temporary name to avoid linking issues while building llvm
    mv lib/libc*.so lib/libc.so
    ;;
esac

_cpmerge $LIBCXX_DIR/lib     lib
_cpmerge $LIBCXX_DIR/include include

# remove empty directories
find . -type d -empty -delete

echo "Creating ${PACKAGE_ARCHIVE##$PWD0/}"
tar -c . | xz --compress -F xz -$XZ_COMPRESSION_RATIO --stdout --threads=0 > "$PACKAGE_ARCHIVE"
