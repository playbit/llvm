BUILDDIR=$BUILD_DIR/wasi-build
_download_and_extract_tar "$WASI_URL" "$BUILDDIR" "$WASI_SHA256"
_pushd "$BUILDDIR"

unset CFLAGS
unset CXXFLAGS
unset LDFLAGS

make -j$NCPU \
  CC=$LLVM_STAGE1_DIR/bin/clang \
  AR=$LLVM_STAGE1_DIR/bin/llvm-ar \
  NM=$LLVM_STAGE1_DIR/bin/llvm-nm \
  SYSROOT_LIB=$PWD/sysroot/lib \
  SYSROOT_INC=$PWD/sysroot/usr/include \
  SYSROOT_SHARE=$PWD/sysroot/share \
  SYSROOT=$PWD/sysroot

echo "mv ${PWD##$PWD0/}/sysroot -> ${SYSROOT##$PWD0/}"
rm -rf "$SYSROOT"
mkdir -p "$(dirname "$SYSROOT")"
mv sysroot "$SYSROOT"

_popd
$NO_CLEANUP || rm -rf "$BUILDDIR"
