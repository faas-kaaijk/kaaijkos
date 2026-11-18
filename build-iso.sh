#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/root/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

[ "$(id -u)" -eq 0 ] || { echo "Run this script as root: sudo ./build-iso.sh" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_ISO="${REPO_DIR}/KaaijkOS-1.0-x86_64.iso"
ROOTFS_TAR="${1:-/tmp/KaaijkOS-1.0-base-rootfs.tar.zst}"
WORK_DIR="/var/tmp/kaaijkos-iso-build"
STAGE_ROOT="${WORK_DIR}/rootfs"
ISO_ROOT="${WORK_DIR}/iso"
EFI_MNT="${WORK_DIR}/efimnt"
KVER="7.1.8-kaaijkos"

for cmd in mksquashfs xorriso grub-mkimage grub-install mkfs.fat mkinitcpio zstd tar blkid; do
    command -v "$cmd" >/dev/null || { echo "Missing required tool: $cmd" >&2; exit 1; }
done

cleanup() {
    umount -lf "$EFI_MNT" 2>/dev/null || true
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

rm -rf "$WORK_DIR"
mkdir -p "$STAGE_ROOT" "$ISO_ROOT/boot/grub/i386-pc" "$ISO_ROOT/kaaijkos" "$EFI_MNT"

if [ ! -f "$ROOTFS_TAR" ]; then
    if [ -f "${REPO_DIR}/KaaijkOS-1.0-base-rootfs.tar.zst" ]; then
        ROOTFS_TAR="${REPO_DIR}/KaaijkOS-1.0-base-rootfs.tar.zst"
    else
        echo "=== Generating clean base rootfs archive first ==="
        "${REPO_DIR}/scripts/export-base-rootfs.sh" "$ROOTFS_TAR"
    fi
fi

echo "=== 1. Extracting clean KaaijkOS base rootfs ==="
tar -C "$STAGE_ROOT" --zstd -xpf "$ROOTFS_TAR"
mkdir -p "$STAGE_ROOT"/{proc,sys,dev,tmp,run,mnt,boot,home,var/log/journal}
chmod 1777 "$STAGE_ROOT/tmp"
find "$STAGE_ROOT" \( -uid 1000 -o -uid 1001 -o -gid 1000 -o -gid 1001 \) -exec chown -h 0:0 {} + 2>/dev/null || true

echo "=== 2. Installing KaaijkOS configs, branding & installer tools ==="
cp -a "$REPO_DIR/rootfs-configs/etc/." "$STAGE_ROOT/etc/"
mkdir -p "$STAGE_ROOT/usr/share/systemd/bootctl" "$STAGE_ROOT/usr/share/pixmaps" "$STAGE_ROOT/usr/share/backgrounds/kaaijkos"
[ -f "$REPO_DIR/assets/splash-kaaijkos.bmp" ] && cp -a "$REPO_DIR/assets/splash-kaaijkos.bmp" "$STAGE_ROOT/usr/share/systemd/bootctl/"
compgen -G "$REPO_DIR/assets/kaaijkos-logo*.png" >/dev/null && cp -a "$REPO_DIR/assets/kaaijkos-logo"*.png "$STAGE_ROOT/usr/share/pixmaps/"
[ -f "$REPO_DIR/assets/kaaijkos-wallpaper.png" ] && cp -a "$REPO_DIR/assets/kaaijkos-wallpaper.png" "$STAGE_ROOT/usr/share/backgrounds/kaaijkos/"
install -m 755 "$REPO_DIR/tools/kpkg" "$STAGE_ROOT/usr/local/bin/kpkg"
install -m 755 "$REPO_DIR/tools/kosapps" "$STAGE_ROOT/usr/local/bin/kosapps"
install -m 755 "$REPO_DIR/tools/kaaijkos-install" "$STAGE_ROOT/usr/local/bin/kaaijkos-install"

# Ensure universal storage modules are listed in installed system mkinitcpio.conf
sed -i 's/^MODULES=.*/MODULES=(virtio virtio_blk virtio_scsi virtio_pci virtio_net nvme ahci sd_mod sr_mod ext4 vfat)/' "$STAGE_ROOT/etc/mkinitcpio.conf"

# Bundle offline GRUB i386-pc closure so Legacy BIOS installs work 100% offline
GRUB_BIN="$(readlink -f "$(command -v grub-install)")"
GRUB_PREFIX="$(dirname "$(dirname "$GRUB_BIN")")"
GRUB_BIOS_DIR="${GRUB_PREFIX}/lib/grub/i386-pc"

if [ -d "$GRUB_BIOS_DIR" ] && command -v nix-store >/dev/null; then
    echo "=== 3. Bundling offline GRUB i386-pc bootloader closure ==="
    mkdir -p "$STAGE_ROOT/nix/store"
    for sp in $(nix-store -qR "$GRUB_PREFIX"); do
        cp -a "$sp" "$STAGE_ROOT/nix/store/"
    done
    for gbin in grub-install grub-mkimage grub-bios-setup grub-mkrelpath grub-probe; do
        if [ -x "$GRUB_PREFIX/bin/$gbin" ]; then
            ln -sf "$GRUB_PREFIX/bin/$gbin" "$STAGE_ROOT/usr/local/bin/$gbin"
        fi
    done
fi

echo "=== 4. Building Universal Live Kernel, Initramfs & UEFI UKI ==="
cp "/usr/lib/modules/${KVER}/vmlinuz" "$ISO_ROOT/boot/vmlinuz-kaaijkos"

cat << 'LIVECONF' > "${WORK_DIR}/mkinitcpio-live.conf"
MODULES=(loop overlay squashfs iso9660 isofs vfat fat nls_cp437 nls_iso8859_1 ext4 cdrom sr_mod sd_mod sg nvme nvme_core ahci libahci ata_piix ata_generic virtio virtio_ring virtio_pci virtio_blk virtio_scsi virtio_net vmw_pvscsi usb_storage uas xhci_pci xhci_hcd ehci_pci ehci_hcd usbhid hid_generic)
BINARIES=()
FILES=()
HOOKS=(base udev keyboard keymap consolefont block kaaijkos_live filesystems)
COMPRESSION="zstd"
LIVECONF

# Build standalone Live initramfs (used by Legacy BIOS & UEFI)
mkinitcpio -k "$KVER" -c "${WORK_DIR}/mkinitcpio-live.conf" -g "$ISO_ROOT/boot/initramfs-live.img"

# Build Live Unified Kernel Image (.efi) with KaaijkOS splash screen for UEFI
echo "quiet loglevel=3 vt.global_cursor_default=0 fbcon=nodefer" > "${WORK_DIR}/live-cmdline.txt"
mkinitcpio -k "$KVER" -c "${WORK_DIR}/mkinitcpio-live.conf" \
    --uki "${WORK_DIR}/kaaijkos-live.efi" \
    --cmdline "${WORK_DIR}/live-cmdline.txt" \
    --splash /usr/share/systemd/bootctl/splash-kaaijkos.bmp

echo "=== 5. Compressing Live SquashFS image (kaaijkos/system.sfs) ==="
mksquashfs "$STAGE_ROOT" "$ISO_ROOT/kaaijkos/system.sfs" -comp zstd -Xcompression-level 15 -noappend

echo "=== 6. Configuring Legacy BIOS (GRUB i386-pc) & UEFI (systemd-boot) bootloaders ==="
cat << 'GRUBCFG' > "$ISO_ROOT/boot/grub/grub.cfg"
set default=0
set timeout=5

insmod all_video
insmod gfxterm
set gfxmode=auto
terminal_output gfxterm

set menu_color_normal=white/black
set menu_color_highlight=black/cyan

menuentry "Install KaaijkOS 1.0 (x86_64 Live Installer)" {
    linux /boot/vmlinuz-kaaijkos quiet loglevel=3 vt.global_cursor_default=0 fbcon=nodefer
    initrd /boot/initramfs-live.img
}

menuentry "KaaijkOS 1.0 Live Rescue Mode (Verbose Boot)" {
    linux /boot/vmlinuz-kaaijkos loglevel=4
    initrd /boot/initramfs-live.img
}
GRUBCFG

cp -r "$GRUB_BIOS_DIR"/*.mod "$GRUB_BIOS_DIR"/*.lst "$ISO_ROOT/boot/grub/i386-pc/" 2>/dev/null || true

grub-mkimage -O i386-pc -d "$GRUB_BIOS_DIR" \
    -o "${WORK_DIR}/core.img" \
    -p /boot/grub \
    biosdisk iso9660 part_gpt part_msdos fat ext2 normal boot linux configfile loopback chain search search_label search_fs_uuid search_fs_file test all_video

cat "${GRUB_BIOS_DIR}/cdboot.img" "${WORK_DIR}/core.img" > "$ISO_ROOT/boot/grub/bios.img"

# Create dynamically sized FAT32 El Torito UEFI boot image
UKI_MB=$(du -m "${WORK_DIR}/kaaijkos-live.efi" | awk '{print $1 + 32}')
[ "$UKI_MB" -lt 64 ] && UKI_MB=64
dd if=/dev/zero of="$ISO_ROOT/boot/efiboot.img" bs=1M count="$UKI_MB" status=none
mkfs.fat -F 32 -n "KAAIJK_EFI" "$ISO_ROOT/boot/efiboot.img" >/dev/null
mount -o loop "$ISO_ROOT/boot/efiboot.img" "$EFI_MNT"

mkdir -p "$EFI_MNT/EFI/BOOT" "$EFI_MNT/EFI/KaaijkOS" "$EFI_MNT/loader/entries"
cp -r /usr/lib/systemd/boot/efi/systemd-bootx64.efi "$EFI_MNT/EFI/BOOT/BOOTX64.EFI"
cp -r "${WORK_DIR}/kaaijkos-live.efi" "$EFI_MNT/EFI/KaaijkOS/kaaijkos-live.efi"

cat << 'LOADER' > "$EFI_MNT/loader/loader.conf"
default kaaijkos-live.conf
timeout 3
console-mode keep
editor yes
LOADER

cat << 'ENTRY' > "$EFI_MNT/loader/entries/kaaijkos-live.conf"
title Install KaaijkOS 1.0 (x86_64 Live Installer)
efi /EFI/KaaijkOS/kaaijkos-live.efi
ENTRY

# Mirror EFI & loader on ISO root for Windows Rufus ISO-mode compatibility
mkdir -p "$ISO_ROOT/EFI/BOOT" "$ISO_ROOT/EFI/KaaijkOS" "$ISO_ROOT/loader/entries"
cp -r "$EFI_MNT/EFI/." "$ISO_ROOT/EFI/"
cp -r "$EFI_MNT/loader/." "$ISO_ROOT/loader/"

sync
umount "$EFI_MNT"

echo "=== 7. Building Hybrid UEFI + Legacy BIOS ISO: $OUT_ISO ==="
rm -f "$OUT_ISO"
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "KAAIJKOS_1_0" \
    -appid "KaaijkOS 1.0 Live & Installer" \
    -publisher "KaaijkOS Project" \
    -preparer "KaaijkOS build-iso.sh" \
    -eltorito-boot boot/grub/bios.img \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    --grub2-mbr "${GRUB_BIOS_DIR}/boot_hybrid.img" \
    -eltorito-alt-boot \
    -e boot/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output "$OUT_ISO" \
    "$ISO_ROOT"

echo "=== KaaijkOS 1.0 Live & Installer ISO successfully built! ==="
ls -lh "$OUT_ISO"
