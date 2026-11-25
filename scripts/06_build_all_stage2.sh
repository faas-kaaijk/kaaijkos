#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.0 — Fase 3 Alle 10 Build-Rondes achter elkaar draaien (IN CHROOT!)
# Maakt alle 85 definitieve KaaijkOS pakketten met kpkg 2.0 + logs in /work/logs.
# ==============================================================================
set -euo pipefail

if [ -d /mnt/kaaijkos/work ]; then
    echo "FOUT: Draai dit script BINNEN (KaaijkOS-chroot), niet op het hostsysteem!" >&2
    exit 1
fi

RDIR="${RDIR:-/work/recipes}"
LDIR="/work/logs"
mkdir -p "$LDIR" /work/stage /work/build

ROUNDS=(
    ronde01_glibc_base.sh
    ronde02_compression_kpkg.sh
    ronde03_build_essentials.sh
    ronde04_binutils_security.sh
    ronde05_gawk_gcc.sh
    ronde06_cli_libs.sh
    ronde07_openssl_python_meson.sh
    ronde08_core_grub.sh
    ronde09_systemd_core.sh
    ronde10_kernel_net_ssh.sh
)

for r in "${ROUNDS[@]}"; do
    SCRIPT="${RDIR}/${r}"
    LOG="${LDIR}/${r%.sh}.log"
    [ -f "$SCRIPT" ] || { echo "FOUT: Recept ontbreekt: $SCRIPT" >&2; exit 1; }
    echo ">>> Start ${r} (log: ${LOG})..."
    bash "$SCRIPT" 2>&1 | tee "$LOG"
done

echo "=== ALLE 10 FASE-3 RONDES 100% VOLTOOID! ==="
kpkg list
