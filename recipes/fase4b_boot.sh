#!/usr/bin/env bash
set -euo pipefail

# Gebruik: ./fase4b_boot.sh [ROOT_UUID] [EFI_UUID]
# Zonder argumenten worden de partities automatisch en chroot-veilig bepaald.
ROOT_PART="${ROOT_PART:-$(findfs LABEL=KAAIJKOS_ROOT 2>/dev/null || df -P / | awk 'NR==2 && $1 ~ /^\/dev\// {print $1}' || true)}"
EFI_PART="${EFI_PART:-$(findfs LABEL=KAAIJK-EFI 2>/dev/null || df -P /boot/efi 2>/dev/null | awk 'NR==2 && $1 ~ /^\/dev\// {print $1}' || true)}"

ROOT_UUID="${1:-${ROOT_UUID:-$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null || true)}}"
EFI_UUID="${2:-${EFI_UUID:-$(blkid -s UUID -o value "$EFI_PART" 2>/dev/null || true)}}"

if [ -z "$ROOT_UUID" ] || [ -z "$EFI_UUID" ]; then
    echo "FOUT: Kon ROOT_UUID ('$ROOT_UUID') of EFI_UUID ('$EFI_UUID') niet automatisch bepalen." >&2
    echo "Geef ze handmatig mee: $0 <ROOT_UUID> <EFI_UUID>" >&2
    exit 1
fi
echo "Gebruikte partities: ROOT=${ROOT_PART:-?} (UUID=${ROOT_UUID}) | EFI=${EFI_PART:-?} (UUID=${EFI_UUID})"

echo "=== [1/4] KaaijkOS 1.1 systeemconfiguratie ==="

cat > /etc/hostname << 'EOF'
KaaijkOS
EOF

cat > /etc/hosts << 'EOF'
127.0.0.1  localhost KaaijkOS
::1        localhost ip6-localhost ip6-loopback
EOF

cat > /etc/os-release << 'EOF'
NAME="KaaijkOS"
PRETTY_NAME="KaaijkOS 1.1 (Linux 7.3.6-kaaijkos)"
ID=kaaijkos
VERSION="1.1"
VERSION_ID="1.1"
ANSI_COLOR="1;36"
HOME_URL="https://github.com/faas-kaaijk/kaaijkos"
EOF

cat > /etc/locale.conf << 'EOF'
LANG=en_US.UTF-8
EOF

cat > /etc/vconsole.conf << 'EOF'
KEYMAP=us
EOF

cat > /etc/fstab << EOF
# KaaijkOS 1.1 filesystem table
UUID=${ROOT_UUID}  /          ext4  defaults,noatime              0  1
UUID=${EFI_UUID}   /boot/efi  vfat  defaults,umask=0077,nofail    0  2
EOF

python3 - << 'PY_ISSUE'
LOGO = [
    "                        -=----",
    "            :--        =====--",
    "         ---===      ++++====-",
    "        --===++   =++++++++   ",
    "        ==++*#%+=++++++++     ",
    "        ++###++++++++++       ",
    "        ##*++++++++++         ",
    "        +++++***++====        ",
    "        +++++++======+++++    ",
    "        ==+++++ ===+++++++++  ",
    "        -=====+    ++++++++===",
    "            -==       +++====-",
]
R, D, C, W = "\x1b[0m", "\x1b[2m", "\x1b[1;36m", "\x1b[1;37m"
def color_line(r, line):
    out = []
    for c, ch in enumerate(line):
        if ch == " ":
            out.append(" "); continue
        if c <= 15 and r <= 4:
            col = "\x1b[1;33m" if r <= 2 else "\x1b[1;31m"
        elif c <= 15:
            col = "\x1b[1;34m" if r <= 8 else "\x1b[1;36m"
        elif r <= 6:
            col = "\x1b[1;36m"
        else:
            col = "\x1b[1;35m"
        out.append(f"{col}{ch}")
    out.append(R)
    return "".join(out)

right = {
    3: f"{C}KaaijkOS 1.1{R}",
    4: f"{D}------------------------------{R}",
    5: f"{W}Host  {R}: \\n",
    6: f"{W}IP    {R}: \\4",
    7: f"{W}TTY   {R}: \\l",
    8: f"{D}------------------------------{R}",
    9: f"{D}Geautoriseerde toegang alleen.{R}",
}
lines = ["\x1b[H\x1b[2J"]
for i, raw in enumerate(LOGO):
    left = color_line(i, raw)
    txt = right.get(i, "")
    lines.append(f"{left}    {txt}" if txt else left)
lines.extend(["", ""])
open("/etc/issue", "w", encoding="utf-8").write("\n".join(lines))
PY_ISSUE

