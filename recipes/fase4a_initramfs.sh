#!/usr/bin/env bash
set -euo pipefail

S=/work/stage/kaaijkos-initramfs
rm -rf "$S"
mkdir -p "$S/usr/bin"

cat << 'MKINIT_EOF' > "$S/usr/bin/kaaijkos-mkinitramfs"
#!/usr/bin/env bash
# KaaijkOS 1.0 — 100% Eigen Initramfs Builder (0% Arch mkinitcpio)
set -euo pipefail

KVER="${1:-7.3.6-kaaijkos}"
OUT="${2:-/boot/initramfs-kaaijkos.img}"
MODDIR="/usr/lib/modules/$KVER"

[ -d "$MODDIR" ] || { echo "FOUT: $MODDIR bestaat niet!"; exit 1; }

WORK="$(mktemp -d /tmp/kaaijkos-initramfs.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "[kaaijkos-mkinitramfs] Bouw initramfs voor Linux $KVER..."

mkdir -p "$WORK"/{usr/bin,usr/sbin,usr/lib,lib64,dev,proc,sys,run,tmp,newroot,etc}
ln -s usr/bin "$WORK/bin"
ln -s usr/sbin "$WORK/sbin"
ln -s usr/lib "$WORK/lib"

mknod -m 600 "$WORK/dev/console" c 5 1
mknod -m 666 "$WORK/dev/null" c 1 3

copy_bin() {
    local name="$1" bin real_bin dst link_dst lib
    bin="$(command -v "$name" || true)"
    [ -n "$bin" ] || { echo "  (skip: $name niet gevonden)"; return 0; }
    real_bin="$(readlink -f "$bin")"
    case "$real_bin" in
        /usr/*) dst="$WORK$real_bin" ;;
        *)      dst="$WORK/usr/bin/$(basename "$real_bin")" ;;
    esac
    mkdir -p "$(dirname "$dst")"
    [ -e "$dst" ] || cp -L "$real_bin" "$dst"

    if [ "$bin" != "$real_bin" ]; then
        case "$bin" in
            /bin/*)  link_dst="$WORK/usr/bin/$(basename "$bin")" ;;
            /sbin/*) link_dst="$WORK/usr/sbin/$(basename "$bin")" ;;
            *)       link_dst="$WORK$bin" ;;
        esac
        mkdir -p "$(dirname "$link_dst")"
        ln -sf "$real_bin" "$link_dst"
    fi

    for lib in $(ldd "$real_bin" 2>/dev/null | grep -oE '/[^[:space:]]+' || true); do
        [ -e "$lib" ] || continue
        case "$lib" in
            /lib64/*)
                mkdir -p "$WORK/lib64"
                [ -e "$WORK/lib64/$(basename "$lib")" ] || cp -L "$lib" "$WORK/lib64/$(basename "$lib")"
                ;;
            /lib/*)
                mkdir -p "$WORK/usr/lib"
                [ -e "$WORK/usr/lib/$(basename "$lib")" ] || cp -L "$lib" "$WORK/usr/lib/$(basename "$lib")"
                ;;
            *)
                mkdir -p "$WORK$(dirname "$lib")"
                [ -e "$WORK$lib" ] || cp -L "$lib" "$WORK$lib"
                ;;
        esac
    done
}

# 1. Essentiele userspace binaries + libraries
for b in bash sh cat ls mkdir mknod sleep rm mv ln readlink tr cut head sync grep \
         mount umount switch_root blkid findfs setsid \
         kmod modprobe insmod lsmod e2fsck fsck.ext4; do
    copy_bin "$b"
done
ln -sf bash "$WORK/usr/bin/sh"

# 2. Universele kernel-modules + ALLE transitive dependencies uit modules.dep
python3 - "$MODDIR" "$WORK/usr/lib/modules/$KVER" << 'PYMOD_EOF'
import os, shutil, sys

src_root, dst_root = sys.argv[1], sys.argv[2]
os.makedirs(dst_root, exist_ok=True)

# Kopieer alle modules.* metadata-bestanden (dep, alias, builtin, symbols, ...)
for name in os.listdir(src_root):
    if name.startswith("modules."):
        p = os.path.join(src_root, name)
        if os.path.isfile(p):
            shutil.copy2(p, os.path.join(dst_root, name))

deps = {}
dep_file = os.path.join(src_root, "modules.dep")
with open(dep_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or ":" not in line:
            continue
        mod, reqs = line.split(":", 1)
        deps[mod.strip()] = reqs.strip().split() if reqs.strip() else []

prefixes = (
    "kernel/drivers/virtio/",
    "kernel/drivers/block/virtio_blk",
    "kernel/drivers/block/loop",
    "kernel/drivers/scsi/",
    "kernel/drivers/ata/",
    "kernel/drivers/nvme/",
    "kernel/drivers/cdrom/",
    "kernel/drivers/usb/common/",
    "kernel/drivers/usb/core/",
    "kernel/drivers/usb/host/",
    "kernel/drivers/usb/storage/",
    "kernel/drivers/hid/hid",
    "kernel/drivers/hid/usbhid/",
    "kernel/drivers/mmc/",
    "kernel/fs/ext4/",
    "kernel/fs/jbd2/",
    "kernel/fs/mbcache",
    "kernel/fs/fat/",
    "kernel/fs/nls/",
    "kernel/fs/isofs/",
    "kernel/fs/squashfs/",
    "kernel/fs/overlayfs/",
    "kernel/fs/btrfs/",
    "kernel/fs/xfs/",
    "kernel/crypto/crc",
    "kernel/lib/crc",
    "kernel/arch/x86/crypto/crc",
)

selected = set()
stack = [m for m in deps if m.startswith(prefixes)]
while stack:
    m = stack.pop()
    if m in selected:
        continue
    selected.add(m)
    for d in deps.get(m, []):
        if d not in selected:
            stack.append(d)

copied = 0
for rel in sorted(selected):
    src = os.path.join(src_root, rel)
    dst = os.path.join(dst_root, rel)
    if os.path.isfile(src):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1

print(f"[kaaijkos-mkinitramfs] {copied} universele kernel-modules (+ deps) ingepakt.")
PYMOD_EOF

# 3. Schrijf /init script (ondersteunt root=UUID/PARTUUID/LABEL/dev + rescue shell)
cat << 'INIT_EOF' > "$WORK/init"
#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

mount -t devtmpfs devtmpfs /dev 2>/dev/null || true
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tmpfs tmpfs /run

echo "[KaaijkOS] Initramfs gestart — hardware detecteren..."

load_hw() {
    for m in virtio_pci virtio_scsi virtio_blk ahci nvme sd_mod sr_mod \
             uas usb_storage xhci_pci ehci_pci ohci_pci uhci_hcd \
             hid_generic usbhid loop ext4 vfat isofs squashfs overlay; do
        modprobe -q "$m" 2>/dev/null || true
    done
    for pass in 1 2; do
        for f in /sys/bus/*/devices/*/modalias /sys/devices/*/*/modalias /sys/devices/*/*/*/modalias; do
            [ -r "$f" ] || continue
            read -r alias < "$f" 2>/dev/null || continue
            case "$alias" in
                pci:*|virtio:*|scsi:*|usb:*|hid:*|mmc:*)
                    modprobe -qb "$alias" 2>/dev/null || true
                    ;;
            esac
        done
    done
}

