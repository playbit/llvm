BUILDDIR=$LIBCXX_DIR/build
DESTDIR=$LIBCXX_DIR

rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"
_pushd "$BUILDDIR"

LIBUNWIND=$LLVM_STAGE2_SRC/libunwind
LIBCXXABI=$LLVM_STAGE2_SRC/libcxxabi
LIBCXX=$LLVM_STAGE2_SRC/libcxx

# TARGET_TRIPLES=( aarch64-unknown-linux-musl )
# TARGET_TRIPLES=( wasm32-unknown-wasi )


# find sources
GENERIC_SOURCES=()
WASM_SOURCES=()
NON_WASM_SOURCES=()
EXPERIMENTAL_SOURCES=()
ARM_SOURCES=()
APPLE_SOURCES=()

# libunwind sources
for name in $(cd "$LIBUNWIND/src" && find . -type f -name '*.[csS]' -o -name '*.cpp'); do
  case "$name" in
    *EHABI*)       ARM_SOURCES+=( "$LIBUNWIND/src/$name" ) ;;
    *AppleExtras*) APPLE_SOURCES+=( "$LIBUNWIND/src/$name" ) ;;
    *AIXExtras*)   ;;
    *)             NON_WASM_SOURCES+=( "$LIBUNWIND/src/$name" ) ;;
  esac
done

# libc++abi sources (from libcxxabi/src/CMakeLists.txt)
GENERIC_SOURCES+=(
  $LIBCXXABI/src/cxa_aux_runtime.cpp \
  $LIBCXXABI/src/cxa_default_handlers.cpp \
  $LIBCXXABI/src/cxa_demangle.cpp \
  $LIBCXXABI/src/cxa_exception_storage.cpp \
  $LIBCXXABI/src/cxa_guard.cpp \
  $LIBCXXABI/src/cxa_handlers.cpp \
  $LIBCXXABI/src/cxa_vector.cpp \
  $LIBCXXABI/src/cxa_virtual.cpp \
  $LIBCXXABI/src/stdlib_exception.cpp \
  $LIBCXXABI/src/stdlib_stdexcept.cpp \
  $LIBCXXABI/src/stdlib_typeinfo.cpp \
  $LIBCXXABI/src/abort_message.cpp \
  $LIBCXXABI/src/fallback_malloc.cpp \
  $LIBCXXABI/src/private_typeinfo.cpp \
)
# if LIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS:
GENERIC_SOURCES+=( $LIBCXXABI/src/stdlib_new_delete.cpp )
# if LIBCXXABI_ENABLE_EXCEPTIONS
NON_WASM_SOURCES+=(
  $LIBCXXABI/src/cxa_exception.cpp \
  $LIBCXXABI/src/cxa_personality.cpp \
)
# if !LIBCXXABI_ENABLE_EXCEPTIONS
WASM_SOURCES+=( $LIBCXXABI/src/cxa_noexception.cpp )
# if LIBCXXABI_ENABLE_THREADS and UNIX and !APPLE
NON_WASM_SOURCES+=( $LIBCXXABI/src/cxa_thread_atexit.cpp )

