#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS — Privacy-Schone Publieke GitHub Release Exporter
#
# Draai dit script OP een draaiend KaaijkOS systeem (als root) om schone
# release-archieven te maken ZONDER persoonlijke geheimen:
#   - Strippen: /etc/kernel/kaaijkos-signing-key.pem (privé X.509 kernel key!)
#   - Strippen: /etc/kernel/kaaijkos-mok.key & overige *.key/*.pem in /etc/kernel
#   - Strippen: /etc/ssh/ssh_host_* (unieke SSH host keys)
#   - Strippen: /etc/machine-id & /var/lib/dbus/machine-id
#   - Strippen: /root/.bash_history & /root/.ssh/*
#   - Opschonen: /etc/shadow -> root-account op '!' (locked; gebruiker zet zelf 'passwd root')
#   - Repacken: linux-kaaijkos-*.kpkg.tar.zst zonder privé signing keys
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "FOUT: Draai dit script als root op een draaiend KaaijkOS systeem." >&2
    exit 1
fi

KOS_VER="${KOS_VER:-1.1}"
STAMP="$(date +%Y%m%d-%H%M)"
OUTDIR="${1:-/work/releases/kaaijkos-${KOS_VER}-public-${STAMP}}"
TMPDIR="$(mktemp -d /tmp/kaaijkos-pubrel.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$OUTDIR" "$TMPDIR/sanitized/etc" "$TMPDIR/kpkg_cache"

echo "=== [1/4] Veilige /etc/shadow (root locked '!') voorbereiden ==="
awk -F: 'BEGIN { OFS=":" } { if ($1 == "root") $2 = "!"; print }' /etc/shadow > "$TMPDIR/sanitized/etc/shadow"
chmod 600 "$TMPDIR/sanitized/etc/shadow"

echo "=== [2/4] Publiek, opgeschoond RootFS-archief bouwen (v${KOS_VER}) ==="
RAW_TAR="$TMPDIR/rootfs-public.tar"
tar --numeric-owner --acls --xattrs \
    --exclude='/dev/*' \
    --exclude='/proc/*' \
    --exclude='/sys/*' \
    --exclude='/run/*' \
    --exclude='/tmp/*' \
    --exclude='/mnt/*' \
    --exclude='/media/*' \
    --exclude='/lost+found' \
    --exclude='/work/*' \
    --exclude='/var/cache/kpkg/*' \
    --exclude='/var/log/journal/*' \
    --exclude='/etc/kernel/kaaijkos-signing-key.pem' \
    --exclude='/etc/kernel/kaaijkos-mok.key' \
    --exclude='/etc/kernel/*.key' \
    --exclude='/etc/kernel/*.pem' \
    --exclude='/etc/ssh/ssh_host_*' \
    --exclude='/etc/machine-id' \
    --exclude='/var/lib/dbus/machine-id' \
    --exclude='/root/.bash_history' \
    --exclude='/root/.ssh' \
    --exclude='/root/.ssh/*' \
    --exclude='/etc/shadow' \
    --exclude='/etc/shadow-' \
    -cpf "$RAW_TAR" \
    /

tar --numeric-owner -C "$TMPDIR/sanitized" -rf "$RAW_TAR" etc/shadow
zstd -T0 -6 --rm "$RAW_TAR" -o "$OUTDIR/kaaijkos-${KOS_VER}-rootfs-public.tar.zst"

echo "=== [3/4] Publieke kpkg-repo bouwen (zonder privé kernel/MOK signing keys!) ==="
cp -a /var/cache/kpkg/*.kpkg.tar.zst "$TMPDIR/kpkg_cache/" 2>/dev/null || true
for kpkg_file in "$TMPDIR/kpkg_cache"/linux-kaaijkos-*.kpkg.tar.zst; do
    [ -f "$kpkg_file" ] || continue
    KEX="$TMPDIR/kpkg_extract"
    rm -rf "$KEX" && mkdir -p "$KEX"
    tar -C "$KEX" --zstd -xpf "$kpkg_file"
    rm -vf "$KEX"/etc/kernel/*.pem "$KEX"/etc/kernel/*.key 2>/dev/null || true
    tar -C "$KEX" --zstd -cpf "${kpkg_file}.clean" .
    mv -f "${kpkg_file}.clean" "$kpkg_file"
    rm -rf "$KEX"
done

tar --numeric-owner \
    -cf "$OUTDIR/kaaijkos-${KOS_VER}-kpkg-repo-public.tar" \
    -C "$TMPDIR" kpkg_cache \
    -C / work/recipes

echo "=== [4/4] Geautomatiseerde lek-controle & SHA256SUMS ==="
ROOT_LIST="$(mktemp "$TMPDIR/rootlist.XXXXXX")"
tar --zstd -tf "$OUTDIR/kaaijkos-${KOS_VER}-rootfs-public.tar.zst" > "$ROOT_LIST"

for forbidden in \
    'kaaijkos-signing-key\.pem' \
    'kaaijkos-mok\.key' \
    '^etc/kernel/.*\.(pem|key)$' \
    'ssh_host_' \
    '^etc/machine-id$' \
    'bash_history' \
    '^root/\.ssh' \
    '^etc/shadow-$'; do
    if grep -E "$forbidden" "$ROOT_LIST"; then
        echo "KRITIEKE FOUT: Gevoelig bestand gevonden in rootfs-public ($forbidden)!" >&2
        exit 1
    fi
done

SHADOW_CHECK="$(tar --zstd -xOf "$OUTDIR/kaaijkos-${KOS_VER}-rootfs-public.tar.zst" etc/shadow | awk -F: '$1=="root"{print $2}')"
if [ "$SHADOW_CHECK" != "!" ]; then
    echo "KRITIEKE FOUT: Root wachtwoordveld in publiek /etc/shadow is niet '!' ('$SHADOW_CHECK')!" >&2
    exit 1
fi

for inner in $(tar -tf "$OUTDIR/kaaijkos-${KOS_VER}-kpkg-repo-public.tar" | grep 'linux-kaaijkos-.*\.kpkg\.tar\.zst$' || true); do
    if tar -xOf "$OUTDIR/kaaijkos-${KOS_VER}-kpkg-repo-public.tar" "$inner" | tar --zstd -tf - | grep -qE 'signing-key|\.(pem|key)$'; then
        echo "KRITIEKE FOUT: signing-key aangetroffen in $inner!" >&2
        exit 1
    fi
done

cd "$OUTDIR"
sha256sum "kaaijkos-${KOS_VER}-"* > SHA256SUMS

echo "================================================================================"
echo "  PUBLIEKE RELEASE 100% SCHOON EN GEVERIFIEERD IN: $OUTDIR"
ls -lh "$OUTDIR"
cat SHA256SUMS
echo "  LET OP: Gebruikers die rootfs-public uitpakken moeten vóór eerste boot:"
echo "    chroot /mnt/kaaijkos passwd root"
echo "    chroot /mnt/kaaijkos systemd-machine-id-setup"
echo "================================================================================"
