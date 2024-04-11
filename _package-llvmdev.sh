_cpmerge() {
  echo "copy <projectroot>/${1##$PWD0/} -> $2"
  $TOOLS/cpmerge -v "$@" >> "$BUILD_DIR/package-llvmdev.log"
}

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
_pushd "$PACKAGE_DIR"

# TODO
#   ZLIB_DIR
#   ZSTD_DIR
#   LIBXML2_DIR

_cpmerge $LLVM_STAGE2_DIR/include include
_cpmerge $LLVM_STAGE2_DIR/lib     lib

# remove empty directories
find . -type d -empty -delete

echo "Creating ${PACKAGE_ARCHIVE##$PWD0/}"
tar -c . | xz --compress -F xz -$XZ_COMPRESSION_RATIO --stdout --threads=0 > "$PACKAGE_ARCHIVE"
