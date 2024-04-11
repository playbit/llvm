_cpmerge() {
  echo "copy <projectroot>/${1##$PWD0/} -> $2"
  $TOOLS/cpmerge -v "$@" >> "$BUILD_DIR/package-toolchain.log"
}

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
_pushd "$PACKAGE_DIR"

_cpmerge $LLVM_STAGE2_DIR/bin               bin
_cpmerge $LLVM_STAGE2_DIR/share             share
_cpmerge $LLVM_STAGE2_DIR/lib/clang/include lib/clang/include

# remove empty directories
find . -type d -empty -delete

echo "Creating ${PACKAGE_ARCHIVE##$PWD0/}"
tar -c . | xz --compress -F xz -$XZ_COMPRESSION_RATIO --stdout --threads=0 > "$PACKAGE_ARCHIVE"
