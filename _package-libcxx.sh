lib=lib; [[ $TARGET == *macos* ]] && lib=usr/lib
_cpmerge $LIBCXX_DIR/lib         $lib
_cpmerge $LIBCXX_DIR/usr/include usr/include
