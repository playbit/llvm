#!/bin/bash
set -euo pipefail
eval $(grep -E '^LLVM_VERSION=' build.sh)
cd "$(dirname "$0")/build/s2-llvm-$LLVM_VERSION"

git reset --hard patch1~1
for f in $(echo ../../patches-llvm/*.patch); do
  patch -p1 < "$f"
done
git commit -a -m "initial patches"
git tag -f patch1
