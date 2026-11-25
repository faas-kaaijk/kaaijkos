#!/usr/bin/env bash
set -euo pipefail
mkdir -p /work/stage /work/logs /work/build
cd /work/build

pkg_done() {
    local NAME="$1" VER="$2" STAGE="/work/stage/$1"
    kpkg pack "$STAGE" "$NAME" "$VER"
    kpkg install "/var/cache/kpkg/${NAME}-${VER}.kpkg.tar.zst"
    rm -rf "$STAGE"
}

# Definitieve gawk 5.4.1 (met MPFR/GMP!) moet VÓÓR GCC gebouwd worden
# om de gawk 5.4.1 optc-gen.awk bug ('0Wabsolute-value') te voorkomen.
echo "=== [1/2] Definitieve Gawk 5.4.1 (met MPFR 4.2.2 & GMP 6.3.0) ==="
S=/work/stage/gawk; rm -rf "$S" gawk-5.4.1 && mkdir -p "$S"
tar -xf /work/sources/gawk-5.4.1.tar.xz && cd gawk-5.4.1
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make -j"$(nproc)"
rm -f /usr/bin/gawk-5.4.1
make DESTDIR="$S" install
ln -sfv gawk.1 "$S/usr/share/man/man1/awk.1"
pkg_done gawk 5.4.1
cd /work/build && rm -rf gawk-5.4.1
gawk --version | head -n 2

echo "=== [2/2] Definitieve GCC 16.2.0 (KaaijkOS 1.0) ==="
S=/work/stage/gcc; rm -rf "$S" gcc-16.2.0 && mkdir -p "$S"
tar -xf /work/sources/gcc-16.2.0.tar.xz && cd gcc-16.2.0
sed -e "/m64=/s/lib64/lib/" -i.orig gcc/config/i386/t-linux64

mkdir -v build && cd build
../configure --prefix=/usr                     \
             LD=ld                             \
             --enable-languages=c,c++          \
             --enable-default-pie              \
             --enable-default-ssp              \
             --enable-host-pie                 \
             --enable-targets=all              \
             --disable-multilib                \
             --disable-bootstrap               \
             --disable-fixincludes             \
             --with-system-zlib                \
             --with-pkgversion="KaaijkOS 1.0"  \
             --with-bugurl="https://github.com/faas-kaaijk/kaaijkos/issues"

RAM_MB=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
JOBS="$(nproc 2>/dev/null || echo 2)"
if [ "$RAM_MB" -lt 3500 ] && [ "$JOBS" -gt 2 ]; then
    GCC_JOBS=2
else
    GCC_JOBS="$JOBS"
fi

echo "Compileren GCC 16.2.0 met -j${GCC_JOBS} (RAM: ${RAM_MB} MB)..."
MAKEFLAGS="-j${GCC_JOBS}" make

echo "Staging & verpakken met kpkg..."
make DESTDIR="$S" install
ln -sfv ../bin/cpp "$S/usr/lib/cpp"
ln -sfv gcc "$S/usr/bin/cc"
ln -sfv gcc.1 "$S/usr/share/man/man1/cc.1"
mkdir -pv "$S/usr/lib/bfd-plugins"
LTO_PLUGIN=$(find "$S/usr/libexec/gcc" -name liblto_plugin.so | head -n1 | sed "s|^$S||")
ln -sfv "$LTO_PLUGIN" "$S/usr/lib/bfd-plugins/liblto_plugin.so"
mkdir -pv "$S/usr/share/gdb/auto-load/usr/lib"
mv -v "$S"/usr/lib/*gdb.py "$S/usr/share/gdb/auto-load/usr/lib/"

pkg_done gcc 16.2.0

# Oude Stage-1 cross-restanten opruimen
rm -rf /usr/lib/gcc/x86_64-kaaijkos-linux-gnu /usr/libexec/gcc/x86_64-kaaijkos-linux-gnu
cd /work/build && rm -rf gcc-16.2.0

echo "=== DEFINITIEVE GCC SANITY CHECK ==="
gcc --version | head -n 1
echo "int main(){}" | cc -x c - -v -Wl,--verbose &> /tmp/gcc_sanity.log
readelf -l a.out | grep ": /lib"
grep -E -o "/usr/lib.*/S?crt[1in].*succeeded" /tmp/gcc_sanity.log
grep "/lib.*/libc.so.6 " /tmp/gcc_sanity.log
rm -f a.out /tmp/gcc_sanity.log
echo "=== RONDE 5 KLAAR! ==="
