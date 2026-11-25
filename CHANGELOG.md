# Changelog

All notable releases of **KaaijkOS** are documented in this file.

## [1.1.0] — 2026-11-25

### Added
- **UEFI Secure Boot Support (`shim 16.1` + MOK + SBAT GRUB 2.14 + `systemd-sbsign`):**
  - Added [`tools/kaaijkos-sign-boot`](tools/kaaijkos-sign-boot) and [`recipes/fase5a_secureboot_mok.sh`](recipes/fase5a_secureboot_mok.sh) (`kaaijkos-shim 16.1` + `kaaijkos-secureboot 1.2`).
  - Uses BSD-licensed Debian `shim 16.1` + MokManager (`mmx64.efi`) with locally generated 4096-bit RSA KaaijkOS MOK keys (`/etc/kernel/kaaijkos-mok.*`) and SBAT metadata (`/etc/grub/sbat.csv`).
  - Signs both standalone GRUB 2.14 (`grubx64.efi`) and `vmlinuz-kaaijkos` via `/tmp` (avoiding FAT32 truncation) with byte-level PE certificate verification, tested live under Proxmox OVMF with "Pre-Enroll keys" (`Secure Boot: enabled`, `tainted = 0`).
- **TrueColor Live MOTD & System Dashboard (`kaaijkos-motd 1.1`):**
  - Added [`tools/motd`](tools/motd) and `/etc/profile.d/kaaijkos-motd.sh`: renders the KaaijkOS gradient `K` ASCII logo alongside live host, time, kernel + taint check, UEFI Secure Boot status, uptime/load, IP, live CPU % + temperature, RAM + Swap, `/` + `/boot/efi`, active/failed systemd services + `kpkg` count (+ Docker/Podman auto-detection), active sessions, and last login.
  - Shows once automatically on login and runs interactively on demand via `motd` or continuously every 1s with `motd live` / `motd -w`.
- **Security-Hardened Pre-Login Banner & Dynamic Shell Prompt:**
  - Updated `/etc/issue` ([`configs/etc/issue`](configs/etc/issue)) to show the colored KaaijkOS `K` logo, hostname, IP, and TTY cleanly without exposing internal kernel versions, resources, or service details before authentication, and clears double-render glitches when DHCP finishes asynchronously (`\x1b[H\x1b[2J`).
  - Updated [`configs/etc/bash.bashrc`](configs/etc/bash.bashrc) with dynamic `hostname > Root ~/path #` / `hostname > user ~/path >` prompt and automatic non-zero `[rc]` exit indicator.
- **Boot & Kernel Polish (`fase5c_polish_zram_regdb.sh`):**
  - Added [`tools/kaaijkos-zram`](tools/kaaijkos-zram) & `kaaijkos-zram.service` (`kaaijkos-zram 1.0`, zstd compressed RAM swap at 50% physical RAM, 512 MiB–4 GiB) before `systemd-oomd.service`.
  - Packaged upstream `wireless-regdb 2026.09.03` from kernel.org via `kpkg` (resolving `regulatory.db` warning `-2`).
  - Added `[DHCPv4] UseHostname=false` in `10-ethernet.network` and `/etc/modprobe.d/kaaijkos-blacklist.conf` (`floppy`, `pcspkr`).
- **Package Inventory:** 90 tracked `kpkg` packages ([manifest/packages-1.1.txt](manifest/packages-1.1.txt)).
- **Security Hardening:** Updated [`scripts/07_export_public_release.sh`](scripts/07_export_public_release.sh) to strip MOK private keys (`kaaijkos-mok.key`, `*.key`, `*.pem`) and `/etc/shadow-` in addition to kernel signing keys, host SSH keys, and `machine-id`.

### Verified Metrics (OVMF UEFI + Secure Boot ON)
- Boot time: **`3.553s`** (`1.578s` kernel + `1.975s` userspace), **`0` failed systemd units**, **`tainted = 0`**.

---

## [1.0.0] — 2026-11-25

- First complete, 100% independent x86_64 **KaaijkOS 1.0** From Scratch base (`85` tracked `kpkg` packages):
  - Pure upstream `Linux 7.3.6-kaaijkos` (5,668 zstd-compressed RSA-4096/SHA-512 signed modules, `0` taint)
  - Isolated Stage-1 cross-toolchain (`x86_64-kaaijkos-linux-gnu`) -> `glibc 2.44 (KaaijkOS 1.0)` -> `Binutils 2.47` -> `GCC 16.2.0 (KaaijkOS 1.0)`
  - `OpenSSL 4.0.1`, `Python 3.14.7`, `Meson 1.12.0`, `GRUB 2.14` (Hybrid BIOS `i386-pc` + UEFI `x86_64-efi`), `systemd 261.2-kaaijkos`, `D-Bus 1.16.2`, `cURL 8.21.0`, `OpenSSH 10.5p1`
  - Custom `kpkg 2.0` package manager and custom `kaaijkos-mkinitramfs 1.0` initramfs builder (0% Arch, 0% Deepin, 0% Nix)
  - Package inventory preserved in [manifest/packages-1.0.txt](manifest/packages-1.0.txt) and Git tag `v1.0.0`.
