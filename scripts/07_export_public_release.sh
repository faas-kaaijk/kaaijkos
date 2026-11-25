#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.0 — Privacy-Schone Publieke GitHub Release Exporter
#
# Draai dit script OP een draaiend KaaijkOS 1.0 systeem (als root) om schone
# release-archieven te maken ZONDER persoonlijke geheimen:
#   - Strippen: /etc/kernel/kaaijkos-signing-key.pem (privé X.509 kernel key!)
#   - Strippen: /etc/ssh/ssh_host_* (unieke SSH host keys)
#   - Strippen: /etc/machine-id & /var/lib/dbus/machine-id
#   - Strippen: /root/.bash_history & /root/.ssh/*
#   - Opschonen: /etc/shadow -> root-account op '!' (locked; gebruiker zet zelf 'passwd root')
#   - Repacken: linux-kaaijkos-*.kpkg.tar.zst zonder de privé signing key
# ==============================================================================
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "FOUT: Draai dit script als root op een draaiend KaaijkOS 1.0 systeem." >&2
    exit 1
fi

STAMP="$(date +%Y%m%d-%H%M)"
OUTDIR="${1:-/work/releases/kaaijkos-1.0-public-${STAMP}}"
TMPDIR="$(mktemp -d /tmp/kaaijkos-pubrel.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$OUTDIR" "$TMPDIR/sanitized/etc" "$TMPDIR/kpkg_cache"

echo "=== [1/4] Veilige /etc/shadow (root locked '!') voorbereiden ==="
awk -F: 'BEGIN { OFS=":" } { if ($1 == "root") $2 = "!"; print }' /etc/shadow > "$TMPDIR/sanitized/etc/shadow"
chmod 600 "$TMPDIR/sanitized/etc/shadow"

echo "=== [2/4] Publiek, opgeschoond RootFS-archief bouwen ==="
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
zstd -T0 -6 --rm "$RAW_TAR" -o "$OUTDIR/kaaijkos-1.0-rootfs-public.tar.zst"

echo "=== [3/4] Publieke kpkg-repo bouwen (zonder privé kernel signing key!) ==="
cp -a /var/cache/kpkg/*.kpkg.tar.zst "$TMPDIR/kpkg_cache/" 2>/dev/null || true
for kpkg_file in "$TMPDIR/kpkg_cache"/linux-kaaijkos-*.kpkg.tar.zst; do
    [ -f "$kpkg_file" ] || continue
    KEX="$TMPDIR/kpkg_extract"
    rm -rf "$KEX" && mkdir -p "$KEX"
    tar -C "$KEX" --zstd -xpf "$kpkg_file"
    rm -vf "$KEX/etc/kernel/kaaijkos-signing-key.pem"
    tar -C "$KEX" --zstd -cpf "${kpkg_file}.clean" .
    mv -f "${kpkg_file}.clean" "$kpkg_file"
    rm -rf "$KEX"
done

tar --numeric-owner \
    -cf "$OUTDIR/kaaijkos-1.0-kpkg-repo-public.tar" \
    -C "$TMPDIR" kpkg_cache \
    -C / work/recipes

echo "=== [4/4] Geautomatiseerde lek-controle & SHA256SUMS ==="
ROOT_LIST="$(mktemp "$TMPDIR/rootlist.XXXXXX")"
tar --zstd -tf "$OUTDIR/kaaijkos-1.0-rootfs-public.tar.zst" > "$ROOT_LIST"

for forbidden in 'kaaijkos-signing-key\.pem' 'ssh_host_' '^etc/machine-id$' 'bash_history' '^root/\.ssh' '^etc/shadow-$'; do
    if grep -E "$forbidden" "$ROOT_LIST"; then
        echo "KRITIEKE FOUT: Gevoelig bestand gevonden in rootfs-public ($forbidden)!" >&2
        exit 1
    fi
done

SHADOW_CHECK="$(tar --zstd -xOf "$OUTDIR/kaaijkos-1.0-rootfs-public.tar.zst" etc/shadow | awk -F: '$1=="root"{print $2}')"
if [ "$SHADOW_CHECK" != "!" ]; then
    echo "KRITIEKE FOUT: Root wachtwoordveld in publiek /etc/shadow is niet '!' ('$SHADOW_CHECK')!" >&2
    exit 1
fi

for kpkg_file in "$OUTDIR/kaaijkos-1.0-kpkg-repo-public.tar"; do
    for inner in $(tar -tf "$kpkg_file" | grep 'linux-kaaijkos-.*\.kpkg\.tar\.zst$' || true); do
        if tar -xOf "$kpkg_file" "$inner" | tar --zstd -tf - | grep -q 'signing-key'; then
            echo "KRITIEKE FOUT: signing-key aangetroffen in $inner!" >&2
            exit 1
        fi
    done
done

cd "$OUTDIR"
sha256sum kaaijkos-1.0-* > SHA256SUMS

echo "================================================================================"
echo "  PUBLIEKE RELEASE 100% SCHOON EN GEVERIFIEERD IN: $OUTDIR"
ls -lh "$OUTDIR"
cat SHA256SUMS
echo "  LET OP: Gebruikers die rootfs-public uitpakken moeten vóór eerste boot:"
echo "    chroot /mnt/kaaijkos passwd root"
echo "    chroot /mnt/kaaijkos systemd-machine-id-setup"
echo "================================================================================"
