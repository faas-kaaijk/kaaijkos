#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.1 — Fase 5a: UEFI Secure Boot (Debian shim 16.1 + eigen MOK)
# - Haalt BSD-gelicentieerde Debian shim 16.1 + mmx64.efi (MokManager) op
# - Genereert een lokaal, uniek MOK-sleutelpaar (/etc/kernel/kaaijkos-mok.*)
# - Schrijft /etc/grub/sbat.csv en bouwt/signeert SBAT GRUB 2.14 + kernel
# ==============================================================================
set -euo pipefail

mountpoint -q /boot/efi || mount /boot/efi

echo "=== [1/5] Officiele BSD-gelicentieerde Debian shim 16.1 + MokManager ophalen ==="
TMP="$(mktemp -d /tmp/kaaijkos-shim.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

SHIM_DEB="shim-signed_1.51+16.1-2_amd64.deb"
HELP_DEB="shim-helpers-amd64-signed_1+16.1+2_amd64.deb"
SHIM_URL="https://deb.debian.org/debian/pool/main/s/shim-signed/${SHIM_DEB}"
HELP_URL="https://deb.debian.org/debian/pool/main/s/shim-helpers-amd64-signed/${HELP_DEB}"

if [ -s "/work/sources/${SHIM_DEB}" ]; then
    cp -f "/work/sources/${SHIM_DEB}" shim-signed.deb
else
    curl -fsSL -o shim-signed.deb "$SHIM_URL"
fi

if [ -s "/work/sources/${HELP_DEB}" ]; then
    cp -f "/work/sources/${HELP_DEB}" shim-helpers.deb
else
    curl -fsSL -o shim-helpers.deb "$HELP_URL"
fi

mkdir -p ex1 ex2
(cd ex1 && ar x ../shim-signed.deb && tar -xf data.tar.*)
(cd ex2 && ar x ../shim-helpers.deb && tar -xf data.tar.*)

SHIM_BIN="$(find ex1 -name 'shimx64.efi.signed' | head -n1)"
MM_BIN="$(find ex2 -name 'mmx64.efi.signed' | head -n1)"
COPYRIGHT_FILE="$(find ex1 -name 'copyright' | head -n1 || true)"

[ -f "$SHIM_BIN" ] || { echo "FOUT: shimx64.efi.signed niet gevonden!"; exit 1; }
[ -f "$MM_BIN" ]   || { echo "FOUT: mmx64.efi.signed niet gevonden!"; exit 1; }

S=/work/stage/kaaijkos-shim
rm -rf "$S"
mkdir -p "$S/usr/share/kaaijkos/secureboot" "$S/usr/share/licenses/kaaijkos-shim"
install -v -m644 "$SHIM_BIN" "$S/usr/share/kaaijkos/secureboot/shimx64.efi"
install -v -m644 "$MM_BIN"   "$S/usr/share/kaaijkos/secureboot/mmx64.efi"
[ -n "$COPYRIGHT_FILE" ] && install -v -m644 "$COPYRIGHT_FILE" "$S/usr/share/licenses/kaaijkos-shim/copyright"

kpkg pack "$S" kaaijkos-shim 16.1
kpkg install /var/cache/kpkg/kaaijkos-shim-16.1.kpkg.tar.zst
rm -rf "$S"

echo "=== [2/5] Eigen lokaal KaaijkOS Secure Boot MOK-sleutelpaar genereren ==="
mkdir -p /etc/kernel
MOK_KEY="/etc/kernel/kaaijkos-mok.key"
MOK_CRT="/etc/kernel/kaaijkos-mok.crt"
MOK_CER="/etc/kernel/kaaijkos-mok.cer"

if [ ! -f "$MOK_KEY" ]; then
    openssl req -new -x509 -newkey rsa:4096 -nodes -sha256 -days 36500 \
        -subj "/O=KaaijkOS/CN=KaaijkOS Secure Boot MOK/" \
        -keyout "$MOK_KEY" -out "$MOK_CRT"
    chmod 600 "$MOK_KEY"
    chmod 644 "$MOK_CRT"
fi
openssl x509 -in "$MOK_CRT" -outform DER -out "$MOK_CER"
chmod 644 "$MOK_CER"

echo "=== [3/5] SBAT-metadata voor pure upstream GRUB 2.14 schrijven ==="
mkdir -p /etc/grub
cat > /etc/grub/sbat.csv << 'SBAT'
sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md
grub,5,Free Software Foundation,grub,2.14,https://www.gnu.org/software/grub/
grub.kaaijkos,1,KaaijkOS,grub,2.14-kaaijkos,https://github.com/faas-kaaijk/kaaijkos
SBAT

