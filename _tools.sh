cd "$TOOLS"

CFLAGS="-Wall -Wextra -Wno-unused -Wno-unused-parameter -std=c11 -O2 -g"
[ "$(uname -s)" = Linux ] && CFLAGS="$CFLAGS -static"

cc $CFLAGS -c toolslib.c -o toolslib.o
cc $CFLAGS toolslib.o cpmerge.c -o cpmerge
cc $CFLAGS toolslib.o dedup-target-files.c -o dedup-target-files
