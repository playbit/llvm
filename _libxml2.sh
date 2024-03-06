_download_and_extract_tar "$LIBXML2_URL" "$LIBXML2_DIR/build" "$LIBXML2_SHA256"
_pushd "$LIBXML2_DIR/build"

rm -f test/icu_parse_test.xml  # no icu

./configure \
  --prefix= \
  --host=$CHOST \
  --build=$CBUILD \
  \
  --enable-static \
  --with-zlib="$ZLIB_DIR" \
  \
  --disable-shared \
  --disable-dependency-tracking \
  --without-catalog \
  --without-debug \
  --without-ftp \
  --without-http \
  --without-html \
  --without-iconv \
  --without-history \
  --without-legacy \
  --without-python \
  --without-readline \
  --without-modules \
  --without-lzma

make -j$(nproc)

rm -rf "$LIBXML2_DIR"/{bin,lib,include,share,usr}
make DESTDIR="$LIBXML2_DIR" install # don't use -j here

# rewrite bin/xml2-config to be relative to its install location
cp "$LIBXML2_DIR/bin/xml2-config" xml2-config
sed -E -e \
  's/^prefix=.*/prefix="`cd "$(dirname "$0")\/.."; pwd`"/' \
  xml2-config > "$LIBXML2_DIR/bin/xml2-config"

# remove unwanted programs
# (can't figure out how to disable building and/or installing these)
rm -f "$LIBXML2_DIR/bin/xmlcatalog" "$LIBXML2_DIR/bin/xmllint"

# remove libtool file
rm -f "$LIBXML2_DIR/lib/libxml2.la"

# # remove cmake dir
# rm -rf "$LIBXML2_DIR/lib/cmake"

# # remove pkgconfig dir
# rm -rf "$LIBXML2_DIR/lib/pkgconfig"

_popd
rm -rf "$LIBXML2_DIR/build"
