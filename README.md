<p align="center">
  <img src="assets/kaaijkos-logo.png" alt="KaaijkOS Logo" width="140" />
</p>

<h1 align="center">KaaijkOS 1.1</h1>

<p align="center">
  <strong>A 100% independent, self-hosted x86_64 Linux distribution built from scratch.</strong><br/>
  0% Arch Linux · 0% Deepin · 0% Nix · Pure upstream Linux 7.3.6 + glibc 2.44 + GCC 16.2 + systemd 261.2 + GRUB 2.14 + UEFI Secure Boot (MOK)
</p>

<p align="center">
  <img alt="Release: v1.1.0" src="https://img.shields.io/badge/Version-1.1.0-00d4ff.svg" />
  <img alt="License: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" />
  <img alt="Architecture: x86_64" src="https://img.shields.io/badge/Arch-x86__64%20(2005--2026)-cyan.svg" />
  <img alt="Kernel: 7.3.6-kaaijkos" src="https://img.shields.io/badge/Kernel-7.3.6--kaaijkos-success.svg" />
  <img alt="Secure Boot: shim 16.1 + MOK" src="https://img.shields.io/badge/Secure%20Boot-MOK%20Enabled-success.svg" />
  <img alt="Packages: 90 via kpkg 2.0" src="https://img.shields.io/badge/Packages-90%20(kpkg%202.0)-informational.svg" />
</p>

> Looking for the original **KaaijkOS 1.0.0** baseline release? Check out Git tag [`v1.0.0`](../../tree/v1.0.0) and see [CHANGELOG.md](CHANGELOG.md) for everything new in **1.1.0**.

---

## Overview

**KaaijkOS 1.1** is an independent, reproducible x86_64 Linux operating system compiled completely from upstream source code (following Linux From Scratch 13.1-systemd methodology) and tracked end-to-end by its own package manager (**`kpkg 2.0`**) and custom initramfs builder (**`kaaijkos-mkinitramfs`**).

### Key Characteristics
- **100% Independent Stack:** Zero borrowed rootfs tarballs, zero third-party distro package managers, zero `/nix/store`.
- **Universal x86_64 Compatibility (2005–2026):** Compiled for baseline `x86-64` (never `-march=native`), with runtime FAT CPU dispatch in GMP (`--enable-fat`), generic `libffi`, and 5,668 signed kernel modules covering Proxmox/KVM/VirtIO, VMware, NVMe, SATA/AHCI, USB, and desktop/server NICs.
- **Zero Kernel Taint (`tainted = 0`):** Pure upstream `Linux 7.3.6-kaaijkos` signed with a locally generated 4096-bit RSA + SHA-512 X.509 module signing key.
- **Hybrid BIOS + UEFI + Secure Boot (MOK):** Pure upstream **GRUB 2.14** supporting **Legacy BIOS (`i386-pc`)**, standard **64-bit UEFI**, and **UEFI Secure Boot ("Pre-Enroll keys" ON)** via BSD-licensed Debian `shim 16.1` + MokManager (`mmx64.efi`) and `kaaijkos-sign-boot` (powered by `systemd-sbsign` + SBAT).
- **Fast, Lean & Polished:** Verified UEFI Secure Boot cold boot in **`3.553s`** (`1.578s` kernel + `1.975s` userspace), **0 failed systemd units**, **~255 MiB RAM** idle footprint, automatic **zstd ZRAM swap** (`kaaijkos-zram`), TrueColor **live `motd` dashboard**, security-hardened `K`-logo login screen (`/etc/issue`), dynamic prompt (`hostname > Root ~/path #`), **`systemd-networkd`**, **`systemd-resolved`**, **`cURL 8.21.0`**, and **`OpenSSH 10.5p1`**.

---

## Verified Component Stack (KaaijkOS 1.1)

