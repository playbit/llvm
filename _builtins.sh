BUILDDIR=$BUILTINS_DIR-build
DESTDIR=$BUILTINS_DIR

_pushd "$LLVM_STAGE2_SRC/compiler-rt/lib/builtins"

#
# when upgrading compiler-rt to a new version, perform these manual steps:
# - open lib/builtins/CMakeLists.txt
# - update SOURCES arrays below with GENERIC_SOURCES + GENERIC_TF_SOURCES
#
GENERIC_SOURCES=( # cmake: GENERIC_SOURCES + GENERIC_TF_SOURCES
  absvdi2.c \
  absvsi2.c \
  absvti2.c \
  adddf3.c \
  addsf3.c \
  addvdi3.c \
  addvsi3.c \
  addvti3.c \
  apple_versioning.c \
  ashldi3.c \
  ashlti3.c \
  ashrdi3.c \
  ashrti3.c \
  bswapdi2.c \
  bswapsi2.c \
  clzdi2.c \
  clzsi2.c \
  clzti2.c \
  cmpdi2.c \
  cmpti2.c \
  comparedf2.c \
  comparesf2.c \
  ctzdi2.c \
  ctzsi2.c \
  ctzti2.c \
  divdc3.c \
  divdf3.c \
  divdi3.c \
  divmoddi4.c \
  divmodsi4.c \
  divmodti4.c \
  divsc3.c \
  divsf3.c \
  divsi3.c \
  divti3.c \
  extendsfdf2.c \
  extendhfsf2.c \
  extendhfdf2.c \
  ffsdi2.c \
  ffssi2.c \
  ffsti2.c \
  fixdfdi.c \
  fixdfsi.c \
  fixdfti.c \
  fixsfdi.c \
  fixsfsi.c \
  fixsfti.c \
  fixunsdfdi.c \
  fixunsdfsi.c \
  fixunsdfti.c \
  fixunssfdi.c \
  fixunssfsi.c \
  fixunssfti.c \
  floatdidf.c \
  floatdisf.c \
  floatsidf.c \
  floatsisf.c \
  floattidf.c \
  floattisf.c \
  floatundidf.c \
  floatundisf.c \
  floatunsidf.c \
  floatunsisf.c \
  floatuntidf.c \
  floatuntisf.c \
  fp_mode.c \
  int_util.c \
  lshrdi3.c \
  lshrti3.c \
  moddi3.c \
  modsi3.c \
  modti3.c \
  muldc3.c \
  muldf3.c \
  muldi3.c \
  mulodi4.c \
  mulosi4.c \
  muloti4.c \
  mulsc3.c \
  mulsf3.c \
  multi3.c \
  mulvdi3.c \
  mulvsi3.c \
  mulvti3.c \
  negdf2.c \
  negdi2.c \
  negsf2.c \
  negti2.c \
  negvdi2.c \
  negvsi2.c \
  negvti2.c \
  os_version_check.c \
  paritydi2.c \
  paritysi2.c \
  parityti2.c \
  popcountdi2.c \
  popcountsi2.c \
  popcountti2.c \
  powidf2.c \
  powisf2.c \
  subdf3.c \
  subsf3.c \
  subvdi3.c \
  subvsi3.c \
  subvti3.c \
  trampoline_setup.c \
  truncdfhf2.c \
  truncdfsf2.c \
  truncsfhf2.c \
  ucmpdi2.c \
  ucmpti2.c \
  udivdi3.c \
  udivmoddi4.c \
  udivmodsi4.c \
  udivmodti4.c \
  udivsi3.c \
  udivti3.c \
  umoddi3.c \
  umodsi3.c \
  umodti3.c \
  \
  addtf3.c \
  comparetf2.c \
  divtc3.c \
  divtf3.c \
  extenddftf2.c \
  extendhftf2.c \
  extendsftf2.c \
  fixtfdi.c \
  fixtfsi.c \
  fixtfti.c \
  fixunstfdi.c \
  fixunstfsi.c \
  fixunstfti.c \
  floatditf.c \
  floatsitf.c \
  floattitf.c \
  floatunditf.c \
  floatunsitf.c \
  floatuntitf.c \
  multc3.c \
  multf3.c \
  powitf2.c \
  subtf3.c \
  trunctfdf2.c \
  trunctfhf2.c \
  trunctfsf2.c \
  \
  clear_cache.c \
)
# TODO:
# - if target has __bf16: GENERIC_SOURCES+=( truncdfbf2.c truncsfbf2.c )
#   e.g. if_compiles($TARGET, "__bf16 f(__bf16 x) { return x; }")
DARWIN_SOURCES=( # cmake: if (APPLE) GENERIC_SOURCES+=...
  atomic_flag_clear.c \
  atomic_flag_clear_explicit.c \
  atomic_flag_test_and_set.c \
  atomic_flag_test_and_set_explicit.c \
  atomic_signal_fence.c \
  atomic_thread_fence.c \
)
X86_ARCH_SOURCES=( # these files are used on 32-bit and 64-bit x86
  cpu_model/x86.c \
  i386/fp_mode.c \
)
# Implement extended-precision builtins, assuming long double is 80 bits.
# long double is not 80 bits on Android or MSVC.
X86_80_BIT_SOURCES=(
  divxc3.c \
  fixxfdi.c \
  fixxfti.c \
  fixunsxfdi.c \
  fixunsxfsi.c \
  fixunsxfti.c \
  floatdixf.c \
  floattixf.c \
  floatundixf.c \
  floatuntixf.c \
  mulxc3.c \
  powixf2.c \
)
X86_64_SOURCES=(
  x86_64/floatdidf.c \
  x86_64/floatdisf.c \
  x86_64/floatundidf.S \
  x86_64/floatundisf.S \
)
X86_64_SOURCES+=( # cmake: if (NOT ANDROID)
  "${X86_80_BIT_SOURCES[@]}" \
  x86_64/floatdixf.c \
  x86_64/floatundixf.S \
)
# X86_64_SOURCES_WIN32=( # cmake: if (WIN32)
#   ${X86_64_SOURCES[@]} \
#   x86_64/chkstk.S \
#   x86_64/chkstk2.S \
# )
I386_SOURCES=(
  i386/ashldi3.S \
  i386/ashrdi3.S \
  i386/divdi3.S \
  i386/floatdidf.S \
  i386/floatdisf.S \
  i386/floatundidf.S \
  i386/floatundisf.S \
  i386/lshrdi3.S \
  i386/moddi3.S \
  i386/muldi3.S \
  i386/udivdi3.S \
  i386/umoddi3.S \
)
I386_SOURCES+=( # cmake: if (NOT ANDROID)
  i386/floatdixf.S \
  i386/floatundixf.S \
  "${X86_80_BIT_SOURCES[@]}" \
)
# I386_SOURCES_WIN32=( # cmake: if (WIN32)
#   ${I386_SOURCES[@]} \
#   i386/chkstk.S \
#   i386/chkstk2.S \
# )
ARM_SOURCES=(
  arm/fp_mode.c \
  arm/bswapdi2.S \
  arm/bswapsi2.S \
  arm/clzdi2.S \
  arm/clzsi2.S \
  arm/comparesf2.S \
  arm/divmodsi4.S \
  arm/divsi3.S \
  arm/modsi3.S \
  arm/sync_fetch_and_add_4.S \
  arm/sync_fetch_and_add_8.S \
  arm/sync_fetch_and_and_4.S \
  arm/sync_fetch_and_and_8.S \
  arm/sync_fetch_and_max_4.S \
  arm/sync_fetch_and_max_8.S \
  arm/sync_fetch_and_min_4.S \
  arm/sync_fetch_and_min_8.S \
  arm/sync_fetch_and_nand_4.S \
  arm/sync_fetch_and_nand_8.S \
  arm/sync_fetch_and_or_4.S \
  arm/sync_fetch_and_or_8.S \
  arm/sync_fetch_and_sub_4.S \
  arm/sync_fetch_and_sub_8.S \
  arm/sync_fetch_and_umax_4.S \
  arm/sync_fetch_and_umax_8.S \
  arm/sync_fetch_and_umin_4.S \
  arm/sync_fetch_and_umin_8.S \
  arm/sync_fetch_and_xor_4.S \
  arm/sync_fetch_and_xor_8.S \
  arm/udivmodsi4.S \
  arm/udivsi3.S \
  arm/umodsi3.S \
)
# thumb1_SOURCES is ignored (<armv7)
ARM_EABI_SOURCES=(
  arm/aeabi_cdcmp.S \
  arm/aeabi_cdcmpeq_check_nan.c \
  arm/aeabi_cfcmp.S \
  arm/aeabi_cfcmpeq_check_nan.c \
  arm/aeabi_dcmp.S \
  arm/aeabi_div0.c \
  arm/aeabi_drsub.c \
  arm/aeabi_fcmp.S \
  arm/aeabi_frsub.c \
  arm/aeabi_idivmod.S \
  arm/aeabi_ldivmod.S \
  arm/aeabi_memcmp.S \
  arm/aeabi_memcpy.S \
  arm/aeabi_memmove.S \
  arm/aeabi_memset.S \
  arm/aeabi_uidivmod.S \
  arm/aeabi_uldivmod.S \
)
# TODO: win32: ARM_MINGW_SOURCES
AARCH64_SOURCES=(
  cpu_model/aarch64.c \
  aarch64/fp_mode.c \
  aarch64/lse.S \
)
# TODO: mingw: AARCH64_MINGW_SOURCES=( aarch64/chkstk.S )

