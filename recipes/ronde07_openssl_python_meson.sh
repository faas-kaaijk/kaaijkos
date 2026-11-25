#!/usr/bin/env bash
set -euo pipefail
mkdir -p /work/stage /work/logs
cd /work/build

pkg_done() {
    local NAME="$1" VER="$2" STAGE="/work/stage/$1"
    kpkg pack "$STAGE" "$NAME" "$VER"
    kpkg install "/var/cache/kpkg/${NAME}-${VER}.kpkg.tar.zst"
    rm -rf "$STAGE"
}

echo "=== [1/10] Perl 5.44.0 ==="
S=/work/stage/perl; rm -rf "$S" perl-5.44.0 && mkdir -p "$S"
tar -xf /work/sources/perl-5.44.0.tar.xz && cd perl-5.44.0
export BUILD_ZLIB=False BUILD_BZIP2=0
sh Configure -des                                          \
             -D prefix=/usr                                \
             -D vendorprefix=/usr                          \
             -D privlib=/usr/lib/perl5/5.44/core_perl      \
             -D archlib=/usr/lib/perl5/5.44/core_perl      \
             -D sitelib=/usr/lib/perl5/5.44/site_perl      \
             -D sitearch=/usr/lib/perl5/5.44/site_perl     \
             -D vendorlib=/usr/lib/perl5/5.44/vendor_perl  \
             -D vendorarch=/usr/lib/perl5/5.44/vendor_perl \
             -D man1dir=/usr/share/man/man1                \
             -D man3dir=/usr/share/man/man3                \
             -D pager="/usr/bin/less -isR"                 \
             -D useshrplib                                 \
             -D usethreads
make && make DESTDIR="$S" install
unset BUILD_ZLIB BUILD_BZIP2
pkg_done perl 5.44.0
cd /work/build && rm -rf perl-5.44.0

echo "=== [2/10] Autoconf 2.73 ==="
S=/work/stage/autoconf; rm -rf "$S" autoconf-2.73 && mkdir -p "$S"
tar -xf /work/sources/autoconf-2.73.tar.xz && cd autoconf-2.73
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done autoconf 2.73
cd /work/build && rm -rf autoconf-2.73

echo "=== [3/10] Automake 1.18.1 ==="
S=/work/stage/automake; rm -rf "$S" automake-1.18.1 && mkdir -p "$S"
tar -xf /work/sources/automake-1.18.1.tar.xz && cd automake-1.18.1
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.18.1
make && make DESTDIR="$S" install
pkg_done automake 1.18.1
cd /work/build && rm -rf automake-1.18.1

echo "=== [4/10] OpenSSL 4.0.1 ==="
S=/work/stage/openssl; rm -rf "$S" openssl-4.0.1 && mkdir -p "$S"
tar -xf /work/sources/openssl-4.0.1.tar.gz && cd openssl-4.0.1
./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib shared zlib-dynamic
make
make DESTDIR="$S" MANSUFFIX=ssl install_sw install_ssldirs
rm -fv "$S"/usr/lib/lib{crypto,ssl}.a
pkg_done openssl 4.0.1
cd /work/build && rm -rf openssl-4.0.1

echo "=== [5/10] Libelf 0.195 ==="
S=/work/stage/libelf; rm -rf "$S" elfutils-0.195 && mkdir -p "$S"
tar -xf /work/sources/elfutils-0.195.tar.bz2 && cd elfutils-0.195
./configure --prefix=/usr --disable-debuginfod --enable-libdebuginfod=dummy
make -C lib && make -C libelf
make -C libelf DESTDIR="$S" install
install -vDm644 config/libelf.pc "$S/usr/lib/pkgconfig/libelf.pc"
rm -fv "$S/usr/lib/libelf.a"
pkg_done libelf 0.195
cd /work/build && rm -rf elfutils-0.195

echo "=== [6/10] Libffi 3.8.0 (universeel x86-64) ==="
S=/work/stage/libffi; rm -rf "$S" libffi-3.8.0 && mkdir -p "$S"
tar -xf /work/sources/libffi-3.8.0.tar.gz && cd libffi-3.8.0
./configure --prefix=/usr --disable-static --with-gcc-arch=x86-64
make && make DESTDIR="$S" install
pkg_done libffi 3.8.0
cd /work/build && rm -rf libffi-3.8.0

