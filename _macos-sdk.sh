MAC_SDK=$BUILD_DIR_GENERIC/MacOSX${MAC_SDK_VERSION}.sdk
if [ ! -d "$MAC_SDK" ]; then
  _download_and_extract_tar "$MAC_SDK_URL" "$MAC_SDK" "$MAC_SDK_SHA256"
fi

# copy using file cloning on macos
CP=cp; [ $HOST_SYS != macos ] || CP='cp -c'

echo "copy ${MAC_SDK##$PWD0/} -> ${SYSROOT##$PWD0/}"

# note: clang's Darwin cc1 driver expects includes & libs
# in e.g. sysroot/usr/lib, not sysroot/lib
rm -rf "$SYSROOT/usr"
mkdir -p "$SYSROOT/usr"
$CP -a "$MAC_SDK/usr/bin" "$SYSROOT/usr/bin"
$CP -a "$MAC_SDK/usr/lib" "$SYSROOT/usr/lib"
$CP -a "$MAC_SDK/usr/include" "$SYSROOT/usr/include"
rm -rf "$SYSROOT/usr/lib"/{php,swift} "$SYSROOT/usr/lib"/libc++*

# remove headers provided by our "own" libc++
rm -rf "$SYSROOT/usr/include/c++"
for f in \
  __libunwind_config.h \
  libunwind.h \
  unwind_arm_ehabi.h \
  unwind_itanium.h \
  unwind.h \
;do
  rm -rf "$SYSROOT/usr/include/$f"
done

for dir in bin lib; do
  ln -s usr/$dir "$SYSROOT/$dir"
done

rm -rf "$SYSROOT/System"
mkdir -p "$SYSROOT/System/Library"
for dir in CoreServices Frameworks PrivateFrameworks; do
  $CP -a "$MAC_SDK/System/Library/$dir" "$SYSROOT/System/Library/$dir"
done
