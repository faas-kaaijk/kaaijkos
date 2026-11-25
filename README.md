<p align="center">
  <img src="assets/kaaijkos-logo.png" alt="KaaijkOS Logo" width="140" />
</p>

<h1 align="center">KaaijkOS 1.0</h1>

<p align="center">
  <strong>A 100% independent, self-hosted x86_64 Linux distribution built from scratch.</strong><br/>
  0% Arch Linux · 0% Deepin · 0% Nix · Pure upstream Linux 7.3.6 + glibc 2.44 + GCC 16.2 + systemd 261.2 + GRUB 2.14
</p>

<p align="center">
  <img alt="License: GPL-3.0" src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" />
  <img alt="Architecture: x86_64" src="https://img.shields.io/badge/Arch-x86__64%20(2005--2026)-cyan.svg" />
  <img alt="Kernel: 7.3.6-kaaijkos" src="https://img.shields.io/badge/Kernel-7.3.6--kaaijkos-success.svg" />
  <img alt="Packages: 85 via kpkg 2.0" src="https://img.shields.io/badge/Packages-85%20(kpkg%202.0)-informational.svg" />
</p>

---

## Overview

**KaaijkOS 1.0** is an independent, reproducible x86_64 Linux operating system compiled completely from upstream source code (following Linux From Scratch 13.1-systemd methodology) and tracked end-to-end by its own package manager (**`kpkg 2.0`**) and custom initramfs builder (**`kaaijkos-mkinitramfs`**).

### Key Characteristics
- **100% Independent Stack:** Zero borrowed rootfs tarballs, zero third-party distro package managers, zero `/nix/store`.
- **Universal x86_64 Compatibility (2005–2026):** Compiled for baseline `x86-64` (never `-march=native`), with runtime FAT CPU dispatch in GMP (`--enable-fat`), generic `libffi`, and 5,668 signed kernel modules covering Proxmox/KVM/VirtIO, VMware, NVMe, SATA/AHCI, USB, and desktop/server NICs.
- **Zero Kernel Taint (`tainted = 0`):** Pure upstream `Linux 7.3.6-kaaijkos` signed with a locally generated 4096-bit RSA + SHA-512 X.509 module signing key.
- **Hybrid Bootloader Out-of-the-Box:** Pure upstream **GRUB 2.14** supporting both **Legacy BIOS (`i386-pc`)** and **64-bit UEFI (`x86_64-efi`, including fallback `BOOTX64.EFI`)** on the same GPT disk.
- **Fast & Lean:** Verified cold boot on SeaBIOS VM in **`4.566s`** (`1.632s` kernel + `2.933s` userspace), **0 failed systemd units**, **~253 MiB RAM** idle footprint, with working **`systemd-networkd`**, **`systemd-resolved`**, **`cURL 8.21.0`** (OpenSSL 4.0.1 + Mozilla CAs), and **`OpenSSH 10.5p1`**.

---

## Verified Component Stack (KaaijkOS 1.0)

| Component | Version / Identity | Notes |
|---|---|---|
| **Kernel** | `Linux 7.3.6-kaaijkos` (`#1 SMP PREEMPT_DYNAMIC`) | Zstd-compressed kernel & 5,668 signed modules, `tainted = 0` |
| **C Library** | `glibc 2.44` (`--with-pkgversion="KaaijkOS 1.0"`) | Strong SSP, NL/BE/EN/DE/FR + `C.UTF-8` locales, `tzdata2026c` (`Europe/Amsterdam`) |
| **Toolchain** | `GCC 16.2.0` & `Binutils 2.47` (`KaaijkOS 1.0`) | C/C++, `--enable-targets=all` (for 32-bit GRUB BIOS support) |
| **Init & Services** | `systemd 261 (261.2-kaaijkos)` + `D-Bus 1.16.2` | Dutch NTP defaults, `networkd`, `resolved`, `timesyncd`, `udev` |
| **Bootloader** | `GRUB 2.14` | Dual `i386-pc` (MBR/GPT BIOS boot) + `x86_64-efi` (ESP) |
| **Initramfs** | `kaaijkos-mkinitramfs 1.0` | Custom Bash+Python SVR4 cpio/zstd builder (473 universal modules + chroot self-test) |
| **Package Manager** | `kpkg 2.0` | Tracks all **85 core packages** in `/var/lib/kpkg/` & `/var/cache/kpkg/*.kpkg.tar.zst` |
| **Crypto & Scripting** | `OpenSSL 4.0.1`, `Python 3.14.7`, `Perl 5.44.0`, `Meson 1.12.0` | Patched for OpenSSL 4.0 compatibility |
| **Networking & Tools** | `OpenSSH 10.5p1`, `cURL 8.21.0`, `iproute2 7.1.0`, `e2fsprogs 1.47.4`, `dosfstools 4.2`, `Vim 9.2`, `Nano 9.2` | DHCP + DNS + HTTPS + SSH enabled on first boot |

