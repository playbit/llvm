#!/bin/bash

NO_PATCH=false
CLEAN=false

while [[ $# -gt 0 ]]; do case "$1" in
  --no-patch) NO_PATCH=true; shift ;;
  --clean) CLEAN=true; shift ;;
  -*) _err "unknown option $1 (see $0 -help)" ;;
esac; done

if $CLEAN; then
    rm -rf ./build-target
    rm -rf ./packages
fi

if ! $NO_PATCH; then
    echo ./llvm-reapply-patches.sh
fi

./build.sh --sysroot-target=aarch64-playbit aarch64-playbit --no-cleanup --no-archive --no-native-toolchain --rebuild-llvm

rm -rf ../playbit/llvm/*
mkdir -p ../playbit/llvm
cp -r ./packages/compiler-rt-aarch64-playbit ../playbit/llvm/
cp -r ./packages/sysroot-aarch64-playbit     ../playbit/llvm/
cp -r ./packages/libcxx-aarch64-playbit      ../playbit/llvm/
cp -r ./packages/toolchain-aarch64-playbit   ../playbit/llvm/
