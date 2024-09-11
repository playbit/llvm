#!/bin/sh
#
# Run this script to generate LLVM patches (by looking at 'git diff' of LLVM source)
#
set -euo pipefail
cd "$(dirname "$0")"
eval $(grep -E '^LLVM_VERSION=' build.sh)
_err() { echo "$0:" "$@" >&2; exit 1; }

LLVM_SRC=$PWD/build/s2-llvm-$LLVM_VERSION
LLVM_PATCHDIR=$PWD/patches-llvm

OPT_L=false

while [ $# -gt 0 ]; do case "$1" in
  -h|--help) cat << EOF
Generate patches of changes to ${LLVM_SRC##$PWD/} in ${LLVM_PATCHDIR##$PWD/}/
Usage: $0 [options]
options:
	-h, --help  Show help and exit
	-l          Only list modified files (don't create patches)
EOF
    exit 0 ;;
  -l) OPT_L=true; shift;;
  -*) _err "Unexpected option $1";;
  *) _err "Unexpected argument $1";;
esac; done


if $OPT_L; then
	echo "# git -C ${LLVM_SRC##$PWD/} diff base --name-only"
	exec git -C "$LLVM_SRC" diff base --name-only
fi


RECORDED_LOG=$(mktemp)
trap "rm -f '$RECORDED_LOG'" EXIT


mkpatch() { # <outfile> <comment> <srcfile> [<srcfile> ...]
	local OUTFILE=$LLVM_PATCHDIR/$1; shift
	local COMMENT=$1; shift
	echo "Generating ${OUTFILE##$PWD/}"

	if [ -z "$(git -C "$LLVM_SRC" diff base --name-only -- "$@")" ]; then
		echo "no changes to any files listed" >&2
		for f in "$@"; do
			if [ ! -e "$f" ]; then
				echo "$f: file not found" >&2
			fi
		done
		exit 1
	fi

	if [ -n "$COMMENT" ]; then
		echo "$COMMENT" > "$OUTFILE"
		echo >> "$OUTFILE"
	else
		rm -f "$OUTFILE"
	fi

	git -C "$LLVM_SRC" diff base -- "$@" >> "$OUTFILE"
	git -C "$LLVM_SRC" diff base --name-only -- "$@" >> "$RECORDED_LOG"
	# cat "$OUTFILE" | sed 's/^/\t/'; echo "————————————————————————————————————————"
}

# ————————————————————————————————————————————————————————————————————————————


mkpatch llvm-tests-dlclose.patch \
	"Disable dynamic lib tests for musl's dlclose() is noop" \
	llvm/unittests/Support/CMakeLists.txt


mkpatch llvm-tests-allocscore.patch \
	"on x86, this fails with a float comparison error even though the floats
are the same, because it does absolute eq" \
	llvm/unittests/CodeGen/RegAllocScoreTest.cpp


mkpatch llvm-stack-size.patch \
	"Patch-Source: https://github.com/chimera-linux/cports/blob/8c0359f31b9d888e59ced0320e93ca8ad79ba1f9/main/llvm/patches/0010-always-set-a-larger-stack-size-explicitly.patch
From 18e09846d9333b554e3dfbbd768ada6643bf92c0 Mon Sep 17 00:00:00 2001
From: Daniel Kolesa <daniel@octaforge.org>
Date: Sat, 27 Nov 2021 01:03:28 +0100
Subject: [PATCH 10/22] always set a larger stack size explicitly" \
	llvm/lib/Support/Threading.cpp


mkpatch llvm-fix-memory-mf_exec-on-aarch64.patch \
	"Fix failures in AllocationTests/MappedMemoryTest.* on aarch64:

Failing Tests (8):
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.AllocAndRelease/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.DuplicateNear/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.EnabledWrite/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.MultipleAllocAndRelease/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.SuccessiveNear/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.UnalignedNear/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.ZeroNear/3
    LLVM-Unit :: Support/./SupportTests/AllocationTests/MappedMemoryTest.ZeroSizeNear/3

Upstream-Issue: https://bugs.llvm.org/show_bug.cgi?id=14278#c10" \
	llvm/lib/Support/Unix/Memory.inc


mkpatch llvm-cmake-install-prefix.patch \
	"Starting with llvm14 the install prefix breaks via symlinks;
