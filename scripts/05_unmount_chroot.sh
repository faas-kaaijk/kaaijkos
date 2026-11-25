#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.0 — Chroot & doelschijf 100% schoon unmounten vóór eerste boot
# ==============================================================================
set -euo pipefail

KOS="${KOS:-/mnt/kaaijkos}"

if [ "$(id -u)" -ne 0 ]; then
    echo "FOUT: Draai dit script als root." >&2
    exit 1
fi

sync
for m in \
    "$KOS/boot/efi" \
    "$KOS/dev/pts" \
    "$KOS/dev/shm" \
    "$KOS/dev" \
    "$KOS/proc" \
    "$KOS/sys" \
    "$KOS/run" \
    "$KOS"; do
    if mountpoint -q "$m"; then
        umount -v "$m"
    fi
done
sync

if mount | grep -qE "[[:space:]]${KOS}(/| |$)"; then
    echo "WAARSCHUWING: Er zijn nog actieve mounts onder ${KOS}:" >&2
    mount | grep -E "[[:space:]]${KOS}(/| |$)"
    exit 1
fi

echo "=== ${KOS} 100% SCHOON GE-UNMOUNT — KLAAR VOOR REBOOT / NIEUWE VM! ==="
