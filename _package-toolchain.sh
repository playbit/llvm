_cpmerge $LLVM_STAGE2_DIR/bin               bin
_cpmerge $LLVM_STAGE2_DIR/share             share
_cpmerge $LLVM_STAGE2_DIR/lib/clang/include lib/clang/include
_cpmerge $BINARYEN_DIR/bin                  bin
if [ "$(echo "$LLVM_STAGE2_DIR"/lib/*.so)" != "$LLVM_STAGE2_DIR/lib/*.so" ]; then
  mkdir -p lib
  cp -v -a $LLVM_STAGE2_DIR/lib/*.so $LLVM_STAGE2_DIR/lib/*.so.* lib/
fi