RISCV_SOURCES=(
  riscv/save.S \
  riscv/restore.S \
)
RISCV32_SOURCES=( riscv/mulsi3.S )
RISCV64_SOURCES=( riscv/muldi3.S )

# EXCLUDE_BUILTINS_VARS is a list of shell vars which in turn contains
# space-separated names of builtins to be excluded.
# The var names encodes the targets,
# e.g. "EXCLUDE_BUILTINS__macos" is for macos, any arch.
# e.g. "EXCLUDE_BUILTINS__macos__i386" is for macos, i386 only.
EXCLUDE_BUILTINS_VARS=()
#
# lib/builtins/Darwin-excludes/CMakeLists.txt
# cmake/Modules/CompilerRTDarwinUtils.cmake
#   macro(darwin_add_builtin_libraries)
#   function(darwin_find_excluded_builtins_list output_var)
# Note: The resulting names match source files without filename extension.
# For example, "addtf3" matches source file "addtf3.c".
EXCLUDE_APPLE_ARCHS_TO_CONSIDER=(i386 x86_64 arm64)
for d in Darwin-excludes; do
  for os in osx ios; do  # TODO: ios
    f=$d/$os.txt
    [ -f $f ] || continue
    sys=${os/osx/macos}
    var=EXCLUDE_BUILTINS__$sys
    declare $var=
    while read -r name; do
      declare $var="${!var} $name"
      declare EXCLUDE_FUN__any__${sys}__${name}=1
    done < $f
    [ -n "$var" ] && EXCLUDE_BUILTINS_VARS+=( $var )
    for arch in ${EXCLUDE_APPLE_ARCHS_TO_CONSIDER[@]}; do
      f=$(echo $d/${os}*-$arch.txt)
      [ -f $f ] || continue
      [[ "$f" != *"iossim"* ]] || continue
      var=EXCLUDE_BUILTINS__${sys}__${arch/arm64/aarch64}
      declare $var=
      while read -r name; do
        declare $var="${!var} $name"
        declare EXCLUDE_FUN__${arch}__${sys}__${name}=1
      done < $f
      [ -n "$var" ] && EXCLUDE_BUILTINS_VARS+=( $var )
    done
  done
