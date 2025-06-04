#!/bin/bash

PATCH=false
CLEAN=false
SLOW=false

while [[ $# -gt 0 ]]; do case "$1" in
  -h|--help)
    cat <<- _HELP_
usage: $0 [options]
options:
  --patch         Run llvm-reapply-patches.sh (uesful for testing out new patches)
  --clean         Clean build artifacts (slow!)
  --slow          Disables extra flags to build.sh to speed up iteration time
  -h, --help      Show help and exit
_HELP_
    exit ;;
  --patch) PATCH=true; shift ;;
  --clean) CLEAN=true; shift ;;
  --slow)  SLOW=true; shift ;;
  -*) echo "unknown option $1 (see $0 --help)" >&2; exit 1; ;;
esac; done

if $CLEAN; then
    rm -rf ./build-target
    rm -rf ./packages
fi

if $PATCH; then
    ./llvm-reapply-patches.sh
fi

flags="--no-cleanup --no-archive --no-native-toolchain"
if $SLOW; then
    flags=""
fi
./build.sh --sysroot-target=aarch64-playbit aarch64-playbit $flags --rebuild-llvm

rm -rf ../playbit/llvm/*
mkdir -p ../playbit/llvm
cp -r ./packages/compiler-rt-aarch64-playbit ../playbit/llvm/
cp -r ./packages/sysroot-aarch64-playbit     ../playbit/llvm/
cp -r ./packages/libcxx-aarch64-playbit      ../playbit/llvm/
cp -r ./packages/toolchain-aarch64-playbit   ../playbit/llvm/
