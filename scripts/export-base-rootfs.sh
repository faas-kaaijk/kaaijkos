#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run als root" >&2; exit 1; }

OUT="${1:-/tmp/KaaijkOS-1.0-base-rootfs.tar.zst}"
echo "=== Schone KaaijkOS base rootfs exporteren naar $OUT ==="

tar --zstd -cpf "$OUT" \
    --one-file-system \
    --exclude=/proc/* \
    --exclude=/sys/* \
    --exclude=/dev/* \
    --exclude=/tmp/* \
    --exclude=/run/* \
    --exclude=/mnt/* \
    --exclude=/boot/* \
    --exclude=/nix/* \
    --exclude=/home/faas/Projects/* \
    --exclude=/root/.bash_history \
    --exclude=/home/faas/.bash_history \
    --exclude=/root/.ssh/* \
    --exclude=/home/faas/.ssh/* \
    --exclude=/etc/ssh/ssh_host_* \
    --exclude=/etc/machine-id \
    --exclude=/var/log/journal/* \
    /

ls -lh "$OUT"
