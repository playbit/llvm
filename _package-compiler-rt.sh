if [[ $TARGET != wasm* ]]; then
  _cpmerge $COMPILER_RT_DIR/include lib/clang/include
  _cpmerge $COMPILER_RT_DIR/share   lib/clang/share
  if [ -d $COMPILER_RT_DIR/bin ]; then
    _cpmerge $COMPILER_RT_DIR/bin bin
  fi
fi

case $TARGET in
  *macos*)
    # Clang's darwin toolchain impl assumes rt libs are at ResourceDir/lib/darwin/.
    # See MachO::AddLinkRuntimeLib in clang/lib/Driver/ToolChains/Darwin.cpp
    _cpmerge $BUILTINS_DIR/lib    lib/clang/lib/darwin
    _cpmerge $COMPILER_RT_DIR/lib lib/clang/lib/darwin
    ;;
  wasm*)
    _cpmerge $BUILTINS_DIR/lib    lib/clang/lib
    ;;
  *linux|*playbit)
    _cpmerge $BUILTINS_DIR/lib    lib/clang/lib
    _cpmerge $COMPILER_RT_DIR/lib lib/clang/lib
    ;;
esac