done


rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"

# aarch64: GENERIC_SOURCES + AARCH64_SOURCES
# arm:     GENERIC_SOURCES + ARM_SOURCES (+ ARM_EABI_SOURCES if not win32)
# i386:    GENERIC_SOURCES + X86_ARCH_SOURCES + I386_SOURCES
# x86_64:  GENERIC_SOURCES + X86_ARCH_SOURCES + X86_64_SOURCES
# riscv32: GENERIC_SOURCES + RISCV_SOURCES + RISCV32_SOURCES
# riscv64: GENERIC_SOURCES + RISCV_SOURCES + RISCV64_SOURCES
# wasm32:  GENERIC_SOURCES
# wasm64:  GENERIC_SOURCES

AARCH64_SOURCES_DIR=aarch64
ARM_SOURCES_DIR=arm
ARM_EABI_SOURCES_DIR=arm_eabi
X86_ARCH_SOURCES_DIR=x86
I386_SOURCES_DIR=i386
X86_64_SOURCES_DIR=x86_64
RISCV_SOURCES_DIR=riscv
RISCV32_SOURCES_DIR=riscv32
RISCV64_SOURCES_DIR=riscv64
DARWIN_SOURCES_DIR=any-macos

_deps() { for f in "$1"/*.{h,inc}; do [ ! -f "$f" ] || echo $f; done; }

_copy ../../LICENSE.TXT                        "$BUILDDIR"/LICENSE.TXT
_cpd "${GENERIC_SOURCES[@]}"  $(_deps .)       "$BUILDDIR"
_cpd "${AARCH64_SOURCES[@]}"  $(_deps aarch64) "$BUILDDIR"/$AARCH64_SOURCES_DIR
_cpd "${ARM_SOURCES[@]}"      $(_deps arm)     "$BUILDDIR"/$ARM_SOURCES_DIR
_cpd "${ARM_EABI_SOURCES[@]}"                  "$BUILDDIR"/$ARM_EABI_SOURCES_DIR
_cpd "${X86_ARCH_SOURCES[@]}"                  "$BUILDDIR"/$X86_ARCH_SOURCES_DIR
_cpd "${I386_SOURCES[@]}"     $(_deps i386)    "$BUILDDIR"/$I386_SOURCES_DIR
_cpd "${X86_64_SOURCES[@]}"   $(_deps x86_64)  "$BUILDDIR"/$X86_64_SOURCES_DIR
_cpd "${RISCV_SOURCES[@]}"    $(_deps riscv)   "$BUILDDIR"/$RISCV_SOURCES_DIR
_cpd "${RISCV32_SOURCES[@]}"                   "$BUILDDIR"/$RISCV32_SOURCES_DIR
_cpd "${RISCV64_SOURCES[@]}"                   "$BUILDDIR"/$RISCV64_SOURCES_DIR
_cpd "${DARWIN_SOURCES[@]}"                    "$BUILDDIR"/$DARWIN_SOURCES_DIR

# update arrays to map to files in destdir
AARCH64_SOURCES=( "${AARCH64_SOURCES[@]/#*\//}" )
ARM_SOURCES=( "${ARM_SOURCES[@]/#*\//}" )
ARM_EABI_SOURCES=( "${ARM_EABI_SOURCES[@]/#*\//}" )
X86_ARCH_SOURCES=( "${X86_ARCH_SOURCES[@]/#*\//}" )
I386_SOURCES=( "${I386_SOURCES[@]/#*\//}" )
X86_64_SOURCES=( "${X86_64_SOURCES[@]/#*\//}" )
RISCV_SOURCES=( "${RISCV_SOURCES[@]/#*\//}" )
RISCV32_SOURCES=( "${RISCV32_SOURCES[@]/#*\//}" )
RISCV64_SOURCES=( "${RISCV64_SOURCES[@]/#*\//}" )
DARWIN_SOURCES=( "${DARWIN_SOURCES[@]/#*\//}" )

AARCH64_SOURCES=( "${AARCH64_SOURCES[@]/#/$AARCH64_SOURCES_DIR/}" )
ARM_SOURCES=( "${ARM_SOURCES[@]/#/$ARM_SOURCES_DIR/}" )
ARM_EABI_SOURCES=( "${ARM_EABI_SOURCES[@]/#/$ARM_EABI_SOURCES_DIR/}" )
X86_ARCH_SOURCES=( "${X86_ARCH_SOURCES[@]/#/$X86_ARCH_SOURCES_DIR/}" )
I386_SOURCES=( "${I386_SOURCES[@]/#/$I386_SOURCES_DIR/}" )
X86_64_SOURCES=( "${X86_64_SOURCES[@]/#/$X86_64_SOURCES_DIR/}" )
RISCV_SOURCES=( "${RISCV_SOURCES[@]/#/$RISCV_SOURCES_DIR/}" )
RISCV32_SOURCES=( "${RISCV32_SOURCES[@]/#/$RISCV32_SOURCES_DIR/}" )
RISCV64_SOURCES=( "${RISCV64_SOURCES[@]/#/$RISCV64_SOURCES_DIR/}" )
DARWIN_SOURCES=( "${DARWIN_SOURCES[@]/#/$DARWIN_SOURCES_DIR/}" )

AARCH64_SOURCES=( $(printf "%q\n" "${AARCH64_SOURCES[@]}" | sort -u) )
ARM_SOURCES=( $(printf "%q\n" "${ARM_SOURCES[@]}" | sort -u) )
ARM_EABI_SOURCES=( $(printf "%q\n" "${ARM_EABI_SOURCES[@]}" | sort -u) )
X86_ARCH_SOURCES=( $(printf "%q\n" "${X86_ARCH_SOURCES[@]}" | sort -u) )
I386_SOURCES=( $(printf "%q\n" "${I386_SOURCES[@]}" | sort -u) )
X86_64_SOURCES=( $(printf "%q\n" "${X86_64_SOURCES[@]}" | sort -u) )
RISCV_SOURCES=( $(printf "%q\n" "${RISCV_SOURCES[@]}" | sort -u) )
RISCV32_SOURCES=( $(printf "%q\n" "${RISCV32_SOURCES[@]}" | sort -u) )
RISCV64_SOURCES=( $(printf "%q\n" "${RISCV64_SOURCES[@]}" | sort -u) )
DARWIN_SOURCES=( $(printf "%q\n" "${DARWIN_SOURCES[@]}" | sort -u) )

for var in ${EXCLUDE_BUILTINS_VARS[@]}; do
  IFS=. read -r ign sys arch <<< "${var//__/.}"
  outfile="${arch:-any}-$sys.exclude"
  # echo "generate $(_relpath "$outfile")"
  echo ${!var} > "$outfile"
done

_popd

# —————————————————————————————————————————————————————————————————————————————
# generate build file

_pushd "$BUILDDIR"


ALL_OBJECTS=()

_gen_buildrule() { # <rule> <srcfile>
  local rule=$1
  local src=$2
  local dst=\$objdir/${src//\//.}.o
  ALL_OBJECTS+=( $dst )
  echo "build $dst: $rule $src" >> $NF
}

_gen_buildrules() { # <srcfile> ...
  echo >> $NF
  for src in "$@"; do
    _gen_buildrule cc $src
  done
}

_gen_buildrules_aarch64_lse() {
  local src=$1 # ie aarch64/lse.S
  local dst
  for pat in cas swp ldadd ldclr ldeor ldset; do
    for size in 1 2 4 8 16; do
      for model in 1 2 3 4; do
        dst=\$objdir/aarch64.lse_${pat}${size}_${model}.o
        ALL_OBJECTS+=( $dst )
        echo "build $dst: cc $src" >> $NF
        printf "  FLAGS = -DL_%s -DSIZE=%s -DMODEL=%s\n" $pat $size $model >> $NF
      done
    done
  done
}

CFLAGS="$CFLAGS -fPIC -fno-lto -fno-builtin -fomit-frame-pointer -fvisibility=hidden -O2"

case $TARGET in
  riscv*)
    # for riscv/int_mul_impl.inc, included by riscv{32,64}/muldi3.S
    CFLAGS="$CFLAGS -Iriscv"
    ;;
  aarch64*)
    # Assume target CPU has FEAT_LSE (CAS, atomic ops, SWP, etc.)
    # See https://learn.arm.com/learning-paths/servers-and-cloud-computing/lse/intro/
    # if (compiles("asm(\".arch armv8-a+lse\");asm(\"cas w0, w1, [x2]\");"))
    CFLAGS="$CFLAGS -DHAS_ASM_LSE=1"
    ;;
esac

NF=build.ninja
echo "Generating ${PWD##$PWD0/}/$NF"

cat << _END > $NF
ninja_required_version = 1.3
builddir = build
objdir = \$builddir/obj
cflags = $CFLAGS -I. -I"$LLVM_STAGE2_SRC"/compiler-rt/lib/builtins/cpu_model

rule cc
  command = $CC -MMD -MF \$out.d \$cflags \$FLAGS -c \$in -o \$out
  depfile = \$out.d
  description = cc \$in

rule ar
  command = $AR crs \$out \$in
  description = ar \$out
_END

# generic sources
_gen_buildrules ${GENERIC_SOURCES[@]}

# arch-specific sources
case $TARGET in
  aarch64-*) LIB_SUFFIX=-aarch64
    echo >> $NF
    for src in "${AARCH64_SOURCES[@]}"; do
      case $src in
        aarch64/lse.S) _gen_buildrules_aarch64_lse $src ;;
        *)             _gen_buildrule cc $src ;;
      esac
    done
    ;;
  x86_64-*) LIB_SUFFIX=-x86_64
    _gen_buildrules ${X86_ARCH_SOURCES[@]}
    _gen_buildrules ${X86_64_SOURCES[@]}
    ;;
  riscv32-*) LIB_SUFFIX=-riscv32
    _gen_buildrules ${RISCV_SOURCES[@]}
    _gen_buildrules ${RISCV32_SOURCES[@]}
    ;;
  riscv64-*) LIB_SUFFIX=-riscv64
    _gen_buildrules ${RISCV_SOURCES[@]}
    _gen_buildrules ${RISCV64_SOURCES[@]}
    ;;
  wasm32-*) LIB_SUFFIX=-wasm32
    ;;
  *) _err "unexpected TARGET=$TARGET"
    ;;
esac

# system-specific sources
case $TARGET in
  *macos*)
    _gen_buildrules ${DARWIN_SOURCES[@]}
    ;;
esac

echo "build $DESTDIR/lib/libclang_rt.builtins.a: ar ${ALL_OBJECTS[*]}" >> $NF
echo "default $DESTDIR/lib/libclang_rt.builtins.a" >> $NF

# build & install
rm -rf "$DESTDIR"
mkdir -p "$DESTDIR/lib"
NINJA_STATUS="[builtins %f/%t] " \
ninja -f build.ninja

# compatibility layout for s1 compiler
TARGET_ARCH=${TARGET%%-*}
case $TARGET in
  wasm32*)
    mkdir -p "$BUILTINS_DIR_FOR_S1_CC/lib/wasm32"
    cp "$DESTDIR/lib/libclang_rt.builtins.a" \
       "$BUILTINS_DIR_FOR_S1_CC/lib/wasm32/libclang_rt.builtins-$TARGET_ARCH.a"
    ;;
  *linux|*playbit)
    mkdir -p "$BUILTINS_DIR_FOR_S1_CC/lib/linux"
    cp "$DESTDIR/lib/libclang_rt.builtins.a" \
       "$BUILTINS_DIR_FOR_S1_CC/lib/linux/libclang_rt.builtins-$TARGET_ARCH.a"
    ;;
  *macos)
    mkdir -p "$BUILTINS_DIR_FOR_S1_CC/lib/darwin"
    cp "$DESTDIR/lib/libclang_rt.builtins.a" \
       "$BUILTINS_DIR_FOR_S1_CC/lib/darwin/libclang_rt.builtins-$TARGET_ARCH.a"
    ;;
  *)
    _err "TODO: compatibility layout for s1, TARGET=$TARGET"
    ;;
esac

_popd
$NO_CLEANUP || rm -rf "$BUILDDIR"
