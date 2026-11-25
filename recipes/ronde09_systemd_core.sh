#!/usr/bin/env bash
set -euo pipefail
export MAKEFLAGS="-j$(nproc)"
mkdir -p /work/stage /work/logs
cd /work/build

pkg_done() {
    local NAME="$1" VER="$2" STAGE="/work/stage/$1"
    rm -rf "$STAGE/run" "$STAGE/var/run" "$STAGE/var/lock"
    kpkg pack "$STAGE" "$NAME" "$VER"
    kpkg install "/var/cache/kpkg/${NAME}-${VER}.kpkg.tar.zst"
    ldconfig
    rm -rf "$STAGE"
}

echo "=== [1/6] Systemd 261.2 (261.2-kaaijkos) ==="
S=/work/stage/systemd; rm -rf "$S" systemd-261.2 && mkdir -p "$S"
tar -xf /work/sources/systemd-261.2.tar.gz && cd systemd-261.2
sed -e 's/GROUP="render"/GROUP="video"/' \
    -e 's/GROUP="sgx", //'               \
    -i rules.d/50-udev-default.rules.in

MOPT_FILE="meson.options"
[ -f "$MOPT_FILE" ] || MOPT_FILE="meson_options.txt"
MESON_ARGS=(
    --prefix=/usr
    --buildtype=release
    -D default-dnssec=no
    -D firstboot=false
    -D install-tests=false
    -D ldconfig=false
    -D sysusers=false
    -D rpmmacrosdir=no
    -D homed=disabled
    -D man=disabled
    -D mode=release
    -D pamconfdir=no
    -D dev-kvm-mode=0660
    -D nobody-group=nogroup
    -D sysupdate=disabled
    -D ukify=disabled
    -D docdir=/usr/share/doc/systemd-261.2
)
if grep -q "'version-tag'" "$MOPT_FILE"; then
    MESON_ARGS+=(-D version-tag=261.2-kaaijkos)
fi
if grep -q "'fallback-hostname'" "$MOPT_FILE"; then
    MESON_ARGS+=(-D fallback-hostname=KaaijkOS)
fi
if grep -q "'ntp-servers'" "$MOPT_FILE"; then
    if grep -A3 "'ntp-servers'" "$MOPT_FILE" | grep -q "array"; then
        MESON_ARGS+=(-D "ntp-servers=0.nl.pool.ntp.org,1.nl.pool.ntp.org,2.nl.pool.ntp.org")
    else
        MESON_ARGS+=(-D "ntp-servers=0.nl.pool.ntp.org 1.nl.pool.ntp.org 2.nl.pool.ntp.org")
    fi
fi

mkdir -p build && cd build
meson setup .. "${MESON_ARGS[@]}"
ninja
DESTDIR="$S" ninja install
mkdir -p "$S/usr/share/man"
tar -xf /work/sources/systemd-man-pages-261.2.tar.xz \
    --no-same-owner --strip-components=1 \
    -C "$S/usr/share/man"
pkg_done systemd 261.2
systemd-machine-id-setup
systemctl preset-all
cd /work/build && rm -rf systemd-261.2

echo "=== [2/6] D-Bus 1.16.2 ==="
S=/work/stage/dbus; rm -rf "$S" dbus-1.16.2 && mkdir -p "$S"
tar -xf /work/sources/dbus-1.16.2.tar.xz && cd dbus-1.16.2
mkdir -p build && cd build
meson setup --prefix=/usr --buildtype=release --wrap-mode=nofallback ..
ninja
DESTDIR="$S" ninja install
mkdir -p "$S/var/lib/dbus"
ln -sfv /etc/machine-id "$S/var/lib/dbus/machine-id"
pkg_done dbus 1.16.2
cd /work/build && rm -rf dbus-1.16.2

echo "=== [3/6] Man-DB 2.13.1 ==="
S=/work/stage/man-db; rm -rf "$S" man-db-2.13.1 && mkdir -p "$S"
tar -xf /work/sources/man-db-2.13.1.tar.xz && cd man-db-2.13.1
./configure --prefix=/usr                         \
            --docdir=/usr/share/doc/man-db-2.13.1 \
            --sysconfdir=/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=/usr/bin/lynx          \
            --with-vgrind=/usr/bin/vgrind         \
            --with-grap=/usr/bin/grap
make
make DESTDIR="$S" install
pkg_done man-db 2.13.1
cd /work/build && rm -rf man-db-2.13.1

echo "=== [4/6] Procps-ng 4.0.7 ==="
S=/work/stage/procps-ng; rm -rf "$S" procps*-4.0.7 && mkdir -p "$S"
tar -xf /work/sources/procps-ng-4.0.7.tar.xz && cd procps*-4.0.7
./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng-4.0.7 \
            --disable-static                        \
            --disable-kill                          \
            --enable-watch8bit                      \
            --with-systemd
make
make DESTDIR="$S" install
pkg_done procps-ng 4.0.7
cd /work/build && rm -rf procps*-4.0.7

echo "=== [5/6] Definitieve Util-linux 2.42.2 ==="
S=/work/stage/util-linux; rm -rf "$S" util-linux-2.42.2 && mkdir -p "$S"
tar -xf /work/sources/util-linux-2.42.2.tar.xz && cd util-linux-2.42.2
./configure --bindir=/usr/bin     \
            --libdir=/usr/lib     \
            --runstatedir=/run    \
            --sbindir=/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.42.2
make
make DESTDIR="$S" install
pkg_done util-linux 2.42.2
cd /work/build && rm -rf util-linux-2.42.2

echo "=== [6/6] E2fsprogs 1.47.4 ==="
S=/work/stage/e2fsprogs; rm -rf "$S" e2fsprogs-1.47.4 && mkdir -p "$S"
tar -xf /work/sources/e2fsprogs-1.47.4.tar.gz && cd e2fsprogs-1.47.4
mkdir -p build && cd build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-elf-shlibs \
             --disable-libblkid  \
             --disable-libuuid   \
             --disable-uuidd     \
             --disable-fsck
make
make DESTDIR="$S" install
rm -fv "$S"/usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
if [ -f "$S/usr/share/info/libext2fs.info.gz" ]; then
    gunzip -v "$S/usr/share/info/libext2fs.info.gz"
fi
mkdir -p "$S/usr/share/info"
makeinfo -o doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info "$S/usr/share/info"
sed 's/metadata_csum_seed,//' -i "$S/etc/mke2fs.conf"
pkg_done e2fsprogs 1.47.4
[ -f /usr/share/info/libext2fs.info ] && install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info || true
[ -f /usr/share/info/com_err.info ] && install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info || true
cd /work/build && rm -rf e2fsprogs-1.47.4

echo "=== Opruimen van .la bestanden ==="
find /usr/lib /usr/libexec -name '*.la' -delete

echo "=== RONDE 9 (FASE 3) 100% KLAAR! ==="
systemctl --version
dbus-daemon --version | sed -n '1p'
fsck.ext4 -V 2>&1 | sed -n '1p'
kpkg list | tail -n 12
echo "--- Totaal: $(kpkg list | wc -l) KaaijkOS pakketten ---"