echo "=== [4/5] /usr/bin/kaaijkos-sign-boot (v1.5) installeren via kpkg ==="
S=/work/stage/kaaijkos-secureboot
rm -rf "$S"
mkdir -p "$S/usr/bin"
if [ -f /work/tools/kaaijkos-sign-boot ]; then
    cp -f /work/tools/kaaijkos-sign-boot "$S/usr/bin/kaaijkos-sign-boot"
else
    cat << 'SIGNTOOL_EOF' > "$S/usr/bin/kaaijkos-sign-boot"
#!/usr/bin/env bash
# KaaijkOS 1.1 — Bouwt SBAT GRUB 2.14 (v1.5) + embedded fonts + signeert GRUB & kernel veilig via /tmp
set -euo pipefail

MOK_KEY="/etc/kernel/kaaijkos-mok.key"
MOK_CRT="/etc/kernel/kaaijkos-mok.crt"
MOK_CER="/etc/kernel/kaaijkos-mok.cer"
SHIM_DIR="/usr/share/kaaijkos/secureboot"
SBSIGN="/usr/lib/systemd/systemd-sbsign"

[ -x "$SBSIGN" ]  || { echo "FOUT: $SBSIGN ontbreekt!"; exit 1; }
[ -f "$MOK_KEY" ] || { echo "FOUT: $MOK_KEY ontbreekt!"; exit 1; }
mountpoint -q /boot/efi || mount /boot/efi

TMP="$(mktemp -d /tmp/kaaijkos-sign.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

verify_pe_sig() {
    python3 - "$1" << 'PY'
import struct, sys
path = sys.argv[1]
b = open(path, "rb").read()
lfanew = struct.unpack_from("<I", b, 0x3C)[0]
magic, = struct.unpack_from("<H", b, lfanew + 24)
dd_off = lfanew + 24 + (112 if magic == 0x20b else 96)
sec_va, sec_sz = struct.unpack_from("<II", b, dd_off + 4*8)
assert sec_va > 0 and sec_sz > 0, f"{path}: geen PE-handtekening!"
assert sec_va + sec_sz == len(b), f"{path}: size mismatch! VA=0x{sec_va:x} Size=0x{sec_sz:x} File=0x{len(b):x}"
dwLen, wRev, wType = struct.unpack_from("<IHH", b, sec_va)
assert wRev == 0x200 and wType == 0x2, f"{path}: ongeldige WIN_CERT header!"
print(f"  [OK] {path}: filesize=0x{len(b):x}, SecDir=0x{sec_va:x}+0x{sec_sz:x}, WIN_CERT=0x{dwLen:x}")
PY
}

has_pe_sig() {
    python3 - "$1" << 'PY'
import struct, sys
b = open(sys.argv[1], "rb").read()
lfanew = struct.unpack_from("<I", b, 0x3C)[0]
magic, = struct.unpack_from("<H", b, lfanew + 24)
dd_off = lfanew + 24 + (112 if magic == 0x20b else 96)
sec_va, sec_sz = struct.unpack_from("<II", b, dd_off + 4*8)
sys.exit(0 if (sec_va > 0 and sec_sz > 0 and sec_va + sec_sz == len(b)) else 1)
PY
}

WANT_MODS="part_gpt part_msdos fat ext2 btrfs xfs iso9660 squash4 \
           memdisk tar \
           search search_fs_uuid search_label search_fs_file \
           normal configfile linux boot chain echo test true loadenv \
           keystatus sleep efifwsetup \
           efi_gop efi_uga video video_fb video_colors \
           font bitmap bitmap_scale trig png jpeg tga gfxterm gfxterm_background gfxmenu \
           gzio zstd ls cat help reboot halt tpm"
MODS=""
for m in $WANT_MODS; do
    [ -f "/usr/lib/grub/x86_64-efi/${m}.mod" ] && MODS="${MODS} ${m}"
done
MODS="${MODS# }"

ROOT_DEV="$(findmnt -no SOURCE / 2>/dev/null || awk '$2=="/"{print $1}' /proc/mounts | tail -n1)"
ROOT_UUID="$(blkid -s UUID -o value "$ROOT_DEV" 2>/dev/null || findmnt -no UUID / 2>/dev/null || true)"
[ -n "$ROOT_UUID" ] || { echo "FOUT: kon ROOT_UUID van / ($ROOT_DEV) niet bepalen!"; exit 1; }

cat > "$TMP/load.cfg" << LOADCFG
search.fs_uuid ${ROOT_UUID} root
set prefix=(\$root)'/boot/grub'
LOADCFG

