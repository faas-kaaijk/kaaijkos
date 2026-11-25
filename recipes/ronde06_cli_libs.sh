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

echo "=== [1/13] Ncurses 6.6 ==="
S=/work/stage/ncurses; rm -rf "$S" ncurses-6.6 && mkdir -p "$S"
tar -xf /work/sources/ncurses-6.6.tar.gz && cd ncurses-6.6
./configure --prefix=/usr --mandir=/usr/share/man --with-shared --without-debug \
            --without-normal --with-cxx-shared --enable-pc-files \
            --with-pkg-config-libdir=/usr/lib/pkgconfig
make && make DESTDIR="$S" install
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$S/usr/include/curses.h"
for lib in ncurses form panel menu; do
    ln -sfv "lib${lib}w.so" "$S/usr/lib/lib${lib}.so"
    ln -sfv "${lib}w.pc"    "$S/usr/lib/pkgconfig/${lib}.pc"
done
ln -sfv libncursesw.so "$S/usr/lib/libcurses.so"
make distclean
./configure --prefix=/usr --with-shared --without-normal --without-debug \
            --without-cxx-binding --with-abi-version=5
make sources libs
cp -av lib/lib*.so.5* "$S/usr/lib/"
pkg_done ncurses 6.6
cd /work/build && rm -rf ncurses-6.6

echo "=== [2/13] Sed 4.10 ==="
S=/work/stage/sed; rm -rf "$S" sed-4.10 && mkdir -p "$S"
tar -xf /work/sources/sed-4.10.tar.xz && cd sed-4.10
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done sed 4.10
cd /work/build && rm -rf sed-4.10

echo "=== [3/13] Psmisc 23.7 ==="
S=/work/stage/psmisc; rm -rf "$S" psmisc-23.7 && mkdir -p "$S"
tar -xf /work/sources/psmisc-23.7.tar.xz && cd psmisc-23.7
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done psmisc 23.7
cd /work/build && rm -rf psmisc-23.7

echo "=== [4/13] Gettext 1.0 ==="
S=/work/stage/gettext; rm -rf "$S" gettext-1.0 && mkdir -p "$S"
tar -xf /work/sources/gettext-1.0.tar.xz && cd gettext-1.0
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/gettext-1.0
make && make DESTDIR="$S" install
chmod -v 0755 "$S/usr/lib/preloadable_libintl.so"
pkg_done gettext 1.0
cd /work/build && rm -rf gettext-1.0

echo "=== [5/13] Bison 3.8.2 ==="
S=/work/stage/bison; rm -rf "$S" bison-3.8.2 && mkdir -p "$S"
tar -xf /work/sources/bison-3.8.2.tar.xz && cd bison-3.8.2
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make && make DESTDIR="$S" install
pkg_done bison 3.8.2
cd /work/build && rm -rf bison-3.8.2

echo "=== [6/13] Grep 3.12 ==="
S=/work/stage/grep; rm -rf "$S" grep-3.12 && mkdir -p "$S"
tar -xf /work/sources/grep-3.12.tar.xz && cd grep-3.12
sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done grep 3.12
cd /work/build && rm -rf grep-3.12

echo "=== [7/13] Bash 5.3 ==="
S=/work/stage/bash; rm -rf "$S" bash-5.3 && mkdir -p "$S"
tar -xf /work/sources/bash-5.3.tar.gz && cd bash-5.3
./configure --prefix=/usr --without-bash-malloc --with-installed-readline --docdir=/usr/share/doc/bash-5.3
make && make DESTDIR="$S" install
ln -sfv bash "$S/usr/bin/sh"
pkg_done bash 5.3
cd /work/build && rm -rf bash-5.3

echo "=== [8/13] Libtool 2.6.2 ==="
S=/work/stage/libtool; rm -rf "$S" libtool-2.6.2 && mkdir -p "$S"
tar -xf /work/sources/libtool-2.6.2.tar.xz && cd libtool-2.6.2
./configure --prefix=/usr && make && make DESTDIR="$S" install
rm -fv "$S/usr/lib/libltdl.a"
pkg_done libtool 2.6.2
cd /work/build && rm -rf libtool-2.6.2

echo "=== [9/13] GDBM 1.26 ==="
S=/work/stage/gdbm; rm -rf "$S" gdbm-1.26 && mkdir -p "$S"
tar -xf /work/sources/gdbm-1.26.tar.gz && cd gdbm-1.26
./configure --prefix=/usr --disable-static --enable-libgdbm-compat
make && make DESTDIR="$S" install
pkg_done gdbm 1.26
cd /work/build && rm -rf gdbm-1.26

echo "=== [10/13] Gperf 3.3 ==="
S=/work/stage/gperf; rm -rf "$S" gperf-3.3 && mkdir -p "$S"
tar -xf /work/sources/gperf-3.3.tar.gz && cd gperf-3.3
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.3
make && make DESTDIR="$S" install
pkg_done gperf 3.3
cd /work/build && rm -rf gperf-3.3

echo "=== [11/13] Expat 2.8.3 ==="
S=/work/stage/expat; rm -rf "$S" expat-2.8.3 && mkdir -p "$S"
tar -xf /work/sources/expat-2.8.3.tar.xz && cd expat-2.8.3
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/expat-2.8.3
make && make DESTDIR="$S" install
pkg_done expat 2.8.3
cd /work/build && rm -rf expat-2.8.3

echo "=== [12/13] Inetutils 2.8 ==="
S=/work/stage/inetutils; rm -rf "$S" inetutils-2.8 && mkdir -p "$S"
tar -xf /work/sources/inetutils-2.8.tar.gz && cd inetutils-2.8
sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
./configure --prefix=/usr --bindir=/usr/bin --localstatedir=/var \
            --disable-logger --disable-whois --disable-rcp \
            --disable-rexec --disable-rlogin --disable-rsh --disable-servers
make && make DESTDIR="$S" install
mkdir -p "$S/usr/sbin" && mv -v "$S/usr/bin/ifconfig" "$S/usr/sbin/"
pkg_done inetutils 2.8
cd /work/build && rm -rf inetutils-2.8

echo "=== [13/13] Less 704 ==="
S=/work/stage/less; rm -rf "$S" less-704 && mkdir -p "$S"
tar -xf /work/sources/less-704.tar.gz && cd less-704
./configure --prefix=/usr --sysconfdir=/etc && make && make DESTDIR="$S" install
pkg_done less 704
cd /work/build && rm -rf less-704

echo "=== RONDE 6 KLAAR! ==="
kpkg list | tail -n 15