echo "=== [7/10] SQLite 3.53.4 ==="
S=/work/stage/sqlite; rm -rf "$S" sqlite-autoconf-3530400 && mkdir -p "$S"
tar -xf /work/sources/sqlite-autoconf-3530400.tar.gz && cd sqlite-autoconf-3530400
./configure --prefix=/usr --disable-static --enable-fts{4,5} \
            CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 -D SQLITE_ENABLE_UNLOCK_NOTIFY=1 -D SQLITE_ENABLE_DBSTAT_VTAB=1 -D SQLITE_SECURE_DELETE=1"
make LDFLAGS.rpath=""
make DESTDIR="$S" install
pkg_done sqlite 3.53.4
cd /work/build && rm -rf sqlite-autoconf-3530400

echo "=== [8/10] Mpdecimal 4.0.1 ==="
S=/work/stage/mpdecimal; rm -rf "$S" mpdecimal-4.0.1 && mkdir -p "$S"
tar -xf /work/sources/mpdecimal-4.0.1.tar.gz && cd mpdecimal-4.0.1
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpdecimal-4.0.1
make && make DESTDIR="$S" install
pkg_done mpdecimal 4.0.1
cd /work/build && rm -rf mpdecimal-4.0.1

echo "=== [9/10] Definitieve Python 3.14.7 (+ OpenSSL 4 patch) ==="
S=/work/stage/python3; rm -rf "$S" Python-3.14.7 && mkdir -p "$S"
tar -xf /work/sources/Python-3.14.7.tar.xz && cd Python-3.14.7
patch -Np1 -i /work/sources/Python-3.14.7-openssl_4-1.patch
./configure --prefix=/usr --enable-shared --with-system-expat --without-static-libpython
make && make DESTDIR="$S" install
mkdir -p "$S/etc"
cat > "$S/etc/pip.conf" << 'PIPEOF'
[global]
root-user-action = ignore
disable-pip-version-check = true
PIPEOF
pkg_done python3 3.14.7
cd /work/build && rm -rf Python-3.14.7

echo "=== [10/10] Python build- & systemd-modules (incl. Meson 1.12.0 & Jinja2) ==="
py_pkg() {
    local KNAME="$1" VER="$2" TAR="$3" PIPNAME="$4"
    local S="/work/stage/${KNAME}"
    rm -rf "$S" && mkdir -p "$S"
    cd /work/build
    local W="/work/build/_py_${KNAME}"
    rm -rf "$W" && mkdir -p "$W" && cd "$W"
    tar -xf "/work/sources/${TAR}"
    cd "$(find "$W" -mindepth 1 -maxdepth 1 -type d | head -n1)"
    pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps "$PWD"
    pip3 install --no-index --no-user --find-links dist --root="$S" --prefix=/usr "$PIPNAME"
    if [ "$KNAME" = "meson" ]; then
        install -vDm644 data/shell-completions/bash/meson "$S/usr/share/bash-completion/completions/meson"
    fi
    pkg_done "$KNAME" "$VER"
    cd /work/build && rm -rf "$W"
}

py_pkg python-flit-core   4.0.2  flit_core-4.0.2.tar.gz   flit_core
py_pkg python-packaging   26.3   packaging-26.3.tar.gz    packaging
py_pkg python-wheel       0.48.0 wheel-0.48.0.tar.gz      wheel
py_pkg python-setuptools  84.0.0 setuptools-84.0.0.tar.gz setuptools
py_pkg meson              1.12.0 meson-1.12.0.tar.gz      meson
py_pkg python-markupsafe  3.0.3  markupsafe-3.0.3.tar.gz  MarkupSafe
py_pkg python-jinja2      3.1.6  jinja2-3.1.6.tar.gz      Jinja2

echo "=== RONDE 7 KLAAR! ==="
python3 -c 'import ssl, jinja2; print(ssl.OPENSSL_VERSION, "| Jinja2", jinja2.__version__)'
meson --version
kpkg list | tail -n 10