| Component | Version / Identity | Notes |
|---|---|---|
| **Kernel** | `Linux 7.3.6-kaaijkos` (`#1 SMP PREEMPT_DYNAMIC`) | Zstd-compressed kernel & 5,668 signed modules, `tainted = 0` |
| **C Library** | `glibc 2.44` (`--with-pkgversion="KaaijkOS 1.0"`) | Strong SSP, NL/BE/EN/DE/FR + `C.UTF-8` locales, `tzdata2026c` (`Europe/Amsterdam`) |
| **Toolchain** | `GCC 16.2.0` & `Binutils 2.47` (`KaaijkOS 1.0`) | C/C++, `--enable-targets=all` (for 32-bit GRUB BIOS support) |
| **Init & Services** | `systemd 261 (261.2-kaaijkos)` + `D-Bus 1.16.2` | Dutch NTP defaults, `networkd`, `resolved`, `timesyncd`, `systemd-sbsign` |
| **Bootloader & Secure Boot** | `GRUB 2.14` + `shim 16.1` + `kaaijkos-secureboot 1.2` | Dual `i386-pc` (BIOS) + `x86_64-efi` (SBAT + PE-signed via local MOK) |
| **Initramfs** | `kaaijkos-mkinitramfs 1.0` | Custom Bash+Python SVR4 cpio/zstd builder (473 universal modules + chroot self-test) |
| **Package Manager** | `kpkg 2.0` | Tracks all **90 packages** in `/var/lib/kpkg/` & `/var/cache/kpkg/*.kpkg.tar.zst` |
| **UX & Polish** | `kaaijkos-motd 1.1`, `kaaijkos-zram 1.0`, `wireless-regdb 2026.09.03` | TrueColor live MOTD (`motd` / `motd live`), zstd ZRAM swap, dynamic shell prompt |
| **Crypto & Networking** | `OpenSSL 4.0.1`, `Python 3.14.7`, `cURL 8.21.0`, `OpenSSH 10.5p1` | Mozilla CAs, DHCP + DNS + HTTPS + SSH enabled on boot |

The complete package inventories are listed in [manifest/packages-1.1.txt](manifest/packages-1.1.txt) (**90 packages**) and [manifest/packages-1.0.txt](manifest/packages-1.0.txt) (**85 packages**).

---

## Build KaaijkOS 1.1 From Scratch

> **Host Requirements:** Any modern x86_64 Linux build host with `bash`, `gcc`, `g++`, `binutils`, `make`, `bison`, `m4`, `patch`, `texinfo`, `python3`, `perl`, `curl`, `sfdisk`, `dosfstools`, `e2fsprogs`, `openssl`, `binutils` (`ar`), `cpio`, `zstd`, and at least **25 GiB free space** on a dedicated target disk (recommended: **40–60 GiB**, plus >= 4 GiB RAM+swap for compiling GCC).

### Phase 0 — Build the Pure Upstream `7.3.6-kaaijkos` Kernel (on Build Host)
Generates your own X.509 signing key (`/etc/kernel/kaaijkos-signing-key.pem`) and compiles Linux `7.3.6-kaaijkos`:

```bash
git clone https://github.com/faas-kaaijk/kaaijkos.git
cd kaaijkos
chmod +x tools/* scripts/*.sh recipes/*.sh
sudo ./tools/kaaijkos-kernel-build --version 7.3.6 --mode universal
```

*(Optionally copy `kernel/config-7.3.6-kaaijkos` as your baseline `.config` if you want the exact verified universal configuration.)*

### Phase 1 — Prepare Target Disk & Fetch All Verified Sources
Partition a dedicated target disk (example: `/dev/sdb` — **wipes the target disk!**) with Hybrid GPT (2 MiB BIOS Boot + 512 MiB FAT32 EFI + ext4 root) and download all upstream archives (90 MD5-verified LFS 13.1 sources/patches + Linux 7.3.6 + networking/boot/Secure Boot/regdb extras):

```bash
sudo ./scripts/00_prepare_disk.sh /dev/sdb
sudo ./scripts/01_fetch_sources.sh
```

`01_fetch_sources.sh` automatically verifies MD5 checksums, falls back to the OSUOSL LFS 13.1 mirror if SourceForge rejects a client, and copies `recipes/` and `tools/` into `/mnt/kaaijkos/work/`.

### Phase 2 — Build Isolated Cross-Toolchain & Stage-1 Chroot (`x86_64-kaaijkos-linux-gnu`)
Runs completely isolated as non-root `kosbuild` (`env -i`), then switches into `/mnt/kaaijkos` chroot, builds temporary bootstrap tools, removes `/tools`, and saves a clean Stage-1 checkpoint:

```bash
sudo ./scripts/02_stage1_toolchain.sh
sudo ./scripts/03_stage1_chroot_tools.sh
```

