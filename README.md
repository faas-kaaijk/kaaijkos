# KaaijkOS 1.0

**KaaijkOS** is een minimaal, zelfstandig Linux-besturingssysteem (`x86_64`) gebouwd rondom een eigen gecompileerde Linux-kernel (`7.1.8-kaaijkos`), `systemd` + `systemd-boot` (Unified Kernel Image), `kpkg` voor eigen source-builds en **Nix** voor gebruikerssoftware.

## Kenmerken
- **Kernel**: Custom Linux `7.1.8-kaaijkos` (`PREEMPT_DYNAMIC`, ZSTD initramfs, UKI `/EFI/KaaijkOS/kaaijkos-kernel.efi`)
- **Minimale Footprint**: ~2.8 GB rootfs, alleen essentiële system services (`systemd`, `NetworkManager`, `sshd`, `ufw`, `nix-daemon`)
- **Eigen Source Packaging (`kpkg`)**: `tools/kpkg` voor het compileren en beheren van eigen C/C++/CMake/Meson/Autotools software
- **Nix**: Volledige toegang tot >100.000 distro-onafhankelijke packages

## Structuur
- `kernel/` — Kernel `.config` en `build-kernel.sh` (upstream Linux `7.1.8` van kernel.org)
- `rootfs-configs/` — Systeem- & bootloader-configuraties (`/etc`, `/boot/loader`)
- `tools/` — Eigen KaaijkOS tools (`kpkg`)
- `scripts/` — Setup- en synchronisatiescripts
