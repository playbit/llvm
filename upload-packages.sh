#!/bin/sh
cd "$(dirname "$0")"
set -eo pipefail
eval $(grep -E '^(LLVM_VERSION|PKG_VERSION)=' build.sh)

DRYRUN=false

while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help)
    cat <<- _HELP_
usage: $0 [--dryrun]
options:
  --dryrun    Just print what would happen
  -h, --help  Show help and exit
_HELP_
    exit ;;
  --dryrun) DRYRUN=true; shift ;;
  -*) _err "unknown option $1 (see $0 -help)" ;;
  *) _err "unexpected argument $1 (see $0 -help)" ;;
esac; done

WFCP_ARGS=( -v --sha256 --expires=2024-01-01T00:00:00Z --cache-control=max-age=60 )
for f in packages/llvm-$LLVM_VERSION-$PKG_VERSION-*.tar.xz; do
  if $DRYRUN; then
    echo "[dryrun] webfiles cp ${WFCP_ARGS[@]} '${f##$PWD0/}' 'llvm/$(basename "$f")'"
  else
    ../playbit/tools/webfiles cp "${WFCP_ARGS[@]}" "${f##$PWD0/}" "llvm/$(basename "$f")" &
  fi
done
wait
