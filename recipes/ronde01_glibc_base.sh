#!/usr/bin/env bash
set -euo pipefail
export MAKEFLAGS="-j$(nproc)"
mkdir -p /work/stage /work/logs /work/build
cd /work/build

echo "=== [1/3] Iana-etc 20260805 ==="
rm -rf iana-etc-20260805
tar -xf /work/sources/iana-etc-20260805.tar.gz && cd iana-etc-20260805
cp -v services protocols /etc
cd /work/build && rm -rf iana-etc-20260805

echo "=== [2/3] Man-pages 6.18 ==="
rm -rf man-pages-6.18
tar -xf /work/sources/man-pages-6.18.tar.xz && cd man-pages-6.18
rm -v man3/crypt*
make -R GIT=false prefix=/usr install
cd /work/build && rm -rf man-pages-6.18

echo "=== [3/3] Definitieve Glibc 2.44 (KaaijkOS 1.0) ==="
rm -rf glibc-2.44
tar -xf /work/sources/glibc-2.44.tar.xz && cd glibc-2.44
patch -Np1 -i /work/sources/glibc-fhs-1.patch
patch -Np1 -i /work/sources/glibc-2.44-upstream_fixes-1.patch

mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms

../configure --prefix=/usr                     \
             --disable-werror                  \
             --disable-nscd                    \
             libc_cv_slibdir=/usr/lib          \
             --enable-stack-protector=strong   \
             --enable-kernel=5.10              \
             --with-pkgversion="KaaijkOS 1.0"  \
             --with-bugurl="https://github.com/faas-kaaijk/kaaijkos/issues"

make
touch /etc/ld.so.conf
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
rm -f /usr/sbin/nscd

# Veilig live-vervangen van shared libraries + oude include-fixed opruimen
make DESTDIR="$PWD/dest" install
install -vm755 dest/usr/lib/*.so.* /usr/lib
DIR=$(dirname "$(gcc -print-libgcc-file-name)")
[ -e "$DIR/include/limits.h" ]    || mv "$DIR"/include{-fixed,}/limits.h
[ -e "$DIR/include/syslimits.h" ] || mv "$DIR"/include{-fixed,}/syslimits.h
rm -rfv "$DIR"/include-fixed/*
unset DIR

make install
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

# Locales aanmaken (NL, BE, EN, DE, FR + C.UTF-8)
localedef -i C     -f UTF-8 C.UTF-8
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i nl_NL -f UTF-8 nl_NL.UTF-8
localedef -i nl_BE -f UTF-8 nl_BE.UTF-8
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8

# /etc/nsswitch.conf (klaar voor systemd)
cat > /etc/nsswitch.conf << 'EOF'
passwd: files systemd
group: files systemd
shadow: files systemd

hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
networks: files

protocols: files
services: files
ethers: files
rpc: files
EOF

# Wereldwijde tijdzones (tzdata2026c) + Europe/Amsterdam als standaard
mkdir -p tzdata && cd tzdata
tar -xf /work/sources/tzdata2026c.tar.gz
ZONEINFO=/usr/share/zoneinfo
mkdir -pv "$ZONEINFO"/{posix,right}
for tz in etcetera southamerica northamerica europe africa antarctica asia australasia backward; do
    zic -L /dev/null   -d "$ZONEINFO"       "$tz"
    zic -L /dev/null   -d "$ZONEINFO/posix" "$tz"
    zic -L leapseconds -d "$ZONEINFO/right" "$tz"
done
cp -v zone.tab zone1970.tab iso3166.tab "$ZONEINFO"
zic -d "$ZONEINFO" -p Europe/Amsterdam
ln -sfv /usr/share/zoneinfo/Europe/Amsterdam /etc/localtime

# Dynamic linker configuratie
cat > /etc/ld.so.conf << 'EOF'
/usr/local/lib
/opt/lib
include /etc/ld.so.conf.d/*.conf
EOF
mkdir -pv /etc/ld.so.conf.d

cd /work/build && rm -rf glibc-2.44

echo "=== RONDE 1 KLAAR! ==="
ldd --version | head -n 1
/usr/lib/libc.so.6 | head -n 3
