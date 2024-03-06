tools/build.sh

LOGFILE=$BUILD_DIR_GENERIC/$(basename "${BASH_SOURCE[0]}" .sh).log
rm -f "$LOGFILE"

for dir in \
  sysroot/any-linux \
  sysroot/aarch64-linux \
  sysroot/x86_64-linux \
;do
  echo "cpmerge $dir -> ${SYSROOT##$PWD0/}/usr/include"
  if ! tools/cpmerge -v -f $dir $SYSROOT/usr/include >> "$LOGFILE"; then
    cat "$LOGFILE" >&2
    exit 1
  fi
done