/lib/llvm14/lib/cmake/llvm/LLVMConfig.cmake goes up 3 directories to find
/lib/llvm14/include as LLVM_INCLUDE_DIRS, but to even use this cmake folder
at all it has to be symlinked to /lib/cmake/llvm .. so the directory it
instead uses is just /usr/include, which is not where the cmake includes are.
this hardcodes them to the install prefix we pass via cmake, which should
always be correct, and what cmake tries to autodetect anyway.

See also: https://reviews.llvm.org/D29969

This is supposedly fixed now, but for some reason it still isn't" \
	llvm/cmake/modules/CMakeLists.txt


mkpatch llvm-rust-feature-tables.patch \
	"Patch-Source: https://github.com/rust-lang/llvm-project/commit/0a157fd7a5f61973ffddf96b3d445a718193eb1a
From 0a157fd7a5f61973ffddf96b3d445a718193eb1a Mon Sep 17 00:00:00 2001
From: Cameron Hart <cameron.hart@gmail.com>
Date: Sun, 10 Jul 2016 23:55:53 +1000
Subject: [PATCH] [rust] Add accessors for MCSubtargetInfo CPU and Feature
 tables

This is needed for '-C target-cpu=help' and '-C target-feature=help' in rustc" \
	llvm/include/llvm/MC/MCSubtargetInfo.h


mkpatch compiler-rt-cmake.patch \
	"Allow COMPILER_RT_BUILD_CRT to be set" \
	compiler-rt/lib/builtins/CMakeLists.txt


mkpatch clang-darwin.patch \
	"Darwin toolchain" \
	clang/lib/Driver/ToolChains/Darwin.\*


mkpatch clang-wasm.patch \
	"WebAssembly toolchain" \
	clang/lib/Driver/ToolChains/WebAssembly.\*


mkpatch llvm-playbit.patch \
	"Playbit target" \
	llvm/include/llvm/TargetParser/Triple.h \
	llvm/lib/Analysis/TargetLibraryInfo.cpp \
	llvm/lib/TargetParser/Triple.cpp \
	llvm/lib/Transforms/Instrumentation/AddressSanitizer.cpp \
	llvm/lib/Transforms/Instrumentation/InstrProfiling.cpp \
	llvm/unittests/Support/Threading.cpp \


mkpatch clang-playbit.patch \
	"Playbit target" \
	clang/lib/Basic/Targets.cpp \
	clang/lib/Basic/Targets/OSTargets.h \
	clang/lib/CodeGen/Targets/X86.cpp \
	clang/lib/Driver/CMakeLists.txt \
	clang/lib/Driver/Driver.cpp \
	clang/lib/Driver/SanitizerArgs.cpp \
	clang/lib/Driver/ToolChain.cpp \
	clang/lib/Driver/ToolChains/Arch/ARM.cpp \
	clang/lib/Driver/ToolChains/Clang.cpp \
	clang/lib/Lex/InitHeaderSearch.cpp \


mkpatch lldb-playbit.patch \
	"Playbit target" \
	lldb/source/Plugins/ABI/AArch64/ABISysV_arm64.cpp \


# Note: Playbit toolchain is maintained as separate source files, Playbit.{cpp,h}


# ————————————————————————————————————————————————————————————————————————————
echo "Modified files successfully recorded in patches:"
sort -hf "$RECORDED_LOG" | sed 's/^/\t/'

# find files not recorded
A_LOG=$(mktemp)
B_LOG=$(mktemp)
trap "rm -f '$RECORDED_LOG' '$A_LOG' '$B_LOG'" EXIT
sort "$RECORDED_LOG" > "$A_LOG"
git -C "$LLVM_SRC" diff base --name-only | sort > "$B_LOG"
comm -3 "$A_LOG" "$B_LOG" > "$RECORDED_LOG"

if [ -s "$RECORDED_LOG" ]; then
	echo "Modified files NOT recorded in patches:"
	cat "$RECORDED_LOG"
	echo "Command to show differences:"
	while IFS= read line; do
		printf "\t%s %s\n" "git -C ${LLVM_SRC##$PWD/} diff base --" $line
	done < "$RECORDED_LOG"
else
	echo "OK: All changes to source files were recorded in patches."
fi