cat > /etc/profile << 'EOF'
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin
export LANG=en_US.UTF-8
export EDITOR=nano
export PAGER=less
[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc
for _f in /etc/profile.d/*.sh; do
    [ -r "$_f" ] && . "$_f"
done
unset _f
EOF

cat > /etc/bash.bashrc << 'EOF'
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

__kaaijkos_prompt() {
    local rc=$?
    local C_RESET='\[\e[0m\]'
    local C_DIM='\[\e[2m\]'
    local C_CYAN='\[\e[1;36m\]'
    local C_BLUE='\[\e[1;34m\]'
    local C_RED='\[\e[1;31m\]'
    local C_GREEN='\[\e[1;32m\]'

    local err_tag=""
    local sym_col="$C_GREEN"
    if [ "$rc" -ne 0 ]; then
        err_tag=" ${C_RED}[${rc}]${C_RESET}"
        sym_col="$C_RED"
    fi

    if [ "$(id -u)" -eq 0 ]; then
        PS1="${C_CYAN}\h${C_RESET} ${C_DIM}>${C_RESET} ${C_RED}Root${C_RESET} ${C_BLUE}\w${C_RESET}${err_tag} ${C_RED}#${C_RESET} "
    else
        PS1="${C_CYAN}\h${C_RESET} ${C_DIM}>${C_RESET} ${C_GREEN}\u${C_RESET} ${C_BLUE}\w${C_RESET}${err_tag} ${sym_col}>${C_RESET} "
    fi
}

PROMPT_COMMAND=__kaaijkos_prompt
EOF

cat > /etc/shells << 'EOF'
/bin/sh
/bin/bash
/usr/bin/sh
/usr/bin/bash
EOF

echo "=== [2/4] Netwerk (DHCP + DNS via systemd-networkd & resolved) + SSH ==="
mkdir -p /etc/systemd/network
cat > /etc/systemd/network/10-ethernet.network << 'EOF'
[Match]
Name=en* eth*

[Network]
DHCP=yes

[DHCPv4]
UseHostname=false
EOF

ln -sfv /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable systemd-timesyncd.service
systemctl enable sshd.service
systemctl enable getty@tty1.service 2>/dev/null || true
systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true

echo "=== [3/4] Pure Upstream GRUB 2.14 installeren (Hybrid BIOS + UEFI!) ==="
ROOT_PART="${ROOT_PART:-$(findfs "UUID=${ROOT_UUID}")}"
DISK="/dev/$(lsblk -no pkname "$ROOT_PART")"
echo "KaaijkOS root-partitie: $ROOT_PART -> doelschijf: $DISK"
[ -b "$DISK" ] || { echo "FOUT: schijf $DISK niet gevonden!"; exit 1; }

mkdir -p /boot/efi
mountpoint -q /boot/efi || mount "UUID=${EFI_UUID}" /boot/efi

# Legacy SeaBIOS (i386-pc -> /dev/sdb1 BIOS boot partitie)
grub-install --target=i386-pc --recheck "$DISK"

# 64-bit UEFI (x86_64-efi -> universele BOOTX64.EFI + KaaijkOS entry)
grub-install --target=x86_64-efi \
             --efi-directory=/boot/efi \
             --bootloader-id=KaaijkOS \
             --removable \
             --no-nvram

grub-install --target=x86_64-efi \
             --efi-directory=/boot/efi \
             --bootloader-id=KaaijkOS \
             --no-nvram

echo "=== [4/4] Schone /boot/grub/grub.cfg genereren ==="
cat > /boot/grub/grub.cfg << EOF
set default=0
set timeout=5

insmod part_gpt
insmod ext2
insmod all_video

search --no-floppy --fs-uuid --set=root ${ROOT_UUID}

set menu_color_normal=light-cyan/black
set menu_color_highlight=black/light-cyan

menuentry "KaaijkOS 1.1 (Linux 7.3.6-kaaijkos)" {
    linux  /boot/vmlinuz-kaaijkos root=UUID=${ROOT_UUID} ro
    initrd /boot/initramfs-kaaijkos.img
}

menuentry "KaaijkOS 1.1 (Debug / Verbose Boot)" {
    linux  /boot/vmlinuz-kaaijkos root=UUID=${ROOT_UUID} ro loglevel=7
    initrd /boot/initramfs-kaaijkos.img
}
EOF

echo "=== FASE 4 KLAAR! Controle: ==="
ls -lh /boot/vmlinuz-kaaijkos /boot/initramfs-kaaijkos.img /boot/grub/grub.cfg
ls -lh /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/KaaijkOS/grubx64.efi
kpkg list | tail -n 1
