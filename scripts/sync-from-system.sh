#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cp /etc/os-release /etc/kaaijkos-release /etc/issue /etc/mkinitcpio.conf "$REPO/rootfs-configs/etc/"
cp /etc/nix/nix.conf "$REPO/rootfs-configs/etc/nix/"
cp /boot/loader/loader.conf "$REPO/rootfs-configs/boot/loader/"
cp /boot/loader/entries/*.conf "$REPO/rootfs-configs/boot/loader/entries/"
cp /usr/local/bin/kpkg /usr/local/bin/kosapps "$REPO/tools/"
zcat /proc/config.gz > "$REPO/kernel/config-7.1.8-kaaijkos"
echo "Systeemconfigs gesynchroniseerd naar $REPO"
