_cpmerge $SYSROOT .

if [[ $TARGET == *playbit && $TARGET != wasm* ]]; then
  # libc.so may have a temporary name to avoid linking issues while building llvm
  mv lib/libc*.so lib/libc.so
fi
