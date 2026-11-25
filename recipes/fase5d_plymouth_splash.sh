#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.1 — Fase 5d: Flicker-Free Boot Splash (Upstream Plymouth 24.004.60
# + eigen KaaijkOS K-spinner thema + GRUB boot-splash handoff)
# ==============================================================================
set -euo pipefail

WORK="${WORK:-/tmp/kaaijkos-plymouth-build}"
SRC="${WORK}/sources"
BLD="${WORK}/build"
STG="${WORK}/stage"
THEME_SRC="${1:-/work/assets/plymouth-theme/kaaijkos}"
BOOT_SPLASH_SRC="${2:-/work/assets/grub-theme/boot-splash.png}"
GRUB_TMPL_SRC="${3:-/work/configs/grub/grub.cfg.template}"

mkdir -p "$SRC" "$BLD" "$STG"

fetch() {
    local file="$1" url="$2"
    if [ ! -s "${SRC}/${file}" ]; then
        echo "  [fetch] ${file}..."
        curl -fsSL -o "${SRC}/${file}" "$url"
    fi
}

pkg_done() {
    local name="$1" ver="$2" sdir="$3"
    kpkg pack "$sdir" "$name" "$ver"
    kpkg install "/var/cache/kpkg/${name}-${ver}.kpkg.tar.zst"
    rm -rf "$sdir"
}

echo "=== [1/7] libpng 1.6.47 ==="
if [ ! -f /var/lib/kpkg/libpng.info ]; then
    fetch libpng-1.6.47.tar.xz "https://downloads.sourceforge.net/libpng/libpng-1.6.47.tar.xz"
    rm -rf "$BLD/libpng-1.6.47" "$STG/libpng"
    tar -xf "$SRC/libpng-1.6.47.tar.xz" -C "$BLD"
    (
        cd "$BLD/libpng-1.6.47"
        ./configure --prefix=/usr --disable-static
        make -j"$(nproc)"
        make DESTDIR="$STG/libpng" install
    )
    pkg_done libpng 1.6.47 "$STG/libpng"
    rm -rf "$BLD/libpng-1.6.47"
fi

echo "=== [2/7] libdrm 2.4.124 (core DRM) ==="
if [ ! -f /var/lib/kpkg/libdrm.info ]; then
    fetch libdrm-2.4.124.tar.xz "https://dri.freedesktop.org/libdrm/libdrm-2.4.124.tar.xz"
    rm -rf "$BLD/libdrm-2.4.124" "$STG/libdrm"
    tar -xf "$SRC/libdrm-2.4.124.tar.xz" -C "$BLD"
    (
        cd "$BLD/libdrm-2.4.124"
        meson setup build --prefix=/usr --buildtype=release \
            -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled \
            -Dvmwgfx=disabled -Dfreedreno=disabled -Dvc4=disabled -Detnaviv=disabled \
            -Dvalgrind=disabled -Dman-pages=disabled -Dtests=false -Dcairo-tests=disabled
        ninja -C build -j"$(nproc)"
        DESTDIR="$STG/libdrm" ninja -C build install
    )
    pkg_done libdrm 2.4.124 "$STG/libdrm"
    rm -rf "$BLD/libdrm-2.4.124"
fi

echo "=== [3/7] libevdev 1.13.4 ==="
if [ ! -f /var/lib/kpkg/libevdev.info ]; then
    fetch libevdev-1.13.4.tar.xz "https://www.freedesktop.org/software/libevdev/libevdev-1.13.4.tar.xz"
    rm -rf "$BLD/libevdev-1.13.4" "$STG/libevdev"
    tar -xf "$SRC/libevdev-1.13.4.tar.xz" -C "$BLD"
    (
        cd "$BLD/libevdev-1.13.4"
        meson setup build --prefix=/usr --buildtype=release \
            -Dtests=disabled -Ddocumentation=disabled
        ninja -C build -j"$(nproc)"
        DESTDIR="$STG/libevdev" ninja -C build install
    )
    pkg_done libevdev 1.13.4 "$STG/libevdev"
    rm -rf "$BLD/libevdev-1.13.4"
fi

echo "=== [4/7] xkeyboard-config 2.44 ==="
if [ ! -f /var/lib/kpkg/xkeyboard-config.info ]; then
    fetch xkeyboard-config-2.44.tar.xz "https://xorg.freedesktop.org/archive/individual/data/xkeyboard-config/xkeyboard-config-2.44.tar.xz"
    rm -rf "$BLD/xkeyboard-config-2.44" "$STG/xkeyboard-config"
    tar -xf "$SRC/xkeyboard-config-2.44.tar.xz" -C "$BLD"
    (
        cd "$BLD/xkeyboard-config-2.44"
        meson setup build --prefix=/usr --buildtype=release
        ninja -C build -j"$(nproc)"
        DESTDIR="$STG/xkeyboard-config" ninja -C build install
    )
    pkg_done xkeyboard-config 2.44 "$STG/xkeyboard-config"
    rm -rf "$BLD/xkeyboard-config-2.44"
fi

