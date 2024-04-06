#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f cpmerge ] || [ ! -f dedup-target-files ] ||
   [ toolslib.c -nt toolslib.o ] ||
   [ cpmerge.c -nt cpmerge ] ||
   [ cpmerge.c -nt toolslib.o ] ||
   [ dedup-target-files.c -nt dedup-target-files ] ||
   [ dedup-target-files.c -nt toolslib.o ]
then
  CC=${CC:-cc}
  CFLAGS="-Wall -std=c11 -O2 -g"
  case "$(uname -s)" in
    Linux) CFLAGS="$CFLAGS -static" ;;
    Darwin) if [ -n "$MAC_SDK" ]; then CFLAGS="$CFLAGS --sysroot=$MAC_SDK"; fi
  esac
  set -x
  $CC $CFLAGS -c toolslib.c -o toolslib.o
  $CC $CFLAGS toolslib.o cpmerge.c -o cpmerge
  $CC $CFLAGS toolslib.o dedup-target-files.c -o dedup-target-files
fi
