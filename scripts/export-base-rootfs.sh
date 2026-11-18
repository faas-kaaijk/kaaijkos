#!/usr/bin/env bash
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run als root" >&2; exit 1; }

OUT="${1:-/tmp/KaaijkOS-1.0-base-rootfs.tar.zst}"
CLEAN_ETC="/tmp/kaaijkos-clean-etc"
rm -rf "$CLEAN_ETC" && mkdir -p "$CLEAN_ETC/etc"

# Schone passwd & group zonder user faas
grep -v '^faas:' /etc/passwd > "$CLEAN_ETC/etc/passwd"
grep -v '^faas:' /etc/group | sed 's/,faas//g; s/:faas$/:/' > "$CLEAN_ETC/etc/group"
chmod 644 "$CLEAN_ETC/etc/passwd" "$CLEAN_ETC/etc/group"

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
    --exclude=/home/faas \
    --exclude=/home/faas/* \
    --exclude=/root/.bash_history \
    --exclude=/root/.ssh/* \
    --exclude=/etc/ssh/ssh_host_* \
    --exclude=/etc/machine-id \
    --exclude=/etc/passwd \
    --exclude=/etc/passwd- \
    --exclude=/etc/group \
    --exclude=/etc/group- \
    --exclude=/etc/shadow \
    --exclude=/etc/shadow- \
    --exclude=/etc/gshadow \
    --exclude=/etc/gshadow- \
    --exclude=/var/log/journal/* \
    / \
    -C "$CLEAN_ETC" etc

rm -rf "$CLEAN_ETC"
ls -lh "$OUT"