ROOT_SPEC=""
ROOT_FSTYPE=""
ROOT_FLAGS="ro"
INIT_BIN="/sbin/init"
for arg in $(cat /proc/cmdline); do
    case "$arg" in
        root=*)       ROOT_SPEC="${arg#root=}" ;;
        rootfstype=*) ROOT_FSTYPE="${arg#rootfstype=}" ;;
        rootflags=*)  ROOT_FLAGS="${arg#rootflags=}" ;;
        init=*)       INIT_BIN="${arg#init=}" ;;
        rw)           ROOT_FLAGS="rw" ;;
        ro)           ROOT_FLAGS="ro" ;;
    esac
done

load_hw

ROOT_DEV=""
i=0
while [ "$i" -lt 75 ]; do
    case "$ROOT_SPEC" in
        /dev/*)
            [ -b "$ROOT_SPEC" ] && ROOT_DEV="$ROOT_SPEC"
            ;;
        UUID=*|PARTUUID=*|LABEL=*)
            ROOT_DEV="$(findfs "$ROOT_SPEC" 2>/dev/null || true)"
            ;;
    esac
    [ -n "$ROOT_DEV" ] && [ -b "$ROOT_DEV" ] && break
    if [ "$((i % 10))" -eq 5 ]; then
        load_hw
    fi
    sleep 0.2
    i=$((i + 1))
done

if [ -z "$ROOT_DEV" ] || [ ! -b "$ROOT_DEV" ]; then
    echo "!!! [KaaijkOS] Root device '$ROOT_SPEC' niet gevonden! Rescue shell:"
    blkid || true
    ls -l /dev/sd* /dev/vd* /dev/nvme* 2>/dev/null || true
    exec /bin/sh
fi

echo "[KaaijkOS] Mount root: $ROOT_DEV ($ROOT_FLAGS)"
if [ -n "$ROOT_FSTYPE" ]; then
    mount -t "$ROOT_FSTYPE" -o "$ROOT_FLAGS" "$ROOT_DEV" /newroot || exec /bin/sh
else
    mount -o "$ROOT_FLAGS" "$ROOT_DEV" /newroot || exec /bin/sh
fi

[ -x "/newroot$INIT_BIN" ] || INIT_BIN="/usr/lib/systemd/systemd"
echo "[KaaijkOS] Start $INIT_BIN..."
exec switch_root /newroot "$INIT_BIN"
INIT_EOF
chmod 755 "$WORK/init"

# 4. SELF-TEST: controleer in chroot dat alle initramfs-binaries echt draaien!
echo "[kaaijkos-mkinitramfs] Self-test van binaries + libraries..."
chroot "$WORK" /bin/sh -c 'modprobe --version | head -n1; blkid --version; switch_root --version'

# 5. Pak in als SVR4 newc cpio + zstd (of gzip fallback)
COMP_CMD=(gzip -9)
if [ -f "/boot/config-$KVER" ] && grep -q '^CONFIG_RD_ZSTD=y' "/boot/config-$KVER"; then
    COMP_CMD=(zstd -19 -T0 -q)
    echo "[kaaijkos-mkinitramfs] Compressie: zstd (CONFIG_RD_ZSTD=y geverifieerd)"
else
    echo "[kaaijkos-mkinitramfs] Compressie: gzip"
fi

python3 - "$WORK" << 'PYCPIO_EOF' | "${COMP_CMD[@]}" > "${OUT}.tmp"
import os, stat, sys

root = sys.argv[1]
out = sys.stdout.buffer
ino = 1

def write_entry(relpath, mode, data=b"", rdev_maj=0, rdev_min=0, nlink=1):
    global ino
    name = relpath.encode("utf-8") + b"\x00"
    hdr = (
        f"070701"
        f"{ino:08x}{mode:08x}{0:08x}{0:08x}{nlink:08x}{0:08x}"
        f"{len(data):08x}{0:08x}{0:08x}{rdev_maj:08x}{rdev_min:08x}"
        f"{len(name):08x}{0:08x}"
    ).encode("ascii")
    ino += 1
    out.write(hdr)
    out.write(name)
    pad = (-(len(hdr) + len(name))) % 4
    if pad:
        out.write(b"\x00" * pad)
    if data:
        out.write(data)
        dpad = (-len(data)) % 4
        if dpad:
            out.write(b"\x00" * dpad)

for dirpath, dirnames, filenames in os.walk(root):
    dirnames.sort()
    filenames.sort()
    for d in list(dirnames):
        full = os.path.join(dirpath, d)
        rel = os.path.relpath(full, root)
        st = os.lstat(full)
        if stat.S_ISLNK(st.st_mode):
            write_entry(rel, st.st_mode, os.readlink(full).encode("utf-8"), nlink=1)
            dirnames.remove(d)
        else:
            write_entry(rel, st.st_mode, b"", nlink=2)
    for f in filenames:
        full = os.path.join(dirpath, f)
        rel = os.path.relpath(full, root)
        st = os.lstat(full)
        if stat.S_ISLNK(st.st_mode):
            write_entry(rel, st.st_mode, os.readlink(full).encode("utf-8"), nlink=1)
        elif stat.S_ISREG(st.st_mode):
            with open(full, "rb") as fp:
                data = fp.read()
            write_entry(rel, st.st_mode, data, nlink=1)
        elif stat.S_ISCHR(st.st_mode) or stat.S_ISBLK(st.st_mode):
            write_entry(rel, st.st_mode, b"", os.major(st.st_rdev), os.minor(st.st_rdev), nlink=1)

name = b"TRAILER!!!\x00"
hdr = (
    f"070701"
    f"{0:08x}{0:08x}{0:08x}{0:08x}{1:08x}{0:08x}"
    f"{0:08x}{0:08x}{0:08x}{0:08x}{0:08x}"
    f"{len(name):08x}{0:08x}"
).encode("ascii")
out.write(hdr)
out.write(name)
pad = (-(len(hdr) + len(name))) % 4
if pad:
    out.write(b"\x00" * pad)
out.flush()
PYCPIO_EOF

mv -f "${OUT}.tmp" "$OUT"
echo "[kaaijkos-mkinitramfs] KLAAR: $OUT ($(du -h "$OUT" | cut -f1))"
MKINIT_EOF

chmod 755 "$S/usr/bin/kaaijkos-mkinitramfs"
kpkg pack "$S" kaaijkos-initramfs 1.0
kpkg install /var/cache/kpkg/kaaijkos-initramfs-1.0.kpkg.tar.zst
rm -rf "$S"

kaaijkos-mkinitramfs 7.3.6-kaaijkos /boot/initramfs-kaaijkos.img
ls -lh /boot/vmlinuz-kaaijkos /boot/initramfs-kaaijkos.img
