lib=lib; [[ $TARGET == *macos* ]] && lib=usr/lib

if [[ $TARGET != wasm* ]]; then
  _cpmerge $COMPILER_RT_DIR/include $lib/clang/include
  _cpmerge $COMPILER_RT_DIR/share   $lib/clang/share
  if [ -d $COMPILER_RT_DIR/bin ]; then
    _cpmerge $COMPILER_RT_DIR/bin bin
  fi
fi

case $TARGET in
  wasm*)  # note: wasm case must precede playbit case
    _cpmerge $BUILTINS_DIR/lib $lib/clang/lib
    ;;
  *linux|*playbit)
    _cpmerge $BUILTINS_DIR/lib    $lib/clang/lib
    _cpmerge $COMPILER_RT_DIR/lib $lib/clang/lib
    ;;
  *macos*)
    # Clang's darwin toolchain has a complicated filename scheme for rt libs:
    # - treats builtins specially by not appending its name,
    #   i.e. libclang_rt.osx.a not libclang_rt.builtins_osx.a
    # - appends "_osx" to all library names except builtins which gets "osx" appended
    # - appends "_dynamic" to shared libraries
    mkdir -p $lib/clang/lib
    cp -v $BUILTINS_DIR/lib/libclang_rt.builtins.a $lib/clang/lib/libclang_rt.osx.a
    _cpmerge $COMPILER_RT_DIR/lib                  $lib/clang/lib
    ;;
esac
