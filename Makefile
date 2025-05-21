all: patch llvm install

patch:
	./llvm-reapply-patches.sh

llvm:
	./build.sh --sysroot-target=aarch64-playbit aarch64-playbit --no-cleanup --rebuild-llvm

install:
	rm -rf ../playbit/llvm/*
	mkdir -p ../playbit/llvm
	cp -r ./packages/compiler-rt-aarch64-playbit ../playbit/llvm/
	cp -r ./packages/sysroot-aarch64-playbit     ../playbit/llvm/
	cp -r ./packages/libcxx-aarch64-playbit      ../playbit/llvm/
	cp -r ./packages/toolchain-aarch64-playbit   ../playbit/llvm/

.PHONY: all patch llvm install
