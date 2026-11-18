# KaaijkOS 1.0

**KaaijkOS** is een minimaal, zelfstandig Linux-besturingssysteem (`x86_64`) gebouwd rondom een eigen gecompileerde Linux-kernel (`7.1.8-kaaijkos`), `systemd` + `systemd-boot` (Unified Kernel Image), `kpkg` voor eigen source-builds en `kosapps` (powered by **Nix**) voor gebruikerssoftware.

## Package Management
- **`kosapps`** (`tools/kosapps`): gebruiksvriendelijke CLI-wrapper rondom [Nix](https://nixos.org/) (`nixpkgs`, LGPL-2.1) om eenvoudig >100.000 pakketten te installeren (`kosapps install <pakket>`).
- **`kpkg`** (`tools/kpkg`): eigen source-package tool voor het compileren en beheren van lokale C/C++/CMake/Meson/Autotools projecten.

## Zelf KaaijkOS bouwen (bootable image)
~~~bash
git clone https://github.com/faas-kaaijk/kaaijkos.git
cd kaaijkos
sudo ./build-os.sh
~~~
Dit bouwt een bootable UEFI disk-image (`KaaijkOS-1.0-x86_64.img`) met `systemd-boot`, de KaaijkOS splash/logo's, systeemconfigs en tools.
Wil je ook de Linux `7.1.8-kaaijkos` kernel opnieuw vanaf `kernel.org` compileren tijdens de build? Run dan:
~~~bash
sudo BUILD_KERNEL=1 ./build-os.sh
~~~

## Structuur
- `build-os.sh` — Bouwt een complete bootable UEFI `.img`
- `kernel/` — Kernel `.config` en `build-kernel.sh` (upstream Linux `7.1.8` van kernel.org)
- `assets/` — KaaijkOS boot-splash (`splash-kaaijkos.bmp`), logo's en wallpaper
- `rootfs-configs/` — Systeem- & bootloader-configuraties (`/etc`, `/boot/loader`)
- `tools/` — Eigen KaaijkOS tools (`kpkg`, `kosapps`)
- `scripts/` — `setup-nix.sh`, `sync-from-system.sh`, en `export-base-rootfs.sh`
