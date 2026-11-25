#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS From Scratch - Stap 2c: Schone Chroot + Tijdelijke Chroot-Tools
# - Zet rechten naar root:root, mount /dev /proc /sys /run veilig
# - Bouwt binnen 100% geïsoleerde KaaijkOS chroot: gettext, bison, perl, zlib,
#   mpdecimal, Python 3.14.7, texinfo, util-linux
# - Ruimt /tools op en maakt een herstel-checkpoint (.tar.zst)
# ==============================================================================
set -euo pipefail

KOS="/mnt/kaaijkos"

if [ "$(id -u)" -ne 0 ]; then
    echo "FOUT: Draai dit script als root." >&2
    exit 1
fi
if ! mountpoint -q "$KOS"; then
    echo "FOUT: $KOS is niet gemount!" >&2
    exit 1
fi
if [ ! -f "${KOS}/work/stamps/stage1-22-gcc-pass2.done" ]; then
    echo "FOUT: 02_stage1_toolchain.sh is nog niet volledig afgerond!" >&2
    exit 1
fi

echo "=== 1. Rechten terugzetten naar root:root ==="
chown -h root:root "$KOS"/{bin,lib,sbin}
chown -R root:root "$KOS"/{usr,var,etc,lib64,tools} "$KOS"/work/{build,logs,stamps}

echo "=== 2. Virtuele kernel-bestandssystemen veilig koppelen ==="
mkdir -pv "$KOS"/{dev,proc,sys,run}
mountpoint -q "$KOS/dev"     || mount -v --bind /dev "$KOS/dev"
mountpoint -q "$KOS/dev/pts" || mount -vt devpts devpts -o gid=5,mode=0620 "$KOS/dev/pts"
mountpoint -q "$KOS/proc"    || mount -vt proc proc "$KOS/proc"
mountpoint -q "$KOS/sys"     || mount -vt sysfs sysfs "$KOS/sys"
mountpoint -q "$KOS/run"     || mount -vt tmpfs tmpfs "$KOS/run"
if [ -h "$KOS/dev/shm" ]; then
    install -v -d -m 1777 "${KOS}$(realpath /dev/shm)"
else
    mountpoint -q "$KOS/dev/shm" || mount -vt tmpfs -o nosuid,nodev tmpfs "$KOS/dev/shm"
fi

echo "=== 3. Inner chroot-builder voorbereiden ==="
cat << 'CHROOT_INNER' > "${KOS}/work/recipes/_chroot_stage1_inner.sh"
#!/usr/bin/env bash
set -euo pipefail

SOURCES="/work/sources"
BUILD="/work/build"
LOGS="/work/logs"
STAMPS="/work/stamps"
JOBS="$(nproc 2>/dev/null || echo 2)"

if [ ! -f "${STAMPS}/chroot-00-layout.done" ]; then
    echo "[INIT] KaaijkOS basisstructuur & kernbestanden aanmaken..."
    mkdir -pv /{boot,home,mnt,opt,srv}
    mkdir -pv /etc/{opt,sysconfig}
    mkdir -pv /lib/firmware
    mkdir -pv /usr/{,local/}{include,src}
    mkdir -pv /usr/lib/locale
    mkdir -pv /usr/local/{bin,lib,sbin}
    mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
    mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
    mkdir -pv /usr/{,local/}share/man/man{1..8}
    mkdir -pv /var/{cache,local,log,mail,opt,spool}
    mkdir -pv /var/lib/{color,misc,locate,kpkg}
    mkdir -pv /var/cache/kpkg

    ln -sfv /run /var/run
    ln -sfv /run/lock /var/lock
    install -dv -m 0700 /root
    install -dv -m 1777 /tmp /var/tmp

    ln -sfv /proc/self/mounts /etc/mtab

    cat > /etc/hosts << 'EOF'
127.0.0.1  localhost KaaijkOS
::1        localhost
EOF

    cat > /etc/os-release << 'EOF'
NAME="KaaijkOS"
PRETTY_NAME="KaaijkOS 1.0"
ID=kaaijkos
VERSION="1.0"
VERSION_ID="1.0"
BUILD_ID="rolling"
HOME_URL="https://kaaijkos.com"
DOCUMENTATION_URL="https://wiki.kaaijkos.com/"
SUPPORT_URL="https://kaaijkos.nl"
LOGO=kaaijkos-logo
EOF

    cat > /etc/passwd << 'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

    cat > /etc/group << 'EOF'
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

    touch /var/log/{btmp,lastlog,faillog,wtmp}
    chgrp -v utmp /var/log/lastlog
    chmod -v 664 /var/log/lastlog
    chmod -v 600 /var/log/btmp
    touch "${STAMPS}/chroot-00-layout.done"
fi

