echo "copy ${LLVM_STAGE1_SRC##$PWD0/} -> ${LLVM_STAGE2_SRC##$PWD0/}"
rm -rf "$LLVM_STAGE2_SRC"
mkdir -p "$(dirname "$LLVM_STAGE2_SRC")"

if [ $HOST_SYS = macos ]; then
  cp -a -c "$LLVM_STAGE1_SRC" "$LLVM_STAGE2_SRC"
else
  cp -a "$LLVM_STAGE1_SRC" "$LLVM_STAGE2_SRC"
fi

cd "$LLVM_STAGE2_SRC"

if $LLVM_SRC_CHANGE_TRACKING_ENABLED; then
  echo "git init (LLVM_SRC_CHANGE_TRACKING_ENABLED)"
  rm -rf .git
  git init
  git config core.safecrlf false
  git add .
  git commit -m "import llvm $LLVM_VERSION"
  git tag base
fi

for f in $(echo "$LLVM_PATCHDIR"/*.patch | sort); do
  echo "applying patch ${f##$PWD0/}"
  patch -p1 < "$f"
done

_symlink clang/lib/Driver/ToolChains/Playbit.h   $LLVM_PATCHDIR/Playbit.h
_symlink clang/lib/Driver/ToolChains/Playbit.cpp $LLVM_PATCHDIR/Playbit.cpp

if $LLVM_SRC_CHANGE_TRACKING_ENABLED; then
  git commit -a -m "initial patches"
  git tag patch1
fi
