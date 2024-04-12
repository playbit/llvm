for dir in $LLVM_STAGE2_DIR $ZLIB_DIR $ZSTD_DIR $LIBXML2_DIR; do
  _cpmerge $dir/include include
  _cpmerge $dir/lib     lib
done
# remove compiler-rt & builtins lib dir
rm -rf lib/clang
