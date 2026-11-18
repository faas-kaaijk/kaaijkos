#!/usr/bin/env bash
set -euo pipefail

KVER="7.1.8"
WORKDIR="/usr/src/kaaijkos/kernel-${KVER}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p /usr/src/kaaijkos
cd /usr/src/kaaijkos

if [ ! -f "linux-${KVER}.tar.xz" ]; then
    curl -LO "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-${KVER}.tar.xz"
fi
rm -rf "linux-${KVER}"
tar -xf "linux-${KVER}.tar.xz"
cd "linux-${KVER}"

cp "${SCRIPT_DIR}/config-7.1.8-kaaijkos" .config
make olddefconfig
make -j"$(nproc)"
make modules_install
cp arch/x86/boot/bzImage "/usr/lib/modules/${KVER}-kaaijkos/vmlinuz"
mkinitcpio -P
echo "Kernel ${KVER}-kaaijkos succesvol gebouwd en UKI bijgewerkt!"