MEMDISK_ARGS=()
if ls /boot/grub/themes/kaaijkos/*.pf2 >/dev/null 2>&1; then
    mkdir -p "$TMP/memdisk/fonts"
    cp -f /boot/grub/themes/kaaijkos/*.pf2 "$TMP/memdisk/fonts/"
    tar --format=ustar -C "$TMP/memdisk" -cf "$TMP/fonts.tar" fonts
    MEMDISK_ARGS=(--memdisk "$TMP/fonts.tar")
    echo "[kaaijkos-sign-boot] Ingebedde memdisk-fonts: $(ls -1 "$TMP/memdisk/fonts" | tr '\n' ' ')"
fi

echo "[kaaijkos-sign-boot] Bouw zelfstandige SBAT GRUB 2.14 EFI image (ROOT_UUID=${ROOT_UUID})..."
# shellcheck disable=SC2086
grub-mkimage \
    -O x86_64-efi \
    -d /usr/lib/grub/x86_64-efi \
    -c "$TMP/load.cfg" \
    "${MEMDISK_ARGS[@]}" \
    -p /boot/grub \
    --sbat=/etc/grub/sbat.csv \
    -o "$TMP/grubx64.efi.unsigned" \
    $MODS

echo "[kaaijkos-sign-boot] Signeer grubx64.efi veilig in /tmp (niet direct op FAT32)..."
"$SBSIGN" sign \
    --private-key "$MOK_KEY" \
    --certificate "$MOK_CRT" \
    --output "$TMP/grubx64.efi.signed" \
    "$TMP/grubx64.efi.unsigned"
verify_pe_sig "$TMP/grubx64.efi.signed"

echo "[kaaijkos-sign-boot] Installeer shim 16.1 + MokManager + gesigneerde GRUB + MOK cert..."
mkdir -p /boot/efi/EFI/BOOT /boot/efi/EFI/KaaijkOS

cp -f "$SHIM_DIR/shimx64.efi"     /boot/efi/EFI/BOOT/BOOTX64.EFI
cp -f "$SHIM_DIR/mmx64.efi"       /boot/efi/EFI/BOOT/mmx64.efi
cp -f "$TMP/grubx64.efi.signed"   /boot/efi/EFI/BOOT/grubx64.efi
cp -f "$MOK_CER"                  /boot/efi/EFI/BOOT/kaaijkos-mok.cer

cp -f "$SHIM_DIR/shimx64.efi"     /boot/efi/EFI/KaaijkOS/shimx64.efi
cp -f "$SHIM_DIR/mmx64.efi"       /boot/efi/EFI/KaaijkOS/mmx64.efi
cp -f "$TMP/grubx64.efi.signed"   /boot/efi/EFI/KaaijkOS/grubx64.efi
cp -f "$MOK_CER"                  /boot/efi/EFI/KaaijkOS/kaaijkos-mok.cer

if has_pe_sig /boot/vmlinuz-kaaijkos; then
    echo "[kaaijkos-sign-boot] /boot/vmlinuz-kaaijkos heeft al een geldige PE-handtekening."
else
    echo "[kaaijkos-sign-boot] Signeer /boot/vmlinuz-kaaijkos veilig in /tmp..."
    cp -f /boot/vmlinuz-kaaijkos "$TMP/vmlinuz.unsigned"
    "$SBSIGN" sign \
        --private-key "$MOK_KEY" \
        --certificate "$MOK_CRT" \
        --output "$TMP/vmlinuz.signed" \
        "$TMP/vmlinuz.unsigned"
    verify_pe_sig "$TMP/vmlinuz.signed"
    cp -f "$TMP/vmlinuz.signed" /boot/vmlinuz-kaaijkos
fi

sync
echo "[kaaijkos-sign-boot] Eindverificatie op schijf:"
verify_pe_sig /boot/efi/EFI/BOOT/grubx64.efi
verify_pe_sig /boot/vmlinuz-kaaijkos
echo "=== SBAT ==="
objcopy -O binary --only-section=.sbat "$TMP/grubx64.efi.unsigned" "$TMP/sbat.out"
cat "$TMP/sbat.out"
echo ""
SIGNTOOL_EOF
fi

chmod 755 "$S/usr/bin/kaaijkos-sign-boot"
kpkg pack "$S" kaaijkos-secureboot 1.5
kpkg install /var/cache/kpkg/kaaijkos-secureboot-1.5.kpkg.tar.zst
rm -rf "$S"

echo "=== [5/5] Eerste keer signeren & installeren uitvoeren ==="
kaaijkos-sign-boot
