# KaaijkOS 1.0

**KaaijkOS 1.0** is a minimal, fast, independent `x86_64` Linux operating system powered by a custom **Linux 7.1.8-kaaijkos** kernel, featuring a full C/C++ build toolchain, a source package manager (`kpkg`), a Nix-backed binary application manager (`kosapps`), and an interactive Ubuntu Server-style TUI installer (`kaaijkos-install`).

---

## Features

- **Custom Kernel**: `7.1.8-kaaijkos` (`PREEMPT_DYNAMIC`, `x86_64`) with custom Unified Kernel Image (UKI) boot splash.
- **Minimal Footprint**: Clean CLI base (~2.8 GiB installed, ~500 MiB RAM usage, 0 failed systemd services).
- **Universal Boot Support**: Hybrid **UEFI** (`systemd-boot` + UKI) and **Legacy BIOS** (`GRUB i386-pc`) support for cloud/dedicated servers (e.g. Hetzner, KVM/QEMU, Proxmox), modern PCs/laptops, and VMware/VirtualBox.
- **Interactive TUI Installer (`kaaijkos-install`)**:
  - Full system keymap, locale, and timezone selection.
  - Per-interface network configuration (DHCP, Static IPv4/IPv6, DNS, Wi-Fi via `nmcli`).
  - Guided whole-disk partitioning or Custom interactive layout (`cfdisk`, `/`, `/boot`, `/home`, swap/ZRAM).
  - Hostname, `root` password, optional `sudo` user, OpenSSH toggle, and GitHub SSH key import.
- **Package Management**:
  - `kosapps` — install, remove, search, and upgrade binary applications via Nix (`kosapps install htop git neovim`).
  - `kpkg` — build and manage native source packages (`.tar.zst`).

---

## Quick Start

### 1. Build a Bootable Disk Image (`.img`)

~~~bash
git clone https://github.com/faas-kaaijk/kaaijkos.git
cd kaaijkos
sudo ./build-os.sh
~~~

`build-os.sh` automatically downloads the sanitized base rootfs from GitHub Releases, prompts you to set your own `root` password, and outputs a bootable `KaaijkOS-1.0-x86_64.img` disk image.

### 2. Build a Hybrid UEFI + Legacy BIOS Live Installer ISO (`.iso`)

~~~bash
git clone https://github.com/faas-kaaijk/kaaijkos.git
cd kaaijkos
sudo ./build-iso.sh
~~~

This generates `KaaijkOS-1.0-x86_64.iso`. Booting from the ISO (via virtual CD-ROM or USB flash drive) automatically launches `kaaijkos-install` on `tty1`.

### 3. Test the Installer UI Safely (Dry-Run)

~~~bash
sudo kaaijkos-install --dry-run
~~~

---

## Repository Layout

- `build-os.sh` — Builds a bootable GPT/UEFI disk image (`KaaijkOS-1.0-x86_64.img`).
- `build-iso.sh` — Builds a hybrid UEFI + Legacy BIOS Live & Installer ISO (`KaaijkOS-1.0-x86_64.iso`).
- `tools/` — Core system tools (`kaaijkos-install`, `kosapps`, `kpkg`).
- `kernel/` — Custom `7.1.8-kaaijkos` kernel configuration and build script.
- `rootfs-configs/` — System configuration files, branding, and `kaaijkos_live` initcpio hook.
- `assets/` — KaaijkOS boot splash (`splash-kaaijkos.bmp`), logos, and wallpaper.
- `scripts/` — Helper scripts (`export-base-rootfs.sh`, `setup-nix.sh`, `sync-from-system.sh`).
