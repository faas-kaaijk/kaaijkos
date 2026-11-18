#!/usr/bin/env bash
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run dit script als root: sudo ./build-os.sh" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_IMG="${REPO_DIR}/KaaijkOS-1.0-x86_64.img"
ROOTFS_TAR="${1:-${REPO_DIR}/KaaijkOS-1.0-base-rootfs.tar.zst}"
RELEASE_URL="https://github.com/faas-kaaijk/kaaijkos/releases/latest/download/KaaijkOS-1.0-base-rootfs.tar.zst"
MNT="/mnt/kaaijkos-build"

for cmd in sfdisk losetup mkfs.fat mkfs.ext4 tar zstd curl chroot blkid; do
    command -v "$cmd" >/dev/null || { echo "Ontbrekend tool: $cmd" >&2; exit 1; }
done

if [ ! -f "$ROOTFS_TAR" ]; then
    echo "=== Base rootfs downloaden van GitHub Releases ==="
    curl -fL "$RELEASE_URL" -o "$ROOTFS_TAR"
fi

echo "=== 1. Schijf-image aanmaken (6 GiB GPT + EFI + ext4) ==="
rm -f "$OUT_IMG"
truncate -s 6G "$OUT_IMG"
sfdisk "$OUT_IMG" << 'PARTS'
label: gpt
size=512M, type=U
type=L
PARTS

LOOP=$(losetup --find --show --partscan "$OUT_IMG")
cleanup() {
    umount -R "$MNT" 2>/dev/null || true
    losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

mkfs.fat -F32 "${LOOP}p1"
mkfs.ext4 -F "${LOOP}p2"

mkdir -p "$MNT"
mount "${LOOP}p2" "$MNT"
mkdir -p "$MNT/boot"
mount "${LOOP}p1" "$MNT/boot"

echo "=== 2. KaaijkOS base rootfs uitpakken ==="
tar -C "$MNT" --zstd -xpf "$ROOTFS_TAR"

echo "=== 3. KaaijkOS configs, logo's & tools installeren ==="
cp -a "$REPO_DIR/rootfs-configs/etc/." "$MNT/etc/"
mkdir -p "$MNT/usr/share/systemd/bootctl" "$MNT/usr/share/pixmaps" "$MNT/usr/share/backgrounds/kaaijkos"
cp "$REPO_DIR/assets/boot/splash-kaaijkos.bmp" "$MNT/usr/share/systemd/bootctl/"
cp "$REPO_DIR/assets/logos/kaaijkos-logo"*.png "$MNT/usr/share/pixmaps/"
cp "$REPO_DIR/assets/logos/kaaijkos-wallpaper.png" "$MNT/usr/share/backgrounds/kaaijkos/"
cp "$REPO_DIR/tools/kpkg" "$MNT/usr/local/bin/kpkg"
cp "$REPO_DIR/tools/kosapps" "$MNT/usr/local/bin/kosapps"
chmod +x "$MNT/usr/local/bin/kpkg" "$MNT/usr/local/bin/kosapps"

echo "=== 4. fstab, PARTUUID & bootloader configureren ==="
BOOT_UUID=$(blkid -s UUID -o value "${LOOP}p1")
ROOT_UUID=$(blkid -s UUID -o value "${LOOP}p2")
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "${LOOP}p2")

cat << FSTAB > "$MNT/etc/fstab"
UUID=${ROOT_UUID}  /      ext4  rw,relatime  0 1
UUID=${BOOT_UUID}  /boot  vfat  rw,relatime  0 2
FSTAB

mkdir -p "$MNT/boot/loader/entries" "$MNT/boot/EFI/KaaijkOS"
cp -a "$REPO_DIR/rootfs-configs/boot/loader/." "$MNT/boot/loader/"
sed -i "s|PARTUUID=[^ ]*|PARTUUID=${ROOT_PARTUUID}|g" "$MNT/boot/loader/entries/"*.conf

echo "=== 5. systemd-boot & UKI genereren in chroot ==="
mount --types proc /proc "$MNT/proc"
mount --rbind /sys "$MNT/sys"
mount --rbind /dev "$MNT/dev"

if [ "${BUILD_KERNEL:-0}" = "1" ]; then
    mkdir -p "$MNT/usr/src/kaaijkos"
    cp -a "$REPO_DIR/kernel/." "$MNT/usr/src/kaaijkos/"
    chroot "$MNT" /usr/src/kaaijkos/build-kernel.sh
fi

chroot "$MNT" systemd-machine-id-setup
chroot "$MNT" bootctl --esp-path=/boot install --no-variables
chroot "$MNT" mkinitcpio -P

echo "=== KLAAR! Bootable image gebouwd: $OUT_IMG ==="
