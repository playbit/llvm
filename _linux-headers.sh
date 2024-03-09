tools/build.sh

LOGFILE=$BUILD_DIR_GENERIC/$(basename "${BASH_SOURCE[0]}" .sh)-$TARGET_TRIPLE.log
rm -f "$LOGFILE"

SRCDIRS=( linux-headers/any-linux )

case "$TARGET_TRIPLE" in
  x86_64-*) SRCDIRS+=( linux-headers/x86_64-linux );;
  aarch64-*) SRCDIRS+=( linux-headers/aarch64-linux );;
esac

for dir in ${SRCDIRS[@]}; do
  echo "cpmerge $dir/include -> ${SYSROOT##$PWD0/}/include"
  if ! tools/cpmerge -v -f $dir/include $SYSROOT/include >> "$LOGFILE"; then
    cat "$LOGFILE" >&2
    exit 1
  fi
done
