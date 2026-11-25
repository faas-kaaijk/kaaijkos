#!/usr/bin/env bash
set -euo pipefail
export MAKEFLAGS="-j$(nproc)"
mkdir -p /work/stage /work/logs /work/build
cd /work/build

pkg_done() {
    local NAME="$1" VER="$2" STAGE="/work/stage/$1"
    kpkg pack "$STAGE" "$NAME" "$VER"
    kpkg install "/var/cache/kpkg/${NAME}-${VER}.kpkg.tar.zst"
    rm -rf "$STAGE"
}

echo "=== [1/8] File 5.48 ==="
S=/work/stage/file; rm -rf "$S" file-5.48 && mkdir -p "$S"
tar -xf /work/sources/file-5.48.tar.gz && cd file-5.48
./configure --prefix=/usr
make && make DESTDIR="$S" install
pkg_done file 5.48
cd /work/build && rm -rf file-5.48

echo "=== [2/8] Readline 8.3 ==="
S=/work/stage/readline; rm -rf "$S" readline-8.3 && mkdir -p "$S"
tar -xf /work/sources/readline-8.3.tar.gz && cd readline-8.3
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
sed -e '270a\
     else\
       chars_avail = 1;' \
    -e '288i\   result = -1;' \
    -i.orig input.c
./configure --prefix=/usr --disable-static --with-curses --docdir=/usr/share/doc/readline-8.3
make SHLIB_LIBS="-lncursesw"
make DESTDIR="$S" install
pkg_done readline 8.3
cd /work/build && rm -rf readline-8.3

echo "=== [3/8] PCRE2 10.47 ==="
S=/work/stage/pcre2; rm -rf "$S" pcre2-10.47 && mkdir -p "$S"
tar -xf /work/sources/pcre2-10.47.tar.bz2 && cd pcre2-10.47
./configure --prefix=/usr --docdir=/usr/share/doc/pcre2-10.47 \
            --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 \
            --enable-pcre2grep-libz --enable-pcre2grep-libbz2 \
            --enable-pcre2test-libreadline --disable-static
make && make DESTDIR="$S" install
pkg_done pcre2 10.47
cd /work/build && rm -rf pcre2-10.47

echo "=== [4/8] M4 1.4.21 ==="
S=/work/stage/m4; rm -rf "$S" m4-1.4.21 && mkdir -p "$S"
tar -xf /work/sources/m4-1.4.21.tar.xz && cd m4-1.4.21
./configure --prefix=/usr
make && make DESTDIR="$S" install
pkg_done m4 1.4.21
cd /work/build && rm -rf m4-1.4.21

echo "=== [5/8] Bc 7.0.3 ==="
S=/work/stage/bc; rm -rf "$S" bc-7.0.3 && mkdir -p "$S"
tar -xf /work/sources/bc-7.0.3.tar.xz && cd bc-7.0.3
CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
make && make DESTDIR="$S" install
pkg_done bc 7.0.3
cd /work/build && rm -rf bc-7.0.3

echo "=== [6/8] Flex 2.6.4 ==="
S=/work/stage/flex; rm -rf "$S" flex-2.6.4 && mkdir -p "$S"
tar -xf /work/sources/flex-2.6.4.tar.gz && cd flex-2.6.4
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/flex-2.6.4
make && make DESTDIR="$S" install
ln -sfv flex "$S/usr/bin/lex"
ln -sfv flex.1 "$S/usr/share/man/man1/lex.1"
pkg_done flex 2.6.4
cd /work/build && rm -rf flex-2.6.4

echo "=== [7/8] Ninja 1.13.2 ==="
S=/work/stage/ninja; rm -rf "$S" ninja-1.13.2 && mkdir -p "$S"
tar -xf /work/sources/ninja-1.13.2.tar.gz && cd ninja-1.13.2
sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
python3 configure.py --bootstrap --verbose
install -vDm755 ninja "$S/usr/bin/ninja"
install -vDm644 misc/bash-completion "$S/usr/share/bash-completion/completions/ninja"
pkg_done ninja 1.13.2
cd /work/build && rm -rf ninja-1.13.2

echo "=== [8/8] Pkgconf 3.0.5 ==="
S=/work/stage/pkgconf; rm -rf "$S" pkgconf-3.0.5 && mkdir -p "$S"
tar -xf /work/sources/pkgconf-3.0.5.tar.xz && cd pkgconf-3.0.5
tar -xf /work/sources/meson-1.12.0.tar.gz
mkdir build && cd build
python3 ../meson-1.12.0/meson.py setup --prefix=/usr --buildtype=release ..
ninja
DESTDIR="$S" ninja install
[ -d "$S/usr/share/doc/pkgconf" ] && mv "$S/usr/share/doc/pkgconf" "$S/usr/share/doc/pkgconf-3.0.5"
ln -sfv pkgconf "$S/usr/bin/pkg-config"
ln -sfv pkgconf.1 "$S/usr/share/man/man1/pkg-config.1"
pkg_done pkgconf 3.0.5
cd /work/build && rm -rf pkgconf-3.0.5

echo "=== RONDE 3 KLAAR! ==="
kpkg list