The complete 85-package inventory is listed in [manifest/packages-1.0.txt](manifest/packages-1.0.txt).

---

## Build KaaijkOS 1.0 From Scratch

> **Host Requirements:** Any modern x86_64 Linux build host with `bash`, `gcc`, `g++`, `binutils`, `make`, `bison`, `m4`, `patch`, `texinfo`, `python3`, `perl`, `curl`, `sfdisk`, `dosfstools`, `e2fsprogs`, `openssl`, `cpio`, `zstd`, and at least **25 GiB free space** on a dedicated target disk (recommended: **40–60 GiB**, plus >= 4 GiB RAM+swap for compiling GCC).

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
Partition a dedicated target disk (example: `/dev/sdb` — **wipes the target disk!**) with Hybrid GPT (2 MiB BIOS Boot + 512 MiB FAT32 EFI + ext4 root) and download all 96 upstream archives (90 MD5-verified LFS 13.1 sources/patches + Linux 7.3.6 + 5 networking/boot extras):

```bash
sudo ./scripts/00_prepare_disk.sh /dev/sdb
sudo ./scripts/01_fetch_sources.sh
```

`01_fetch_sources.sh` automatically verifies MD5 checksums, falls back to the OSUOSL LFS 13.1 mirror if SourceForge rejects a client, and copies `recipes/` and `tools/` into `/mnt/kaaijkos/work/`.

### Phase 2 — Build Isolated Cross-Toolchain & Stage-1 Chroot (`x86_64-kaaijkos-linux-gnu`)
Runs completely isolated as non-root `kosbuild` (`env -i`), then switches into `/mnt/kaaijkos` chroot, builds the temporary Python/Perl/Gettext/Bison/Util-linux tools, removes `/tools`, and saves a clean Stage-1 checkpoint:

```bash
sudo ./scripts/02_stage1_toolchain.sh
sudo ./scripts/03_stage1_chroot_tools.sh
```

### Phase 3 — Stage Host Kernel & Build All 85 Final Packages via `kpkg 2.0`
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

*(Note: when running `./tools/kaaijkos-kernel-build` natively inside a booted KaaijkOS 1.0 system later, pair it with `kaaijkos-mkinitramfs` for regenerating `/boot/initramfs-kaaijkos.img`.)*

Now enter the isolated **KaaijkOS chroot**:

```bash
sudo ./scripts/04_enter_chroot.sh
```

Inside `(KaaijkOS-chroot)`, either run all 10 build rounds sequentially:

```bash
bash /work/recipes/06_build_all_stage2.sh
```

Or run them individually round-by-round (`ronde01` through `ronde10` in `/work/recipes/`) to inspect each step:

1. `ronde01_glibc_base.sh` — `iana-etc`, `man-pages`, final `glibc 2.44 (KaaijkOS 1.0)`, locales, `tzdata2026c`, `/etc/nsswitch.conf`
2. `ronde02_compression_kpkg.sh` — `zlib`, `bzip2`, `xz`, `lz4`, `zstd`, and installs `kpkg 2.0`
3. `ronde03_build_essentials.sh` — `file`, `readline`, `pcre2`, `m4`, `bc`, `flex`, `ninja`, `pkgconf`
4. `ronde04_binutils_security.sh` — final `binutils 2.47 (KaaijkOS 1.0)`, `gmp` (`--enable-fat`), `mpfr`, `mpc`, `attr`, `acl`, `libcap`, `libxcrypt`, `shadow` (`YESCRYPT`)
5. `ronde05_gawk_gcc.sh` — builds MPFR-linked `gawk 5.4.1` first (preventing the upstream `0Wabsolute-value` codegen bug), then final `GCC 16.2.0 (KaaijkOS 1.0)`
6. `ronde06_cli_libs.sh` — `ncurses 6.6` (wide + ABI5), `sed`, `psmisc`, `gettext`, `bison`, `grep`, `bash`, `libtool`, `gdbm`, `gperf`, `expat`, `inetutils`, `less`
7. `ronde07_openssl_python_meson.sh` — `perl`, `autoconf`, `automake`, `OpenSSL 4.0.1`, `libelf`, `libffi` (`x86-64`), `sqlite`, `mpdecimal`, `Python 3.14.7`, `Meson 1.12.0`, `Jinja2`
8. `ronde08_core_grub.sh` — `kmod`, `coreutils`, `diffutils`, `findutils`, `groff`, pure upstream **`GRUB 2.14`** (`i386-pc` + `x86_64-efi`), `gzip`, `iproute2`, `kbd`, `libpipeline`, `make`, `patch`, `tar`, `texinfo`, `vim`
9. `ronde09_systemd_core.sh` — **`systemd 261.2-kaaijkos`**, `dbus`, `man-db`, `procps-ng`, final `util-linux`, `e2fsprogs`
10. `ronde10_kernel_net_ssh.sh` — packages `linux-kaaijkos 7.3.6`, Mozilla CA certs, `cURL 8.21.0`, `OpenSSH 10.5p1` (`sshd.service`), `dosfstools`, `nano`

