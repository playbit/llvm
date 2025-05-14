#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/build/s2-llvm-17.0.3"

git reset --hard patch1~1
for f in $(echo ../../patches-llvm/*.patch); do
  patch -p1 < "$f"
done
git commit -a -m "initial patches"
git tag -f patch1
