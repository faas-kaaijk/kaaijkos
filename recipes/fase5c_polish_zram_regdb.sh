#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.1 — Fase 5c: Boot-polish (ZRAM swap, wireless-regdb, DHCP & blacklist)
# ==============================================================================
set -euo pipefail

echo "=== [1/4] DHCP UseHostname=false (stopt networkd hostname warning) ==="
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-ethernet.network << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes

[DHCPv4]
UseHostname=false
EOF

echo "=== [2/4] Floppy & pcspkr blacklisten ==="
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/kaaijkos-blacklist.conf << 'EOF'
blacklist floppy
blacklist pcspkr
EOF

echo "=== [3/4] Wireless-regdb 2026.09.03 van kernel.org (via kpkg) ==="
TMP="$(mktemp -d /tmp/regdb.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
REGDB_TAR="wireless-regdb-2026.09.03.tar.xz"
if [ -s "/work/sources/${REGDB_TAR}" ]; then
    cp -f "/work/sources/${REGDB_TAR}" "$REGDB_TAR"
else
    curl -fsSL -O "https://mirrors.edge.kernel.org/pub/software/network/wireless-regdb/${REGDB_TAR}"
fi
tar -xf "$REGDB_TAR"
S=/work/stage/wireless-regdb; rm -rf "$S" && mkdir -p "$S/usr/lib/firmware"
install -v -m644 wireless-regdb-2026.09.03/regulatory.db     "$S/usr/lib/firmware/"
install -v -m644 wireless-regdb-2026.09.03/regulatory.db.p7s "$S/usr/lib/firmware/"
kpkg pack "$S" wireless-regdb 2026.09.03
kpkg install /var/cache/kpkg/wireless-regdb-2026.09.03.kpkg.tar.zst
rm -rf "$S"

echo "=== [4/4] KaaijkOS ZRAM zstd-swap service (50% van RAM, via kpkg) ==="
S=/work/stage/kaaijkos-zram; rm -rf "$S"
mkdir -p "$S/usr/bin" "$S/usr/lib/systemd/system"

if [ -f /work/tools/kaaijkos-zram ]; then
    cp -f /work/tools/kaaijkos-zram "$S/usr/bin/kaaijkos-zram"
else
    cat << 'ZRAM_SH' > "$S/usr/bin/kaaijkos-zram"
#!/usr/bin/env bash
set -euo pipefail
case "${1:-start}" in
    start)
        modprobe zram
        [ -b /dev/zram0 ] || exit 1
        grep -q '^/dev/zram0 ' /proc/swaps && exit 0
        MEM_KB=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        ZRAM_BYTES=$(( (MEM_KB / 2) * 1024 ))
        [ "$ZRAM_BYTES" -lt 536870912 ]  && ZRAM_BYTES=536870912
        [ "$ZRAM_BYTES" -gt 4294967296 ] && ZRAM_BYTES=4294967296
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
        echo "$ZRAM_BYTES" > /sys/block/zram0/disksize
        mkswap -L KAAIJKOS_ZRAM /dev/zram0 >/dev/null
        swapon -p 100 /dev/zram0
        ;;
    stop)
        swapoff /dev/zram0 2>/dev/null || true
        echo 1 > /sys/block/zram0/reset 2>/dev/null || true
        ;;
esac
ZRAM_SH
fi
chmod 755 "$S/usr/bin/kaaijkos-zram"

cat << 'ZRAM_UNIT' > "$S/usr/lib/systemd/system/kaaijkos-zram.service"
[Unit]
Description=KaaijkOS Compressed ZRAM Swap (zstd)
DefaultDependencies=no
Before=swap.target systemd-oomd.service
After=systemd-modules-load.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/kaaijkos-zram start
ExecStop=/usr/bin/kaaijkos-zram stop

[Install]
WantedBy=swap.target
ZRAM_UNIT

kpkg pack "$S" kaaijkos-zram 1.0
kpkg install /var/cache/kpkg/kaaijkos-zram-1.0.kpkg.tar.zst
rm -rf "$S"

systemctl enable kaaijkos-zram.service
if systemctl is-system-running >/dev/null 2>&1; then
    systemctl daemon-reload
    systemctl start kaaijkos-zram.service
    swapon --show
    free -h
fi
echo "=== Fase 5c KLAAR! ==="
