BUILDDIR=$LIBUNWIND_DIR/build
DESTDIR=$LIBUNWIND_DIR
SRCDIR=$LLVM_STAGE2_SRC/libunwind


# libunwind is not available for wasm
TARGET_TRIPLES_TO_BUILD=()
for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  [[ $TARGET_TRIPLE != wasm* ]] && TARGET_TRIPLES_TO_BUILD+=( $TARGET_TRIPLE )
done


# find sources
COMMON_SOURCES=()
ARM_SOURCES=()
APPLE_SOURCES=()
_pushd "$SRCDIR/src"
for name in $(find . -type f -name '*.[csS]' -o -name '*.cpp'); do
  path=$SRCDIR/src/$name
  case "$name" in
    *EHABI*)       ARM_SOURCES+=( "$path" ) ;;
    *AppleExtras*) APPLE_SOURCES+=( "$path" ) ;;
    *AIXExtras*)   ;;
    *)             COMMON_SOURCES+=( "$path" ) ;;
  esac
done
_popd


# generate build files
ALL_OBJECTS=()
_gen_cc_buildrule() { # <srcfile>
  local dst=\$objdir/$(basename "$1").o
  ALL_OBJECTS+=( $dst )
  echo "build $dst: cc $1" >> $NF
}
_gen_buildrules() { # <srcfile> ...
  echo >> $NF
  for src in "$@"; do
    _gen_cc_buildrule $src
  done
}
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
_pushd "$BUILDDIR"
for TARGET_TRIPLE in ${TARGET_TRIPLES_TO_BUILD[@]}; do
  ALL_OBJECTS=()
  CFLAGS="--target=$TARGET_TRIPLE --sysroot=$BUILD_DIR_S2/sysroot-$TARGET_TRIPLE"
  CFLAGS="$CFLAGS -resource-dir=$BUILTINS_DIR/"
  CFLAGS="$CFLAGS -fPIC -fomit-frame-pointer -fvisibility=hidden -O2"
  CFLAGS="$CFLAGS -I$SRCDIR/include"
  NF=build-$TARGET_TRIPLE.ninja
  echo "Generating ${PWD##$PWD0/}/$NF"
  cat << _END > $NF
ninja_required_version = 1.3
builddir = .
objdir = \$builddir/obj
rule cc
  command = $CC -MMD -MF \$out.d $CFLAGS \$FLAGS -c \$in -o \$out
  depfile = \$out.d
  description = cc \$in
rule ar
  command = $AR crs \$out \$in
  description = ar \$out
_END
  echo >> $NF
  _gen_buildrules ${COMMON_SOURCES[@]}
  if [[ $TARGET_TRIPLE == aarch64-* ]]; then
    _gen_buildrules ${ARM_SOURCES[@]}
  fi
  # TARGET_ARCH=${TARGET_TRIPLE%%-*}
  echo "build libunwind-$TARGET_TRIPLE.a: ar ${ALL_OBJECTS[*]}" >> $NF
  echo "default libunwind-$TARGET_TRIPLE.a" >> $NF
done


# build
for TARGET_TRIPLE in ${TARGET_TRIPLES_TO_BUILD[@]}; do
  ninja -f build-$TARGET_TRIPLE.ninja
done


# install
# note: headers are target-independent
mkdir -p "$DESTDIR/include"
install -v -m0644 "$SRCDIR/include/__libunwind_config.h" "$DESTDIR/include/"
install -v -m0644 "$SRCDIR/include/libunwind.h"          "$DESTDIR/include/"
install -v -m0644 "$SRCDIR/include/unwind.h"             "$DESTDIR/include/"
install -v -m0644 "$SRCDIR/include/unwind_arm_ehabi.h"   "$DESTDIR/include/"
install -v -m0644 "$SRCDIR/include/unwind_itanium.h"     "$DESTDIR/include/"

for TARGET_TRIPLE in ${TARGET_TRIPLES_TO_BUILD[@]}; do
  mkdir -p "$DESTDIR/lib-$TARGET_TRIPLE"
  install -v -m0644 libunwind-$TARGET_TRIPLE.a "$DESTDIR/lib-$TARGET_TRIPLE/libunwind.a"
done
