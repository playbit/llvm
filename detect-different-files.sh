#!/bin/sh
#
# usage: $0 <base_a> <base_b> <common_subdir>
#
set -euo pipefail
base_a=${1:-build-x86_64-unknown-linux-musl/compiler-rt-x86_64-unknown-linux-musl}
base_b=${2:-build-x86_64-unknown-linux-musl/compiler-rt-aarch64-unknown-linux-musl}
common_subdir=${3:-share}
for a in $base_a/$common_subdir/*; do
  name=$(basename "$a")
  b=$base_b/$common_subdir/$name
  if [ ! -f "$b" ]; then
    echo "$common_subdir/$name: MISSING in $base_b" >&2
    continue
  fi
  sums=$(sha256sum "$a" "$b")
  asum=$(echo $sums | cut -d' ' -f1)
  bsum=$(echo $sums | cut -d' ' -f3)
  if [ "$asum" != "$bsum" ]; then
    echo "$common_subdir/$name: DIFFERS" >&2
  else
    echo "$common_subdir/$name: identical"
  fi
done