### Phase 3 — Stage Host Kernel & Build All Core Packages via `kpkg 2.0`
First, from the **host**, stage your newly compiled kernel, signed modules, and fresh X.509 signing key so `ronde10` can package `linux-kaaijkos 7.3.6` cleanly with `kpkg`:

```bash
KSTAGE=/mnt/kaaijkos/work/stage/linux-kaaijkos
sudo mkdir -p "$KSTAGE"/{boot,usr/lib/modules,etc/kernel,usr/local/bin}
sudo cp -a /boot/vmlinuz-kaaijkos "$KSTAGE/boot/"
[ -f /boot/config-7.3.6-kaaijkos ] && sudo cp -a /boot/config-7.3.6-kaaijkos "$KSTAGE/boot/"
sudo cp -a /usr/lib/modules/7.3.6-kaaijkos "$KSTAGE/usr/lib/modules/"
sudo rm -f "$KSTAGE/usr/lib/modules/7.3.6-kaaijkos"/{build,source}
sudo cp -a /etc/kernel/kaaijkos-signing-key.pem "$KSTAGE/etc/kernel/"
sudo chmod 600 "$KSTAGE/etc/kernel/kaaijkos-signing-key.pem"
sudo cp -a ./tools/kaaijkos-kernel-build "$KSTAGE/usr/local/bin/kaaijkos-kernel-build"
```

Now enter the isolated **KaaijkOS chroot** and build Rounds 1–10:

```bash
sudo ./scripts/04_enter_chroot.sh
bash /work/recipes/06_build_all_stage2.sh
```

### Phase 4 — Generate Custom Initramfs, System Config & Hybrid Bootloader
Still inside `(KaaijkOS-chroot)`:

```bash
bash /work/recipes/fase4a_initramfs.sh
bash /work/recipes/fase4b_boot.sh
passwd root
```

### Phase 5 — Secure Boot (MOK), Live MOTD, K-Login & ZRAM Polish (Optional / Included in 1.1)
Still inside `(KaaijkOS-chroot)` (or after first boot):

```bash
bash /work/recipes/fase5a_secureboot_mok.sh   # Debian shim 16.1 + local MOK signing + SBAT GRUB
bash /work/recipes/fase5b_motd_branding.sh    # TrueColor live MOTD + K-logo /etc/issue + dynamic prompt
bash /work/recipes/fase5c_polish_zram_regdb.sh # ZRAM zstd swap + wireless-regdb + DHCP UseHostname=false
exit
```

Then cleanly unmount from the host:

```bash
sudo ./scripts/05_unmount_chroot.sh
```

### Phase 6 — Boot Standalone & Verify
Attach the target disk to any x86_64 PC or VM (**Legacy BIOS**, **UEFI**, or **UEFI with Secure Boot / Pre-Enroll keys ON**):
- **With Secure Boot ON (first time on a new PC/VM):** `shim 16.1` automatically opens the blue **MokManager** screen (`Perform MOK management`). Choose **`Enroll key from disk`** -> **`EFI`** -> **`BOOT`** -> **`kaaijkos-mok.cer`** -> **`Continue`** -> **`Yes`** -> **`Reboot`**. Subsequent boots are instant!

Verify inside **KaaijkOS 1.1**:

```bash
uname -a                          # Linux KaaijkOS 7.3.6-kaaijkos ...
cat /proc/sys/kernel/tainted      # 0
bootctl status | grep Secure      # Secure Boot: enabled (user)
systemctl --version               # systemd 261 (261.2-kaaijkos)
kpkg list                         # 90 KaaijkOS pakketten
motd                              # Live MOTD (or 'motd live' for 1s dashboard)
```

---

## Tool Reference (`kpkg`, `motd`, `kaaijkos-sign-boot`)

```bash
# Package management (kpkg 2.0)
kpkg list                                   # List installed packages
kpkg info / kpkg files / kpkg owns <path>   # Inspect package metadata & file ownership
kpkg build <src_dir> <name> <version>       # Auto-build CMake/Meson/Autotools/Make -> .kpkg.tar.zst
kpkg pack <stage_dir> <name> <version>      # Pack DESTDIR tree -> .kpkg.tar.zst
kpkg install /var/cache/kpkg/<file>.tar.zst # Install & track package safely
kpkg remove <name>                          # Cleanly remove package

# Live MOTD Dashboard
motd                                        # Show live status once
motd live                                   # Live 1s refreshing dashboard (also: motd -w)

# UEFI Secure Boot Re-Signing (after kernel or GRUB updates)
sudo kaaijkos-sign-boot                     # Rebuild SBAT GRUB, sign GRUB & vmlinuz via /tmp, verify PE headers
```

