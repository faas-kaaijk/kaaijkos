#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.0 — Veilig de geïsoleerde KaaijkOS-chroot binnengaan (of heropenen)
# Mount /dev, /dev/pts, /proc, /sys, /run en /dev/shm idempotent (als nodig).
# ==============================================================================
set -euo pipefail

KOS="${KOS:-/mnt/kaaijkos}"

if [ "$(id -u)" -ne 0 ]; then
    echo "FOUT: Draai dit script als root." >&2
    exit 1
fi
if ! mountpoint -q "$KOS"; then
    echo "FOUT: $KOS is niet gemount!" >&2
    exit 1
fi

mkdir -pv "$KOS"/{dev,proc,sys,run}
mountpoint -q "$KOS/dev"     || mount -v --bind /dev "$KOS/dev"
mountpoint -q "$KOS/dev/pts" || mount -vt devpts devpts -o gid=5,mode=0620 "$KOS/dev/pts"
mountpoint -q "$KOS/proc"    || mount -vt proc proc "$KOS/proc"
mountpoint -q "$KOS/sys"     || mount -vt sysfs sysfs "$KOS/sys"
mountpoint -q "$KOS/run"     || mount -vt tmpfs tmpfs "$KOS/run"
if [ -h "$KOS/dev/shm" ]; then
    install -v -d -m 1777 "${KOS}$(realpath /dev/shm)"
else
    mountpoint -q "$KOS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$KOS/dev/shm"
fi

echo "=== Welkom in (KaaijkOS-chroot) [$KOS] ==="
exec chroot "$KOS" /usr/bin/env -i \
    HOME=/root \
    TERM="${TERM:-xterm-256color}" \
    PS1='(KaaijkOS-chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin \
    MAKEFLAGS="-j$(nproc)" \
    /bin/bash --login
