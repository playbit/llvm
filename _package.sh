tools/build.sh
TOOLS=$PWD/tools

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
_pushd "$PACKAGE_DIR"

_cpmerge() {
  echo "copy <projectroot>/${1##$PWD0/} -> $2"
  $TOOLS/cpmerge -v "$@" >> "$PACKAGE_DIR.log"
}

# /bin/cc -> /sdk/bin/clang
# /sdk/sysroot-generic
# /sdk/sysroot-x86_64
# ...

_cpmerge $LLVM_STAGE2_DIR/bin bin
_cpmerge $LLVM_STAGE2_DIR/share share
_cpmerge $LLVM_STAGE2_DIR/lib/clang/include lib/clang/include

_cpmerge $COMPILER_RT_DIR/include lib/clang/include
_cpmerge $COMPILER_RT_DIR/share lib/clang/share
_cpmerge $COMPILER_RT_DIR/bin bin  # hwasan_symbolize

# Our final clang/lib directory contains libraries named like this:
#   clang/lib/TARGET_TRIPLE/libclang_rt.asan.a
_cpmerge $BUILTINS_DIR/lib lib/clang/lib
_cpmerge $COMPILER_RT_DIR/lib lib/clang/lib

_cpmerge $LIBCXX_DIR/include/c++ sysroot-generic/include/c++

# TARGET_TRIPLES=( x86_64-unknown-linux-musl ) # xxx

for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  IFS=- read -r TARGET_ARCH ign <<< "$TARGET_TRIPLE"
  TARGET_SYSROOT=sysroot-$TARGET_ARCH

  mv lib/clang/lib/$TARGET_TRIPLE lib/clang/lib/$TARGET_ARCH-playbit

  _cpmerge $BUILD_DIR_S2/sysroot-$TARGET_TRIPLE $TARGET_SYSROOT

  _cpmerge $LIBCXX_DIR/lib-$TARGET_TRIPLE $TARGET_SYSROOT/lib
  cp -av $LIBCXX_DIR/include/*.h $TARGET_SYSROOT/include/
  _symlink $TARGET_SYSROOT/include/c++ ../../sysroot-generic/include/c++

  # libc.so may have a temporary name to avoid linking issues while building llvm
  if [[ "$TARGET_TRIPLE" == *-linux* ]]; then
    mv $TARGET_SYSROOT/lib/libc*.so $TARGET_SYSROOT/lib/libc.so
  fi
done

# remove empty directories
find . -type d -empty -delete

echo "Creating ${PACKAGE_ARCHIVE##$PWD0/}"
# tar -c . | xz --compress -F xz -9 --stdout --threads=0 > "$PACKAGE_ARCHIVE"
tar -c . | xz --compress -F xz -3 --stdout --threads=0 > "$PACKAGE_ARCHIVE"