---

## Security & Public Release Packaging

Never publish raw system backups directly — a live backup contains your private kernel X.509 signing key (`/etc/kernel/kaaijkos-signing-key.pem`), local Secure Boot MOK private key (`/etc/kernel/kaaijkos-mok.key`), `/etc/shadow`, SSH host keys, and `/etc/machine-id`.

Use the included sanitizer script on a running KaaijkOS system to generate clean, audited public release tarballs:

```bash
sudo ./scripts/07_export_public_release.sh
```

This creates `kaaijkos-1.1-rootfs-public.tar.zst` (with `root` locked as `!` and zero private keys), `kaaijkos-1.1-kpkg-repo-public.tar` (with `linux-kaaijkos` repacked without `.pem`/`.key` files), and `SHA256SUMS`, verified by an automated secret-leak check. Anyone deploying a public rootfs archive should set a root password and machine ID before first boot:

```bash
chroot /mnt/kaaijkos passwd root
chroot /mnt/kaaijkos systemd-machine-id-setup
```

---

## Repository Layout

```text
kaaijkos/
├── assets/                  # KaaijkOS logos, GRUB splash bitmap, and wallpaper
├── configs/                 # Templates (os-release, K-logo issue, bash.bashrc, networkd, GRUB, SBAT, systemd)
├── kernel/                  # Universal Linux 7.3.6-kaaijkos kernel .config (x86_64 2005–2026)
├── manifest/                # Upstream source manifests + v1.0 (85) & v1.1 (90) package lists
├── recipes/                 # Fase 3 rounds (01–10), Fase 4 (initramfs/GRUB), Fase 5 (Secure Boot/MOTD/ZRAM)
├── scripts/                 # Disk setup, source fetcher, Stage-1 toolchain, chroot helpers & release exporter
├── tools/                   # kpkg (v2.0), kaaijkos-mkinitramfs, kaaijkos-kernel-build, kaaijkos-sign-boot, motd, kaaijkos-zram
├── CHANGELOG.md             # Release notes for v1.0.0 and v1.1.0
├── LICENSE                  # GNU General Public License v3.0 (GPL-3.0)
└── README.md
```

---

## Roadmap

- [x] **KaaijkOS 1.0.0 Core:** Pure `7.3.6-kaaijkos` kernel, Stage-1 cross-toolchain, 85 `kpkg`-tracked packages, `systemd 261.2-kaaijkos`, custom `kaaijkos-mkinitramfs`, Dual BIOS/UEFI `GRUB 2.14`, OpenSSH & cURL.
- [x] **KaaijkOS 1.1.0 Boot & UX:** UEFI Secure Boot (`shim 16.1` + MOK + SBAT GRUB + `systemd-sbsign`), TrueColor live `motd` / `motd live`, security-hardened K-logo `/etc/issue`, dynamic prompt, zstd ZRAM swap & `wireless-regdb`.
- [ ] **Live-ISO & Installer (`kaaijkos-install` v2):** Extend `kaaijkos-mkinitramfs` for SquashFS + OverlayFS and build a hybrid BIOS/UEFI + MOK Live-ISO.
- [ ] **Wayland Desktop GUI:** Custom flicker-free Wayland compositor with `ext-session-lock-v1` (eliminating display-manager mode-set flicker).
- [ ] **Remote `kpkg` Sync & ARM64 (`aarch64`) Port:** Port the exact toolchain/recipe pipeline to ARM64 hardware.

---

## License

All original KaaijkOS build scripts, recipes, tooling (`kpkg`, `kaaijkos-mkinitramfs`, `kaaijkos-kernel-build`, `kaaijkos-sign-boot`, `motd`, `kaaijkos-zram`), and configuration files are licensed under the **GNU General Public License v3.0 (GPL-3.0)** — see [LICENSE](LICENSE). Binary UEFI `shim 16.1` (`shimx64.efi` / `mmx64.efi`) used in `fase5a_secureboot_mok.sh` is redistributed under its upstream BSD license; all upstream software packages retain their respective open-source licenses.
