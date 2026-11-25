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

echo "=== [1/9] Definitieve Binutils 2.47 (KaaijkOS 1.0) ==="
S=/work/stage/binutils; rm -rf "$S" binutils-2.47 && mkdir -p "$S"
tar -xf /work/sources/binutils-2.47.tar.xz && cd binutils-2.47
mkdir -v build && cd build
../configure --prefix=/usr                     \
             --sysconfdir=/etc                 \
             --enable-ld=default               \
             --enable-plugins                  \
             --enable-shared                   \
             --disable-werror                  \
             --enable-64-bit-bfd               \
             --enable-new-dtags                \
             --with-system-zlib                \
             --with-lib-path=/usr/lib          \
             --enable-default-hash-style=gnu   \
             --with-pkgversion="KaaijkOS 1.0"  \
             --with-bugurl="https://github.com/faas-kaaijk/kaaijkos/issues"
make tooldir=/usr
make tooldir=/usr DESTDIR="$S" install
rm -rfv "$S"/usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a "$S"/usr/share/doc/gprofng/
pkg_done binutils 2.47
cd /work/build && rm -rf binutils-2.47

echo "=== [2/9] GMP 6.3.0 (universele --enable-fat CPU-dispatch) ==="
S=/work/stage/gmp; rm -rf "$S" gmp-6.3.0 && mkdir -p "$S"
tar -xf /work/sources/gmp-6.3.0.tar.xz && cd gmp-6.3.0
sed -i '/long long t1;/,+1s/()/(...)/' configure
./configure --prefix=/usr --enable-cxx --enable-fat --disable-static --docdir=/usr/share/doc/gmp-6.3.0
make && make DESTDIR="$S" install
pkg_done gmp 6.3.0
cd /work/build && rm -rf gmp-6.3.0

echo "=== [3/9] MPFR 4.2.2 ==="
S=/work/stage/mpfr; rm -rf "$S" mpfr-4.2.2 && mkdir -p "$S"
tar -xf /work/sources/mpfr-4.2.2.tar.xz && cd mpfr-4.2.2
./configure --prefix=/usr --disable-static --enable-thread-safe --docdir=/usr/share/doc/mpfr-4.2.2
make && make DESTDIR="$S" install
pkg_done mpfr 4.2.2
cd /work/build && rm -rf mpfr-4.2.2

echo "=== [4/9] MPC 1.4.1 ==="
S=/work/stage/mpc; rm -rf "$S" mpc-1.4.1 && mkdir -p "$S"
tar -xf /work/sources/mpc-1.4.1.tar.xz && cd mpc-1.4.1
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpc-1.4.1
make && make DESTDIR="$S" install
pkg_done mpc 1.4.1
cd /work/build && rm -rf mpc-1.4.1

echo "=== [5/9] Attr 2.6.0 ==="
S=/work/stage/attr; rm -rf "$S" attr-2.6.0 && mkdir -p "$S"
tar -xf /work/sources/attr-2.6.0.tar.gz && cd attr-2.6.0
./configure --prefix=/usr --disable-static --sysconfdir=/etc --docdir=/usr/share/doc/attr-2.6.0
make && make DESTDIR="$S" install
pkg_done attr 2.6.0
cd /work/build && rm -rf attr-2.6.0

echo "=== [6/9] ACL 2.4.0 ==="
S=/work/stage/acl; rm -rf "$S" acl-2.4.0 && mkdir -p "$S"
tar -xf /work/sources/acl-2.4.0.tar.xz && cd acl-2.4.0
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/acl-2.4.0
make && make DESTDIR="$S" install
pkg_done acl 2.4.0
cd /work/build && rm -rf acl-2.4.0

echo "=== [7/9] Libcap 2.78 ==="
S=/work/stage/libcap; rm -rf "$S" libcap-2.78 && mkdir -p "$S"
tar -xf /work/sources/libcap-2.78.tar.xz && cd libcap-2.78
sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib
make prefix=/usr lib=lib DESTDIR="$S" install
pkg_done libcap 2.78
cd /work/build && rm -rf libcap-2.78

echo "=== [8/9] Libxcrypt 4.5.2 ==="
S=/work/stage/libxcrypt; rm -rf "$S" libxcrypt-4.5.2 && mkdir -p "$S"
tar -xf /work/sources/libxcrypt-4.5.2.tar.xz && cd libxcrypt-4.5.2
sed -i '/strchr/s/const//' lib/crypt-{sm3,gost}-yescrypt.c
./configure --prefix=/usr --enable-hashes=strong,glibc --enable-obsolete-api=no --disable-static --disable-failure-tokens
make && make DESTDIR="$S" install
make distclean
./configure --prefix=/usr --enable-hashes=strong,glibc --enable-obsolete-api=glibc --disable-static --disable-failure-tokens
make
cp -av --remove-destination .libs/libcrypt.so.1* "$S/usr/lib/"
pkg_done libxcrypt 4.5.2
cd /work/build && rm -rf libxcrypt-4.5.2

echo "=== [9/9] Shadow 4.20.2 ==="
S=/work/stage/shadow; rm -rf "$S" shadow-4.20.2 && mkdir -p "$S"
tar -xf /work/sources/shadow-4.20.2.tar.xz && cd shadow-4.20.2
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /' {} \;
sed -e 's:#ENCRYPT_METHOD SHA512:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                      \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                     \
    -i etc/login.defs
touch /usr/bin/passwd
./configure --sysconfdir=/etc --disable-static --with-{b,yes}crypt --without-libbsd --disable-logind --with-group-name-max-length=32
make
make exec_prefix=/usr DESTDIR="$S" install
make -C man DESTDIR="$S" install-man
pkg_done shadow 4.20.2
pwconv
grpconv
mkdir -p /etc/default
useradd -D --gid 999
sed -i '/MAIL/s/yes/no/' /etc/default/useradd
touch /etc/sub{u,g}id
cd /work/build && rm -rf shadow-4.20.2

echo "=== RONDE 4 KLAAR! ==="
ld --version | head -n 1
kpkg list | tail -n 10