echo "=== [5/7] libxkbcommon 1.8.1 ==="
if [ ! -f /var/lib/kpkg/libxkbcommon.info ]; then
    fetch libxkbcommon-1.8.1.tar.gz "https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-1.8.1.tar.gz"
    rm -rf "$BLD/libxkbcommon-xkbcommon-1.8.1" "$STG/libxkbcommon"
    tar -xf "$SRC/libxkbcommon-1.8.1.tar.gz" -C "$BLD"
    (
        cd "$BLD/libxkbcommon-xkbcommon-1.8.1"
        meson setup build --prefix=/usr --buildtype=release \
            -Denable-x11=false -Denable-wayland=false \
            -Denable-xkbregistry=false -Denable-tools=false \
            -Denable-docs=false -Denable-bash-completion=false
        ninja -C build -j"$(nproc)"
        DESTDIR="$STG/libxkbcommon" ninja -C build install
    )
    pkg_done libxkbcommon 1.8.1 "$STG/libxkbcommon"
    rm -rf "$BLD/libxkbcommon-xkbcommon-1.8.1"
fi

echo "=== [6/7] Upstream Plymouth 24.004.60 ==="
if [ ! -f /var/lib/kpkg/plymouth.info ]; then
    fetch plymouth-24.004.60.tar.xz "https://www.freedesktop.org/software/plymouth/releases/plymouth-24.004.60.tar.xz"
    rm -rf "$BLD/plymouth-24.004.60" "$STG/plymouth"
    tar -xf "$SRC/plymouth-24.004.60.tar.xz" -C "$BLD"
    (
        cd "$BLD/plymouth-24.004.60"
        meson setup build --prefix=/usr --buildtype=release \
            -Dpango=disabled -Dfreetype=disabled -Dgtk=disabled -Ddocs=false \
            -Dsystemd-integration=true \
            -Dbackground-color=0x090d16 \
            -Dbackground-start-color-stop=0x090d16 \
            -Dbackground-end-color-stop=0x090d16 \
            -Dboot-tty=/dev/tty1 \
            -Dshutdown-tty=/dev/tty63 \
            -Drelease-file=/etc/os-release
        ninja -C build -j"$(nproc)"
        DESTDIR="$STG/plymouth" ninja -C build install
    )
    pkg_done plymouth 24.004.60 "$STG/plymouth"
    rm -rf "$BLD/plymouth-24.004.60"
fi

echo "=== [7/7] KaaijkOS Plymouth Thema (K-spinner) + GRUB boot-splash ==="
if [ -d "$THEME_SRC" ]; then
    S="$STG/kaaijkos-plymouth-theme"
    rm -rf "$S"
    mkdir -p "$S/usr/share/plymouth/themes/kaaijkos" "$S/etc/plymouth" "$S/etc/systemd/system/plymouth-quit.service.d"
    cp -a "$THEME_SRC/." "$S/usr/share/plymouth/themes/kaaijkos/"
    chmod -R a+rX "$S/usr/share/plymouth/themes/kaaijkos"
    cat > "$S/etc/plymouth/plymouthd.conf" << 'PLYCONF'
[Daemon]
Theme=kaaijkos
ShowDelay=0
DeviceTimeout=5
PLYCONF
    chmod 644 "$S/etc/plymouth/plymouthd.conf"
    cat > "$S/etc/systemd/system/plymouth-quit.service.d/kaaijkos-min-splash.conf" << 'PLYQUIT'
[Service]
ExecStartPre=/usr/bin/sleep 1.1
ExecStartPre=-/usr/bin/plymouth update --status=fadeout
ExecStartPre=/usr/bin/sleep 0.45
PLYQUIT
    chmod 644 "$S/etc/systemd/system/plymouth-quit.service.d/kaaijkos-min-splash.conf"
    pkg_done kaaijkos-plymouth-theme 1.2 "$S"
fi

if [ -f "$BOOT_SPLASH_SRC" ]; then
    SG="$STG/kaaijkos-grub-theme"
    rm -rf "$SG"
    mkdir -p "$SG/boot/grub/themes/kaaijkos"
    cp -a /boot/grub/themes/kaaijkos/. "$SG/boot/grub/themes/kaaijkos/"
    install -m 644 "$BOOT_SPLASH_SRC" "$SG/boot/grub/themes/kaaijkos/boot-splash.png"
    pkg_done kaaijkos-grub-theme 1.3 "$SG"
fi

if [ -f "$GRUB_TMPL_SRC" ]; then
    ROOT_DEV="$(findmnt -no SOURCE / || awk '$2=="/"{print $1}' /proc/mounts | tail -n1)"
    ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV")"
    [ -n "$ROOT_UUID" ] || { echo "FOUT: kon ROOT_UUID niet bepalen!"; exit 1; }
    cp -a /boot/grub/grub.cfg /boot/grub/grub.cfg.bak
    sed "s/<ROOT_UUID>/${ROOT_UUID}/g" "$GRUB_TMPL_SRC" > /boot/grub/grub.cfg
    grub-script-check /boot/grub/grub.cfg
fi

systemctl daemon-reload
echo "=== Fase 5d KLAAR! Plymouth versie & thema: ==="
plymouthd --version || true
cat /etc/plymouth/plymouthd.conf
