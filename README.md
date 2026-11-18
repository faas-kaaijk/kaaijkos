# KaaijkOS 1.0

**KaaijkOS** is a minimal, independent `x86_64` Linux operating system built around a custom Linux kernel (`7.1.8-kaaijkos`), `systemd` + `systemd-boot` (Unified Kernel Image), `kpkg` for local source builds, and `kosapps` (powered by **Nix**) for user packages.

## Features
- **Custom Kernel**: Linux `7.1.8-kaaijkos` (`PREEMPT_DYNAMIC`, ZSTD initramfs, UKI `/EFI/KaaijkOS/kaaijkos-kernel.efi`)
- **Minimal Footprint**: ~2.8 GiB rootfs with only essential system services (`systemd`, `NetworkManager`, `sshd`, `ufw`, `nix-daemon`)
- **Interactive TUI Installer (`kaaijkos-install`)**: Full Ubuntu Server / Subiquity-style CLI installer supporting both **UEFI** (`systemd-boot` UKI) and **Legacy BIOS** (`GRUB`), guided & custom (`cfdisk`) storage layouts, DHCP/Static IPv4 & IPv6 network configuration, all system keymaps/locales/timezones, and GitHub SSH key import
- **Package Management**:
  - **`kosapps`** (`tools/kosapps`): User-friendly CLI wrapper around [Nix](https://nixos.org/) (`nixpkgs`, LGPL-2.1) providing access to >100,000 binary packages (`kosapps install <package>`)
  - **`kpkg`** (`tools/kpkg`): Source package manager for compiling and tracking local C/C++/CMake/Meson/Autotools software

## Building a Bootable Disk Image
~~~bash
git clone https://github.com/faas-kaaijk/kaaijkos.git
cd kaaijkos
sudo ./build-os.sh
~~~
To recompile the Linux `7.1.8-kaaijkos` kernel from `kernel.org` during the image build:
~~~bash
sudo BUILD_KERNEL=1 ./build-os.sh
~~~

## Repository Structure
- `build-os.sh` — Builds a bootable UEFI disk image (`KaaijkOS-1.0-x86_64.img`)
- `kernel/` — Kernel `.config` and `build-kernel.sh` (upstream Linux `7.1.8` from kernel.org)
- `assets/` — KaaijkOS boot splash (`splash-kaaijkos.bmp`), logos, and wallpaper
- `rootfs-configs/` — Core system & bootloader configurations (`/etc`, `/boot/loader`)
- `tools/` — KaaijkOS utilities (`kaaijkos-install`, `kosapps`, `kpkg`)
- `scripts/` — `setup-nix.sh`, `sync-from-system.sh`, and `export-base-rootfs.sh`