# libc++ sources (from libcxx/src/CMakeLists.txt)
for name in $(cd "$LIBCXX/src" && find . -type f -name '*.[csS]' -o -name '*.cpp'); do
  name=${name:2} # ./x => x
  case "$name" in
  filesystem/int128_builtins.cpp)
    # skip int128_builtins.cpp; it provides __muloti4 which is already provided by librt.
    # Also crashes on Windows according to https://github.com/ziglang/zig/issues/10719
    ;;
  */ibm/*|*/solaris/*|*/win32/*|*/libdispatch.cpp)
    ;;
  experimental/*)
    EXPERIMENTAL_SOURCES+=( "$LIBCXX/src/$name" )
    ;;
  filesystem/*)
    NON_WASM_SOURCES+=( "$LIBCXX/src/$name" )
    ;;
  *)
    GENERIC_SOURCES+=( "$LIBCXX/src/$name" )
    ;;
  esac
done


# Generate __config_site file
# See libcxx/include/__config_site.in
# See libcxx/include/CMakeLists.txt & libcxx/CMakeLists.txt
LIBCXX_ABI_VERSION=2
mkdir -p include
cat << END > include/__config_site
#ifndef _LIBCPP___CONFIG_SITE
#define _LIBCPP___CONFIG_SITE

#define _LIBCPP_ABI_VERSION $LIBCXX_ABI_VERSION
#define _LIBCPP_ABI_NAMESPACE __$LIBCXX_ABI_VERSION
//undef _LIBCPP_ABI_FORCE_ITANIUM
//undef _LIBCPP_ABI_FORCE_MICROSOFT
#ifdef __wasm__
  #define _LIBCPP_HAS_NO_THREADS
  #define _LIBCPP_NO_EXCEPTIONS
#endif
//undef _LIBCPP_HAS_NO_MONOTONIC_CLOCK
#define _LIBCPP_HAS_MUSL_LIBC
//undef _LIBCPP_HAS_THREAD_API_PTHREAD
//undef _LIBCPP_HAS_THREAD_API_EXTERNAL
//undef _LIBCPP_HAS_THREAD_API_WIN32
#ifdef __wasm__
  #define _LIBCPP_DISABLE_VISIBILITY_ANNOTATIONS
#endif
#define _LIBCPP_HAS_NO_VENDOR_AVAILABILITY_ANNOTATIONS
//undef _LIBCPP_NO_VCRUNTIME
//undef _LIBCPP_TYPEINFO_COMPARISON_IMPLEMENTATION
//undef _LIBCPP_HAS_NO_FILESYSTEM
//undef _LIBCPP_HAS_NO_RANDOM_DEVICE
//undef _LIBCPP_HAS_NO_LOCALIZATION
//undef _LIBCPP_HAS_NO_WIDE_CHARACTERS
#define _LIBCPP_ENABLE_ASSERTIONS_DEFAULT 0
#define _LIBCPP_DISABLE_EXTERN_TEMPLATE

// PSTL backends
#ifdef __wasm__
  #define _LIBCPP_PSTL_CPU_BACKEND_SERIAL
#else
  #define _LIBCPP_PSTL_CPU_BACKEND_THREAD
#endif
//undef _LIBCPP_PSTL_CPU_BACKEND_LIBDISPATCH

// Hardening
#ifdef __wasm__
  #define _LIBCPP_ENABLE_HARDENED_MODE_DEFAULT 0
#else
  #define _LIBCPP_ENABLE_HARDENED_MODE_DEFAULT 1
#endif
#define _LIBCPP_ENABLE_DEBUG_MODE_DEFAULT 0

#endif
END


# generate build files
GENERIC_CFLAGS=(
  -fPIC -O2 -DNDEBUG "-resource-dir=$BUILTINS_DIR/" \
  -nostdlib \
  -funwind-tables \
  -Wno-user-defined-literals \
  -faligned-allocation \
  -fno-modules \
)
GENERIC_CXXFLAGS=( # in addition to GENERIC_CFLAGS
  -std=c++20 \
  -nostdinc++ \
  -nostdlib++ \
)
GENERIC_LIBCXXABI_CFLAGS=(
  -I$LIBCXX/src \
  -I$LIBCXXABI/src \
  -I$LIBCXXABI/include \
  -I$LIBUNWIND/include \
  -I$LIBCXX/include \
  -D_LIBCXXABI_BUILDING_LIBRARY \
  -D_LIBCPP_BUILDING_LIBRARY \
)
GENERIC_LIBCXX_CFLAGS=(
  -I$LIBCXX/src \
  -I$LIBCXX/include \
  -I$LIBCXXABI/include \
  -DLIBCXX_BUILDING_LIBCXXABI \
  -D_LIBCPP_BUILDING_LIBRARY \
)
GENERIC_LIBUNWIND_CFLAGS=(
  -fomit-frame-pointer \
  -fvisibility=hidden \
  -I$LIBUNWIND/include \
  -fno-exceptions \
  -fno-rtti \
)
# GENERIC_LIBCXXABI_CFLAGS+=( -DHAVE___CXA_THREAD_ATEXIT_IMPL ) # not in musl
LIBUNWIND_OBJECTS=()
LIBCXXABI_OBJECTS=()
LIBCXX_OBJECTS=()
_gen_cc_buildrule() { # <srcfile>
  local src=$1
  local dst=${src##$LLVM_STAGE2_SRC/}
  dst=\$objdir/${dst//\//__}.o
  local rule=cc
  [[ "$src" == *.cpp ]] && rule=cxx
  echo "build $dst: $rule $src" >> $NF
  case "$src" in
    "$LIBUNWIND/"*)
      LIBUNWIND_OBJECTS+=( $dst )
      echo "  FLAGS=\$libunwind_flags" >> $NF
      ;;
    "$LIBCXXABI/"*)
      LIBCXXABI_OBJECTS+=( $dst )
      echo "  FLAGS=\$libcxxabi_flags" >> $NF
      ;;
    "$LIBCXX/"*)
      LIBCXX_OBJECTS+=( $dst )
      echo "  FLAGS=\$libcxx_flags" >> $NF
      ;;
    *) _err "unexpected src=$src" ;;
  esac
}
_gen_buildrules() { # <srcfile> ...
  echo >> $NF
  for src in "$@"; do
    _gen_cc_buildrule $src
  done
}
for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  LIBUNWIND_OBJECTS=()
  LIBCXXABI_OBJECTS=()
  LIBCXX_OBJECTS=()
  CFLAGS="--target=$TARGET_TRIPLE --sysroot=$BUILD_DIR_S2/sysroot-$TARGET_TRIPLE"
  CXXFLAGS="--target=$TARGET_TRIPLE --sysroot=$BUILD_DIR_S2/sysroot-$TARGET_TRIPLE"
  CFLAGS="$CFLAGS -I./include-$TARGET_TRIPLE ${GENERIC_CXXFLAGS[@]}"
  CXXFLAGS="$CXXFLAGS -I./include ${GENERIC_CXXFLAGS[@]}"
  CXXFLAGS="$CXXFLAGS -isystem$BUILD_DIR_S2/sysroot-$TARGET_TRIPLE/include"
  CXXFLAGS="$CXXFLAGS -isystem$S1_CLANGRES_DIR/include"
  CXXFLAGS="$CXXFLAGS ${GENERIC_CFLAGS[@]}"
  CFLAGS="$CFLAGS ${GENERIC_CFLAGS[@]}"
  # note: don't build with LTO, even when ENABLE_LTO=true

  LIBUNWIND_CFLAGS=${GENERIC_LIBUNWIND_CFLAGS[@]}
  LIBCXXABI_CFLAGS=${GENERIC_LIBCXXABI_CFLAGS[@]}
  LIBCXX_CFLAGS=${GENERIC_LIBCXX_CFLAGS[@]}
  if [[ $TARGET_TRIPLE == *wasm* ]]; then
    CFLAGS="$CFLAGS -fno-exceptions"
    CXXFLAGS="$CXXFLAGS -fno-exceptions"
    CFLAGS="$CFLAGS -fvisibility=hidden -fvisibility-inlines-hidden"
    CXXFLAGS="$CXXFLAGS -fvisibility=hidden -fvisibility-inlines-hidden"
    LIBCXXABI_CFLAGS="$LIBCXXABI_CFLAGS -D_LIBCXXABI_HAS_NO_THREADS"
    # if LIBCXXABI_HERMETIC_STATIC_LIBRARY:
    LIBCXXABI_CFLAGS="$LIBCXXABI_CFLAGS -D_LIBCXXABI_DISABLE_VISIBILITY_ANNOTATIONS"
    # if LIBCXXABI_HERMETIC_STATIC_LIBRARY and LIBCXXABI_ENABLE_NEW_DELETE_DEFINITIONS:
    LIBCXXABI_CFLAGS="$LIBCXXABI_CFLAGS -fvisibility-global-new-delete-hidden"
  else
    LIBCXXABI_CFLAGS="$LIBCXXABI_CFLAGS -D_LIBCPP_HAS_THREAD_API_PTHREAD"
  fi
  NF=build-$TARGET_TRIPLE.ninja
  echo "Generating ${PWD##$PWD0/}/$NF"
  cat << _END > $NF
ninja_required_version = 1.3
builddir = .
objdir = \$builddir/obj
libunwind_flags = $LIBUNWIND_CFLAGS
libcxxabi_flags = $LIBCXXABI_CFLAGS
libcxx_flags = $LIBCXX_CFLAGS
rule cc
  command = $CC -MMD -MF \$out.d $CFLAGS -std=c11 \$FLAGS -c \$in -o \$out
  depfile = \$out.d
  description = cc \$in
rule cxx
  command = $CXX -MMD -MF \$out.d $CXXFLAGS \$FLAGS -c \$in -o \$out
  depfile = \$out.d
  description = cc \$in
rule ar
  command = $AR crs \$out \$in
  description = ar \$out
_END
  echo >> $NF
  _gen_buildrules ${GENERIC_SOURCES[@]}
  if [[ $TARGET_TRIPLE == wasm* ]]; then
    _gen_buildrules ${WASM_SOURCES[@]}
  else
    _gen_buildrules ${NON_WASM_SOURCES[@]}
  fi
  if [[ $TARGET_TRIPLE == aarch64-* ]]; then
    _gen_buildrules ${ARM_SOURCES[@]}
  fi
  echo >> $NF
  if [ ${#LIBUNWIND_OBJECTS[@]} -gt 0 ]; then
    echo "build libunwind-$TARGET_TRIPLE.a: ar ${LIBUNWIND_OBJECTS[*]}" >> $NF
  fi
  echo "build libc++abi-$TARGET_TRIPLE.a: ar ${LIBCXXABI_OBJECTS[*]}" >> $NF
  echo "build libc++-$TARGET_TRIPLE.a: ar ${LIBCXX_OBJECTS[*]}" >> $NF
done


# build
for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  libs=( libc++abi-$TARGET_TRIPLE.a libc++-$TARGET_TRIPLE.a )
  [[ $TARGET_TRIPLE != wasm* ]] && libs+=( libunwind-$TARGET_TRIPLE.a )
  NINJA_STATUS="[libc++ $TARGET_TRIPLE %f/%t] " \
  ninja -f build-$TARGET_TRIPLE.ninja ${libs[@]}
done


# install
rm -rf "$DESTDIR/include"
mkdir -p "$DESTDIR/include/c++"
echo "copydir: ${LIBCXX##$PWD0/}/include -> ${DESTDIR##$PWD0/}/include/c++/v1"
cp -a $LIBCXX/include "$DESTDIR/include/c++/v1"

install -v -m0644 "$LIBCXXABI"/include/*.h "$DESTDIR/include/c++/v1"

install -v -m0644 include/__config_site "$DESTDIR/include/c++/v1/__config_site"

install -v -m0644 "$LIBUNWIND/include/__libunwind_config.h" "$DESTDIR/include"
install -v -m0644 "$LIBUNWIND/include/libunwind.h"          "$DESTDIR/include"
install -v -m0644 "$LIBUNWIND/include/unwind.h"             "$DESTDIR/include"
install -v -m0644 "$LIBUNWIND/include/unwind_arm_ehabi.h"   "$DESTDIR/include"
install -v -m0644 "$LIBUNWIND/include/unwind_itanium.h"     "$DESTDIR/include"

for TARGET_TRIPLE in ${TARGET_TRIPLES[@]}; do
  mkdir -p "$DESTDIR/lib-$TARGET_TRIPLE"
  libs=( libc++abi libc++ ); [[ $TARGET_TRIPLE != wasm* ]] && libs+=( libunwind )
  for lib in ${libs[@]}; do
    echo "install: ${DESTDIR##$PWD0/}/lib-$TARGET_TRIPLE/$lib.a"
    mv $lib-$TARGET_TRIPLE.a "$DESTDIR/lib-$TARGET_TRIPLE/$lib.a"
  done
done

find "$DESTDIR/include" \( -name '.*' -o -name '*.txt' -o -name '*.in' \) -delete

cd "$DESTDIR"
$NO_CLEANUP || rm -rf "$BUILDDIR"
