_cpmerge $SYSROOT .

if [[ $TARGET == *playbit && $TARGET != wasm* ]]; then
  # libc.so may have a temporary name to avoid linking issues while building llvm
  if [ -e lib/libc-TEMPORARILY_RENAMED.so ]; then
    mv lib/libc-TEMPORARILY_RENAMED.so lib/libc.so
  fi
fi