### Phase 4 — Generate Custom Initramfs, System Config & Dual BIOS+UEFI GRUB
Still inside `(KaaijkOS-chroot)`:

```bash
bash /work/recipes/fase4a_initramfs.sh
bash /work/recipes/fase4b_boot.sh
passwd root
exit
```

Then cleanly unmount from the host:

```bash
sudo ./scripts/05_unmount_chroot.sh
```

### Phase 5 — Boot Standalone & Verify
Detach or attach the target disk to a VM (SeaBIOS or UEFI with Secure Boot disabled) or bare-metal PC and boot directly into **KaaijkOS 1.0**:

```bash
uname -a                          # Linux KaaijkOS 7.3.6-kaaijkos ...
cat /proc/sys/kernel/tainted      # 0
systemctl --version               # systemd 261 (261.2-kaaijkos)
gcc --version                     # gcc (KaaijkOS 1.0) 16.2.0
ld --version                      # GNU ld (KaaijkOS 1.0) 2.47.20260726
ldd --version                     # ldd (KaaijkOS 1.0) 2.44
kpkg list                         # 85 KaaijkOS pakketten
```

---

## `kpkg 2.0` Package Manager Usage

```bash
kpkg list                                   # List all installed KaaijkOS packages
kpkg info <name>                            # Show metadata (version, arch, install date)
kpkg files <name>                           # List every file owned by a package
kpkg owns /usr/bin/systemctl                # Find which package owns a file
kpkg build <src_dir> <name> <version>       # Auto-build CMake/Meson/Autotools/Make -> .kpkg.tar.zst
kpkg pack <stage_dir> <name> <version>      # Pack a DESTDIR staging tree into .kpkg.tar.zst
kpkg install /var/cache/kpkg/<file>.tar.zst # Install & track package safely
kpkg remove <name>                          # Cleanly remove package (protects shared & core files)
```

---

## Security & Public Release Packaging

Never publish raw system backups directly — a live backup contains your private kernel X.509 signing key (`/etc/kernel/kaaijkos-signing-key.pem`), `/etc/shadow`, SSH host keys, and `/etc/machine-id`.

Use the included sanitizer script on a running KaaijkOS 1.0 system to generate clean, audited public release tarballs:

```bash
sudo ./scripts/07_export_public_release.sh
```

This creates `kaaijkos-1.0-rootfs-public.tar.zst` (with `root` locked as `!` and no private keys), `kaaijkos-1.0-kpkg-repo-public.tar` (with `linux-kaaijkos` repacked without the private PEM key), and `SHA256SUMS`, and runs an automated secret-leak check. Anyone deploying a public rootfs archive should set a root password and machine ID before first boot:

```bash
chroot /mnt/kaaijkos passwd root
chroot /mnt/kaaijkos systemd-machine-id-setup
```

---

## Repository Layout

```text
kaaijkos/
├── assets/                  # KaaijkOS logos, GRUB splash bitmap, and wallpaper
├── configs/                 # System configuration templates (os-release, issue, networkd, GRUB, systemd)
├── kernel/                  # Universal Linux 7.3.6-kaaijkos kernel .config (x86_64 2005–2026)
├── manifest/                # Upstream source manifests + exact 85-package KaaijkOS 1.0 list
├── recipes/                 # All 10 Fase-3 kpkg package rounds + Fase-4 initramfs & boot scripts
├── scripts/                 # Disk setup, source fetcher, Stage-1 toolchain, chroot helpers & release exporter
├── tools/                   # kpkg (v2.0), kaaijkos-mkinitramfs, and kaaijkos-kernel-build
├── LICENSE                  # GNU General Public License v3.0 (GPL-3.0)
└── README.md
```

---

## Roadmap

- [x] **KaaijkOS 1.0 Core:** Pure `7.3.6-kaaijkos` kernel, Stage-1 cross-toolchain, 85 `kpkg`-tracked packages, `systemd 261.2-kaaijkos`, custom `kaaijkos-mkinitramfs`, Dual BIOS/UEFI `GRUB 2.14`, OpenSSH & cURL.
- [ ] **Live-ISO & Installer (`kaaijkos-install` v2):** Extend `kaaijkos-mkinitramfs` for SquashFS + OverlayFS and build a hybrid BIOS/UEFI Live-ISO.
- [ ] **Wayland Desktop GUI:** Custom flicker-free Wayland compositor with `ext-session-lock-v1` (eliminating display-manager mode-set flicker).
- [ ] **Remote `kpkg` Sync & ARM64 (`aarch64`) Port:** Port the exact toolchain/recipe pipeline to ARM64 hardware.

---

## License

All original KaaijkOS build scripts, recipes, tooling (`kpkg`, `kaaijkos-mkinitramfs`, `kaaijkos-kernel-build`), and configuration files are licensed under the **GNU General Public License v3.0 (GPL-3.0)** — see [LICENSE](LICENSE). Upstream software packages retain their respective upstream open-source licenses.
