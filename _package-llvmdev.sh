_cpmerge $LLVM_STAGE2_DIR/usr/include usr/include
_cpmerge $LLVM_STAGE2_DIR/lib         lib
for dir in $ZLIB_DIR $ZSTD_DIR $LIBXML2_DIR; do
  _cpmerge $dir/include usr/include
  _cpmerge $dir/lib     lib
done
# remove compiler-rt & builtins lib dir
rm -rf lib/clang
