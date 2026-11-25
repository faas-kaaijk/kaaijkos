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

echo "=== [1/15] Kmod 34.2 ==="
S=/work/stage/kmod; rm -rf "$S" kmod-34.2 && mkdir -p "$S"
tar -xf /work/sources/kmod-34.2.tar.xz && cd kmod-34.2
mkdir -p build && cd build
meson setup --prefix=/usr .. --buildtype=release -D manpages=false
ninja && DESTDIR="$S" ninja install
pkg_done kmod 34.2
cd /work/build && rm -rf kmod-34.2

echo "=== [2/15] Definitieve Coreutils 9.11 ==="
S=/work/stage/coreutils; rm -rf "$S" coreutils-9.11 && mkdir -p "$S"
tar -xf /work/sources/coreutils-9.11.tar.xz && cd coreutils-9.11
patch -Np1 -i /work/sources/coreutils-9.11-i18n-1.patch
autoreconf -fv
automake -af
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
make && make DESTDIR="$S" install
mkdir -p "$S/usr/sbin" "$S/usr/share/man/man8"
mv -v "$S/usr/bin/chroot" "$S/usr/sbin/"
mv -v "$S/usr/share/man/man1/chroot.1" "$S/usr/share/man/man8/chroot.8"
sed -i 's/"1"/"8"/' "$S/usr/share/man/man8/chroot.8"
pkg_done coreutils 9.11
cd /work/build && rm -rf coreutils-9.11

echo "=== [3/15] Diffutils 3.12 ==="
S=/work/stage/diffutils; rm -rf "$S" diffutils-3.12 && mkdir -p "$S"
tar -xf /work/sources/diffutils-3.12.tar.xz && cd diffutils-3.12
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done diffutils 3.12
cd /work/build && rm -rf diffutils-3.12

echo "=== [4/15] Findutils 4.11.0 ==="
S=/work/stage/findutils; rm -rf "$S" findutils-4.11.0 && mkdir -p "$S"
tar -xf /work/sources/findutils-4.11.0.tar.xz && cd findutils-4.11.0
./configure --prefix=/usr --localstatedir=/var/lib/locate
make && make DESTDIR="$S" install
pkg_done findutils 4.11.0
cd /work/build && rm -rf findutils-4.11.0

echo "=== [5/15] Groff 1.24.1 (A4) ==="
S=/work/stage/groff; rm -rf "$S" groff-1.24.1 && mkdir -p "$S"
tar -xf /work/sources/groff-1.24.1.tar.gz && cd groff-1.24.1
PAGE=A4 ./configure --prefix=/usr
make -j1 && make DESTDIR="$S" install
pkg_done groff 1.24.1
cd /work/build && rm -rf groff-1.24.1

echo "=== [6/15] Pure Upstream GRUB 2.14 (Legacy BIOS i386-pc + UEFI x86_64-efi, 0% Nix!) ==="
S=/work/stage/grub; rm -rf "$S" grub-2.14 && mkdir -p "$S"
tar -xf /work/sources/grub-2.14.tar.xz && cd grub-2.14
unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS || true
sed 's/--image-base/--nonexist-linker-option/' -i configure
# Pass 1: Legacy BIOS (i386-pc)
./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --disable-werror
make && make DESTDIR="$S" install
make clean
# Pass 2: 64-bit UEFI (x86_64-efi)
./configure --prefix=/usr --sysconfdir=/etc --target=x86_64 --with-platform=efi --disable-efiemu --disable-werror
make && make DESTDIR="$S" install
pkg_done grub 2.14
cd /work/build && rm -rf grub-2.14

echo "=== [7/15] Gzip 1.14 ==="
S=/work/stage/gzip; rm -rf "$S" gzip-1.14 && mkdir -p "$S"
tar -xf /work/sources/gzip-1.14.tar.xz && cd gzip-1.14
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done gzip 1.14
cd /work/build && rm -rf gzip-1.14

echo "=== [8/15] Iproute2 7.1.0 ==="
S=/work/stage/iproute2; rm -rf "$S" iproute2-7.1.0 && mkdir -p "$S"
tar -xf /work/sources/iproute2-7.1.0.tar.xz && cd iproute2-7.1.0
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns
make SBINDIR=/usr/sbin DESTDIR="$S" install
pkg_done iproute2 7.1.0
cd /work/build && rm -rf iproute2-7.1.0

echo "=== [9/15] Kbd 2.10.0 ==="
S=/work/stage/kbd; rm -rf "$S" kbd-2.10.0 && mkdir -p "$S"
tar -xf /work/sources/kbd-2.10.0.tar.xz && cd kbd-2.10.0
patch -Np1 -i /work/sources/kbd-2.10.0-backspace-1.patch
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
./configure --prefix=/usr --disable-vlock && make && make DESTDIR="$S" install
pkg_done kbd 2.10.0
cd /work/build && rm -rf kbd-2.10.0

echo "=== [10/15] Libpipeline 1.5.8 ==="
S=/work/stage/libpipeline; rm -rf "$S" libpipeline-1.5.8 && mkdir -p "$S"
tar -xf /work/sources/libpipeline-1.5.8.tar.gz && cd libpipeline-1.5.8
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done libpipeline 1.5.8
cd /work/build && rm -rf libpipeline-1.5.8

echo "=== [11/15] Make 4.4.1 ==="
S=/work/stage/make; rm -rf "$S" make-4.4.1 && mkdir -p "$S"
tar -xf /work/sources/make-4.4.1.tar.gz && cd make-4.4.1
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done make 4.4.1
cd /work/build && rm -rf make-4.4.1

echo "=== [12/15] Patch 2.8 ==="
S=/work/stage/patch; rm -rf "$S" patch-2.8 && mkdir -p "$S"
tar -xf /work/sources/patch-2.8.tar.xz && cd patch-2.8
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done patch 2.8
cd /work/build && rm -rf patch-2.8

echo "=== [13/15] Tar 1.35 ==="
S=/work/stage/tar; rm -rf "$S" tar-1.35 && mkdir -p "$S"
tar -xf /work/sources/tar-1.35.tar.xz && cd tar-1.35
patch -Np1 -i /work/sources/tar-1.35-acl_fix-1.patch
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
make && make DESTDIR="$S" install
pkg_done tar 1.35
cd /work/build && rm -rf tar-1.35

echo "=== [14/15] Texinfo 7.3 ==="
S=/work/stage/texinfo; rm -rf "$S" texinfo-7.3 && mkdir -p "$S"
tar -xf /work/sources/texinfo-7.3.tar.xz && cd texinfo-7.3
./configure --prefix=/usr && make && make DESTDIR="$S" install
pkg_done texinfo 7.3
cd /work/build && rm -rf texinfo-7.3

echo "=== [15/15] Vim 9.2 ==="
S=/work/stage/vim; rm -rf "$S" vim-9.2.1025 && mkdir -p "$S"
tar -xf /work/sources/vim-9.2.1025.tar.gz && cd vim-9.2.1025
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr && make && make DESTDIR="$S" install
ln -sfv vim "$S/usr/bin/vi"
mkdir -p "$S/etc"
cat > "$S/etc/vimrc" << 'VIMEOF'
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1
set nocompatible
set backspace=2
set mouse=
syntax on
VIMEOF
pkg_done vim 9.2.1025
cd /work/build && rm -rf vim-9.2.1025

echo "=== RONDE 8 KLAAR! ==="
grub-install --version
ls -d /usr/lib/grub/*
kpkg list | tail -n 10
