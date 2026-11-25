#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.0 — Stap 1: Schijf Partitioneren (GPT Hybrid BIOS + UEFI) & Layout
#
# Gebruik:
#   sudo ./scripts/00_prepare_disk.sh /dev/sdX [--yes]
#
# Maakt op <disk>:
#   - Partitie 1:  2 MiB  BIOS boot (GPT 21686148-..., SeaBIOS GRUB i386-pc)
#   - Partitie 2: 512 MiB EFI System Partition (FAT32, label: KAAIJK-EFI)
#   - Partitie 3: Rest    KaaijkOS RootFS (ext4, label: KAAIJKOS_ROOT)
# En richt /mnt/kaaijkos met merged-/usr symlinks + /work mappen in.
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "FOUT: Draai dit script als root." >&2
    exit 1
fi

DISK="${1:-}"
AUTO_YES="${2:-}"
KOS="/mnt/kaaijkos"

if [ -z "$DISK" ] || [ ! -b "$DISK" ]; then
    echo "Gebruik: sudo $0 /dev/sdX [--yes]" >&2
    echo "Beschikbare schijven:"
    lsblk -d -o NAME,SIZE,MODEL,TYPE
    exit 1
fi

DISK_REAL="$(readlink -f "$DISK")"
HOST_ROOT_SRC="$(findmnt -no SOURCE / 2>/dev/null || true)"
HOST_PKNAME=""
if [ -b "$HOST_ROOT_SRC" ]; then
    HOST_PKNAME="/dev/$(lsblk -no pkname "$HOST_ROOT_SRC" 2>/dev/null || true)"
    if [ "$(readlink -f "$HOST_PKNAME" 2>/dev/null || true)" = "$DISK_REAL" ]; then
        echo "WEIGERING: $DISK_REAL is de actieve host-schijf waar '/' op draait!" >&2
        exit 1
    fi
fi

if mount | grep -qE "^${DISK_REAL}p?[0-9]*[[:space:]]"; then
    echo "WEIGERING: Een partitie van $DISK_REAL is momenteel gemount! Unmount eerst handmatig." >&2
    exit 1
fi

for cmd in sfdisk wipefs mkfs.fat mkfs.ext4 partprobe lsblk; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FOUT: Tool '$cmd' ontbreekt op het hostsysteem." >&2; exit 1; }
done

echo "================================================================================"
echo "  WAARSCHUWING: ALLE DATA OP ${DISK_REAL} WORDT GEWIST!"
lsblk -o NAME,SIZE,MODEL,FSTYPE,MOUNTPOINTS "$DISK_REAL"
echo "================================================================================"

if [ "$AUTO_YES" != "--yes" ]; then
    read -r -p "Typ exact 'YES' om ${DISK_REAL} opnieuw in te delen: " CONFIRM
    [ "$CONFIRM" = "YES" ] || { echo "Afgebroken."; exit 1; }
fi

echo "=== [1/4] GPT Hybrid BIOS+UEFI partities aanmaken op $DISK_REAL ==="
wipefs -af "$DISK_REAL"
sfdisk "$DISK_REAL" << 'EOF'
label: gpt
size=2M,   type=21686148-6449-6E6F-744E-656564454649, name="BIOS-BOOT"
size=512M, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="KAAIJKOS-EFI"
           type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="KAAIJKOS-ROOT"
EOF
partprobe "$DISK_REAL" || true
sleep 1

if [[ "$DISK_REAL" =~ [0-9]$ ]]; then
    P2="${DISK_REAL}p2"
    P3="${DISK_REAL}p3"
else
    P2="${DISK_REAL}2"
    P3="${DISK_REAL}3"
fi

echo "=== [2/4] Bestandssystemen formatteren ==="
mkfs.fat -F32 -n KAAIJK-EFI "$P2"
mkfs.ext4 -F -L KAAIJKOS_ROOT "$P3"

echo "=== [3/4] Mounten op $KOS ==="
mkdir -p "$KOS"
mount "$P3" "$KOS"
mkdir -p "$KOS/boot/efi"
mount "$P2" "$KOS/boot/efi"

echo "=== [4/4] Merged-/usr structuur & KaaijkOS /work aanmaken ==="
mkdir -p "$KOS"/{etc,var,tools,lib64} "$KOS"/usr/{bin,lib,sbin}
for link in bin lib sbin; do
    [ -e "$KOS/$link" ] || ln -sv "usr/$link" "$KOS/$link"
done
mkdir -p "$KOS"/work/{sources,build,recipes,packages,logs,stage,stamps,tools}

echo "=== KLAAR! Schijfstatus: ==="
lsblk -f "$DISK_REAL"
echo "Nu klaar voor Stap 2: sudo ./scripts/01_fetch_sources.sh"
