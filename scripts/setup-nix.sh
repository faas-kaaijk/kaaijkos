#!/usr/bin/env bash
set -euo pipefail
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon --yes
mkdir -p /etc/nix
grep -q "experimental-features" /etc/nix/nix.conf 2>/dev/null || \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
systemctl restart nix-daemon
