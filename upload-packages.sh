#!/bin/sh
cd "$(dirname "$0")"
set -eo pipefail

if [ -z "${LLVM_VERSION:-}" -a -z "${PKG_VERSION:-}" ]; then
    eval $(grep -E '^(LLVM_VERSION|PKG_VERSION)=' build.sh)
fi

PKGUPLOAD=${PKGUPLOAD:-../engine/tools/pkg-upload}

case "${1:-}" in
    -h|--help)
        cat <<- _HELP_
Calls $PKGUPLOAD [<option> ...] packages/llvm-$LLVM_VERSION-$PKG_VERSION-*.tar.xz
See $PKGUPLOAD for <option>s
_HELP_
        exit ;;
esac

exec bash "$PKGUPLOAD" "$@" packages/llvm-$LLVM_VERSION-$PKG_VERSION-*.tar.xz
