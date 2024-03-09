BUILD_DIR=$BUILD_DIR_S2/wasi
_download_and_extract_tar "$WASI_URL" "$BUILD_DIR" "$WASI_SHA256"
_pushd "$BUILD_DIR"

unset CFLAGS
unset CXXFLAGS
unset LDFLAGS

make -j$NCPU \
  CC=$LLVM_STAGE1_DIR/bin/clang \
  AR=$LLVM_STAGE1_DIR/bin/llvm-ar \
  NM=$LLVM_STAGE1_DIR/bin/llvm-nm \
  SYSROOT_LIB=$PWD/sysroot/lib \
  SYSROOT_INC=$PWD/sysroot/include \
  SYSROOT_SHARE=$PWD/sysroot/share \
  SYSROOT=$PWD/sysroot

echo "mv ${PWD##$PWD0/}/sysroot -> ${SYSROOT##$PWD0/}"
rm -rf "$SYSROOT"
mkdir -p "$(dirname "$SYSROOT")"
mv sysroot "$SYSROOT"