run_chroot_step() {
    local STEP="$1"
    local TARBALL="$2"
    local FUNC="$3"
    local STAMP="${STAMPS}/chroot-${STEP}.done"
    local LOG="${LOGS}/chroot-${STEP}.log"

    if [ -f "$STAMP" ]; then
        printf "[SKIP]  %-20s (al voltooid)\n" "$STEP"
        return 0
    fi

    local T0
    T0=$(date +%s)
    printf "[BUILD] %-20s starten (log: %s)...\n" "$STEP" "$LOG"

    local WORKDIR="${BUILD}/chroot-${STEP}"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"

    (
        set -euo pipefail
        cd "$WORKDIR"
        tar -xf "${SOURCES}/${TARBALL}"
        local SRCDIR
        SRCDIR=$(find "$WORKDIR" -mindepth 1 -maxdepth 1 -type d | head -n1)
        cd "$SRCDIR"
        "$FUNC"
    ) >"$LOG" 2>&1 || {
        echo "!!! FOUT BIJ chroot-${STEP} !!! Laatste 40 regels van ${LOG}:" >&2
        tail -n 40 "$LOG" >&2
        exit 1
    }

    rm -rf "$WORKDIR"
    touch "$STAMP"
    local DT=$(( $(date +%s) - T0 ))
    printf "[DONE]  %-20s voltooid in %dm %02ds\n" "$STEP" $((DT / 60)) $((DT % 60))
}

build_gettext() {
    ./configure --disable-shared
    make -j"$JOBS"
    cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
}

build_bison() {
    ./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
    make -j"$JOBS"
    make install
}

build_perl() {
    sh Configure -des                                         \
                 -D prefix=/usr                               \
                 -D vendorprefix=/usr                         \
                 -D useshrplib                                \
                 -D privlib=/usr/lib/perl5/5.44/core_perl     \
                 -D archlib=/usr/lib/perl5/5.44/core_perl     \
                 -D sitelib=/usr/lib/perl5/5.44/site_perl     \
                 -D sitearch=/usr/lib/perl5/5.44/site_perl    \
                 -D vendorlib=/usr/lib/perl5/5.44/vendor_perl \
                 -D vendorarch=/usr/lib/perl5/5.44/vendor_perl
    make -j"$JOBS"
    make install
}

build_zlib() {
    ./configure --prefix=/usr
    make -j"$JOBS"
    make install
    rm -fv /usr/lib/libz.a
}

build_mpdecimal() {
    ./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/mpdecimal-4.0.1
    make -j"$JOBS"
    make install
}

build_python() {
    ./configure --prefix=/usr       \
                --enable-shared     \
                --without-ensurepip \
                --without-static-libpython
    make -j"$JOBS"
    make install
}

build_texinfo() {
    ./configure --prefix=/usr
    make -j"$JOBS"
    make install
}

build_util_linux() {
    mkdir -pv /var/lib/hwclock
    ./configure --libdir=/usr/lib     \
                --runstatedir=/run    \
                --disable-chfn-chsh   \
                --disable-login       \
                --disable-nologin     \
                --disable-su          \
                --disable-setpriv     \
                --disable-runuser     \
                --disable-pylibmount  \
                --disable-static      \
                --disable-liblastlog2 \
                --without-python      \
                ADJTIME_PATH=/var/lib/hwclock/adjtime \
                --docdir=/usr/share/doc/util-linux-2.42.2
    make -j"$JOBS"
    make install
}

run_chroot_step "01-gettext"    "gettext-1.0.tar.xz"      build_gettext
run_chroot_step "02-bison"      "bison-3.8.2.tar.xz"      build_bison
run_chroot_step "03-perl"       "perl-5.44.0.tar.xz"      build_perl
run_chroot_step "04-zlib"       "zlib-1.3.2.tar.gz"       build_zlib
run_chroot_step "05-mpdecimal"  "mpdecimal-4.0.1.tar.gz"  build_mpdecimal
run_chroot_step "06-python"     "Python-3.14.7.tar.xz"    build_python
run_chroot_step "07-texinfo"    "texinfo-7.3.tar.xz"      build_texinfo
run_chroot_step "08-util-linux" "util-linux-2.42.2.tar.xz" build_util_linux

echo "[CLEANUP] Tijdelijke /tools & .la bestanden opruimen..."
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name '*.la' -delete 2>/dev/null || true
rm -rf /tools
touch "${STAMPS}/stage1-COMPLETE.done"
echo "CHROOT STAGE-1 VOLTOOID!"
CHROOT_INNER

chmod 755 "${KOS}/work/recipes/_chroot_stage1_inner.sh"

echo "=== 4. Geïsoleerde KaaijkOS chroot binnengaan ==="
chroot "$KOS" /usr/bin/env -i \
    HOME=/root                \
    TERM="${TERM:-xterm}"     \
    PATH=/usr/bin:/usr/sbin   \
    /bin/bash /work/recipes/_chroot_stage1_inner.sh

echo "=== 5. Herstel-checkpoint opslaan ==="
CKPT="${KOS}/work/kaaijkos-stage1-checkpoint.tar.zst"
if [ ! -f "$CKPT" ]; then
    tar -C "$KOS" --zstd \
        --exclude='./work' --exclude='./dev/*' --exclude='./proc/*' \
        --exclude='./sys/*' --exclude='./run/*' --exclude='./boot/efi/*' \
        -cpf "$CKPT" .
    echo "Checkpoint opgeslagen: ${CKPT} ($(du -h "$CKPT" | awk '{print $1}'))"
fi

echo "================================================================================"
echo "  FASE 2 (STAGE-1) 100% KLAAR! Je hebt nu een volledig geïsoleerde"
echo "  KaaijkOS chroot met eigen GCC 16.2 + Glibc 2.44 + Python 3.14!"
echo "  Klaar voor Fase 3 (alle ~70 definitieve KaaijkOS pakketten via kpkg)!"
echo "================================================================================"
