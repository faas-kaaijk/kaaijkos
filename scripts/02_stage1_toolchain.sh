#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS From Scratch - Stap 2b: Stage-1 Geïsoleerde Cross-Toolchain & Tools
# - Draait automatisch als geïsoleerde niet-root gebruiker 'kosbuild' (env -i)
# - Doel-triplet: x86_64-kaaijkos-linux-gnu (0% host-vervuiling!)
# - Hervatbaar: voltooide pakketten worden overgeslagen via stamps/
# - Geheugenveilig: activeert /swapfile indien nodig en begrenst GCC op 2 cores bij <3.5GB RAM
# ==============================================================================
set -euo pipefail

KOS="/mnt/kaaijkos"
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"

# ---- Root-wrapper: richt gebruiker & rechten in en schakel over naar schone env -i ----
if [ "${1:-}" != "--as-builder" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        echo "FOUT: Start dit script als root (het schakelt zelf veilig over naar 'kosbuild')." >&2
        exit 1
    fi
    if ! mountpoint -q "$KOS"; then
        echo "FOUT: $KOS is niet gemount!" >&2
        exit 1
    fi

    # Zorg voor voldoende swap bij 2 GB RAM zodat GCC 16.2 nooit OOM gaat
    RAM_MB=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
    SWAP_MB=$(awk '/SwapTotal:/ {print int($2/1024)}' /proc/meminfo)
    if [ "$RAM_MB" -lt 3500 ] && [ "$SWAP_MB" -lt 2500 ] && [ -f /swapfile ]; then
        echo "[INFO] RAM is ${RAM_MB} MB -> /swapfile activeren als OOM-vangnet..."
        swapon /swapfile || true
    fi

    # Geïsoleerde build-gebruiker aanmaken
    if ! id kosbuild >/dev/null 2>&1; then
        groupadd -f kosbuild
        useradd -s /bin/bash -g kosbuild -m -k /dev/null kosbuild
    fi

    mkdir -p "$KOS"/work/{build,logs,stamps,sources,recipes,packages}
    chown -R kosbuild:kosbuild "$KOS"/{usr,var,etc,lib64,tools} \
        "$KOS"/work/{build,logs,stamps}
    chmod -R a+rX "$KOS"/work/{sources,recipes}

    ARCH="$(uname -m)"
    echo "================================================================================"
    echo "  KaaijkOS Stage-1 Cross-Toolchain Builder"
    echo "  Doel-triplet : ${ARCH}-kaaijkos-linux-gnu"
    echo "  Rootfs       : ${KOS}"
    echo "  Build-user   : kosbuild (schone env -i)"
    echo "================================================================================"

    exec su -s /bin/bash kosbuild -c \
        "exec env -i HOME=/home/kosbuild TERM='${TERM:-xterm}' LC_ALL=POSIX \
        KOS='${KOS}' KOS_TGT='${ARCH}-kaaijkos-linux-gnu' \
        PATH='${KOS}/tools/bin:/usr/bin:/bin' \
        CONFIG_SITE='${KOS}/usr/share/config.site' \
        /bin/bash '${SCRIPT_PATH}' --as-builder"
fi

# ---- Vanaf hier draaien we als 'kosbuild' in een 100% schone env -i ----
umask 022
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS || true

SOURCES="${KOS}/work/sources"
BUILD="${KOS}/work/build"
LOGS="${KOS}/work/logs"
STAMPS="${KOS}/work/stamps"

JOBS="$(nproc 2>/dev/null || echo 2)"
RAM_MB=$(awk '/MemTotal:/ {print int($2/1024)}' /proc/meminfo)
if [ "$RAM_MB" -lt 3500 ] && [ "$JOBS" -gt 2 ]; then
    GCC_JOBS=2
else
    GCC_JOBS="$JOBS"
fi

echo "Actieve build-instellingen: JOBS=${JOBS}, GCC_JOBS=${GCC_JOBS}, RAM=${RAM_MB}MB, KOS_TGT=${KOS_TGT}"

run_step() {
    local STEP="$1"
    local TARBALL="$2"
    local FUNC="$3"
    local STAMP="${STAMPS}/stage1-${STEP}.done"
    local LOG="${LOGS}/stage1-${STEP}.log"

    if [ -f "$STAMP" ]; then
        printf "[SKIP] %-20s (al voltooid)\n" "$STEP"
        return 0
    fi

    local T0
    T0=$(date +%s)
    printf "[BUILD] %-20s starten (log: %s)...\n" "$STEP" "$LOG"

    local WORKDIR="${BUILD}/${STEP}"
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
        echo "!!! FOUT BIJ ${STEP} !!! Laatste 40 regels van ${LOG}:" >&2
        tail -n 40 "$LOG" >&2
        exit 1
    }

    rm -rf "$WORKDIR"
    touch "$STAMP"
    local DT=$(( $(date +%s) - T0 ))
    printf "[DONE]  %-20s voltooid in %dm %02ds\n" "$STEP" $((DT / 60)) $((DT % 60))
}

# ==============================================================================
# DEEL A: CROSS-TOOLCHAIN (5 pakketten)
# ==============================================================================

build_binutils_pass1() {
    mkdir -v build && cd build
    ../configure --prefix="$KOS/tools" \
                 --with-sysroot="$KOS" \
                 --target="$KOS_TGT"   \
                 --disable-nls         \
                 --enable-gprofng=no   \
                 --disable-werror      \
                 --enable-new-dtags    \
                 --enable-default-hash-style=gnu
    make -j"$JOBS"
    make install
}

build_gcc_pass1() {
    tar -xf "${SOURCES}/mpfr-4.2.2.tar.xz" && mv -v mpfr-4.2.2 mpfr
    tar -xf "${SOURCES}/gmp-6.3.0.tar.xz"  && mv -v gmp-6.3.0 gmp
    tar -xf "${SOURCES}/mpc-1.4.1.tar.xz"  && mv -v mpc-1.4.1 mpc

    case "$(uname -m)" in
        x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac

    mkdir -v build && cd build
    ../configure                  \
        --target="$KOS_TGT"       \
        --prefix="$KOS/tools"     \
        --with-glibc-version=2.44 \
        --with-sysroot="$KOS"     \
        --with-newlib             \
        --without-headers         \
        --enable-default-pie      \
        --enable-default-ssp      \
        --disable-fixincludes     \
        --disable-nls             \
        --disable-shared          \
        --disable-multilib        \
        --disable-threads         \
        --disable-libatomic       \
        --disable-libgomp         \
        --disable-libquadmath     \
        --disable-libssp          \
        --disable-libvtv          \
        --disable-libstdcxx       \
        --enable-languages=c,c++
    make -j"$GCC_JOBS"
    make install
    cat ../gcc/{limitx,glimits,limity}.h > "$("$KOS_TGT-gcc" -print-file-name=include)/limits.h"
}

build_linux_headers() {
    make mrproper
    make headers
    find usr/include -type f ! -name '*.h' -delete
    cp -rv usr/include "$KOS/usr"
}

build_glibc() {
    case "$(uname -m)" in
        x86_64)
            ln -sfv ../lib/ld-linux-x86-64.so.2 "$KOS/lib64/ld-linux-x86-64.so.2"
            ln -sfv ../lib/ld-linux-x86-64.so.2 "$KOS/lib64/ld-lsb-x86-64.so.3"
            ;;
    esac

    patch -Np1 -i "${SOURCES}/glibc-fhs-1.patch"
    patch -Np1 -i "${SOURCES}/glibc-2.44-upstream_fixes-1.patch"

    mkdir -v build && cd build
    echo "rootsbindir=/usr/sbin" > configparms
    ../configure                              \
        --prefix=/usr                         \
        --host="$KOS_TGT"                     \
        --build="$(../scripts/config.guess)"  \
        --disable-nscd                        \
        libc_cv_slibdir=/usr/lib              \
        --enable-kernel=5.10
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    sed '/RTLDLIST=/s@/usr@@g' -i "$KOS/usr/bin/ldd"

    # Verplichte sanity check: linkt onze cross-compiler echt tegen de NIEUWE KaaijkOS glibc?
    echo 'int main(){}' | "$KOS_TGT-gcc" -x c - -o sanity_test
    local INTERP
    INTERP=$("$KOS_TGT-readelf" -l sanity_test | grep 'Requesting program interpreter' || true)
    echo "SANITY CHECK: ${INTERP}"
    echo "$INTERP" | grep -q '/lib64/ld-linux-x86-64.so.2' || {
        echo "FOUT: Cross-compiler linkt niet tegen /lib64/ld-linux-x86-64.so.2!" >&2
        exit 1
    }
    rm -f sanity_test
}

build_libstdcpp() {
    mkdir -v build && cd build
    ../libstdc++-v3/configure        \
        --host="$KOS_TGT"            \
        --build="$(../config.guess)" \
        CXX="$KOS_TGT-gcc"           \
        --prefix=/usr                \
        --disable-multilib           \
        --disable-nls                \
        --disable-libstdcxx-pch      \
        --with-gxx-include-dir="/tools/${KOS_TGT}/include/c++/16.2.0"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    rm -fv "$KOS"/usr/lib/lib{stdc++{,exp,fs},supc++}.la
}

# ==============================================================================
# DEEL B: CROSS-COMPILED TEMPORARY TOOLS (17 pakketten)
# ==============================================================================

build_m4() {
    mkdir -p "$KOS/usr/share"
    cat > "$KOS/usr/share/config.site" << 'EOF'
ac_cv_func_posix_spawn_file_actions_addchdir=yes
ac_cv_func_posix_spawn_file_actions_addfchdir=yes
EOF
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_ncurses() {
    mkdir build
    pushd build
        ../configure --prefix="$KOS/tools" AWK=gawk
        make -j"$JOBS" -C include
        make -j"$JOBS" -C progs tic
        install progs/tic "$KOS/tools/bin"
    popd

    ./configure --prefix=/usr                \
                --host="$KOS_TGT"            \
                --build="$(./config.guess)"  \
                --mandir=/usr/share/man      \
                --with-manpage-format=normal \
                --with-shared                \
                --without-normal             \
                --with-cxx-shared            \
                --without-debug              \
                --without-ada                \
                --disable-stripping          \
                AWK=gawk
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    ln -sfv libncursesw.so "$KOS/usr/lib/libncurses.so"
    sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "$KOS/usr/include/curses.h"
}

build_bash() {
    ./configure --prefix=/usr                        \
                --build="$(sh support/config.guess)" \
                --host="$KOS_TGT"                    \
                --without-bash-malloc                \
                --docdir=/usr/share/doc/bash-5.3
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    ln -sfv bash "$KOS/bin/sh"
}

build_coreutils() {
    ./configure --prefix=/usr                       \
                --host="$KOS_TGT"                   \
                --build="$(build-aux/config.guess)" \
                --enable-install-program=hostname
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    mv -v "$KOS/usr/bin/chroot" "$KOS/usr/sbin"
    mkdir -pv "$KOS/usr/share/man/man8"
    mv -v "$KOS/usr/share/man/man1/chroot.1" "$KOS/usr/share/man/man8/chroot.8"
    sed -i 's/"1"/"8"/' "$KOS/usr/share/man/man8/chroot.8"
}

build_diffutils() {
    ./configure --prefix=/usr                     \
                --host="$KOS_TGT"                 \
                gl_cv_func_strcasecmp_works=yes   \
                --build="$(./build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_file() {
    mkdir build
    pushd build
        ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib
        make -j"$JOBS"
    popd
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(./config.guess)"
    make -j"$JOBS" FILE_COMPILE="$(pwd)/build/src/file"
    make DESTDIR="$KOS" install
    rm -fv "$KOS/usr/lib/libmagic.la"
}

build_findutils() {
    ./configure --prefix=/usr                     \
                --localstatedir=/var/lib/locate   \
                --host="$KOS_TGT"                 \
                --build="$(build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_gawk() {
    sed -i 's/extras//' Makefile.in
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_grep() {
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(./build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_gzip() {
    ./configure --prefix=/usr --host="$KOS_TGT"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_make() {
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_patch() {
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_sed() {
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(./build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_tar() {
    ./configure --prefix=/usr --host="$KOS_TGT" --build="$(build-aux/config.guess)"
    make -j"$JOBS"
    make DESTDIR="$KOS" install
}

build_xz() {
    ./configure --prefix=/usr                       \
                --host="$KOS_TGT"                   \
                --build="$(build-aux/config.guess)" \
                --disable-static                    \
                --docdir=/usr/share/doc/xz-5.8.3
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    rm -fv "$KOS/usr/lib/liblzma.la"
}

build_binutils_pass2() {
    sed '6031s/$add_dir//' -i ltmain.sh
    mkdir -v build && cd build
    ../configure                     \
        --prefix=/usr                \
        --build="$(../config.guess)" \
        --host="$KOS_TGT"            \
        --disable-nls                \
        --enable-shared              \
        --enable-gprofng=no          \
        --disable-werror             \
        --enable-64-bit-bfd          \
        --enable-new-dtags           \
        --enable-default-hash-style=gnu
    make -j"$JOBS"
    make DESTDIR="$KOS" install
    rm -fv "$KOS"/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
}

build_gcc_pass2() {
    tar -xf "${SOURCES}/mpfr-4.2.2.tar.xz" && mv -v mpfr-4.2.2 mpfr
    tar -xf "${SOURCES}/gmp-6.3.0.tar.xz"  && mv -v gmp-6.3.0 gmp
    tar -xf "${SOURCES}/mpc-1.4.1.tar.xz"  && mv -v mpc-1.4.1 mpc

    case "$(uname -m)" in
        x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
    esac

    mkdir -v build && cd build
    ../configure                     \
        --build="$(../config.guess)" \
        --host="$KOS_TGT"            \
        --target="$KOS_TGT"          \
        --prefix=/usr                \
        --with-build-sysroot="$KOS"  \
        --enable-default-pie         \
        --enable-default-ssp         \
        --disable-fixincludes        \
        --disable-nls                \
        --disable-multilib           \
        --disable-libatomic          \
        --disable-libgomp            \
        --disable-libquadmath        \
        --disable-libsanitizer       \
        --disable-libssp             \
        --disable-libvtv             \
        --enable-languages=c,c++     \
        CXX_FOR_TARGET="${KOS_TGT}-gcc -nostdinc++" \
        LDFLAGS_FOR_TARGET="-L${PWD}/${KOS_TGT}/libgcc" \
        target_configargs=gcc_cv_target_thread_file=posix
    make -j"$GCC_JOBS"
    make DESTDIR="$KOS" install
    ln -sfv gcc "$KOS/usr/bin/cc"
}

# ---- Uitvoeren in exacte afhankelijkheidsvolgorde ----
TOTAL_T0=$(date +%s)

run_step "01-binutils-pass1" "binutils-2.47.tar.xz"  build_binutils_pass1
run_step "02-gcc-pass1"      "gcc-16.2.0.tar.xz"     build_gcc_pass1
run_step "03-linux-headers"  "linux-7.3.6.tar.xz"    build_linux_headers
run_step "04-glibc"          "glibc-2.44.tar.xz"     build_glibc
run_step "05-libstdcpp"      "gcc-16.2.0.tar.xz"     build_libstdcpp

run_step "06-m4"             "m4-1.4.21.tar.xz"      build_m4
run_step "07-ncurses"        "ncurses-6.6.tar.gz"    build_ncurses
run_step "08-bash"           "bash-5.3.tar.gz"       build_bash
run_step "09-coreutils"      "coreutils-9.11.tar.xz" build_coreutils
run_step "10-diffutils"      "diffutils-3.12.tar.xz" build_diffutils
run_step "11-file"           "file-5.48.tar.gz"      build_file
run_step "12-findutils"      "findutils-4.11.0.tar.xz" build_findutils
run_step "13-gawk"           "gawk-5.4.1.tar.xz"     build_gawk
run_step "14-grep"           "grep-3.12.tar.xz"      build_grep
run_step "15-gzip"           "gzip-1.14.tar.xz"      build_gzip
run_step "16-make"           "make-4.4.1.tar.gz"     build_make
run_step "17-patch"          "patch-2.8.tar.xz"      build_patch
run_step "18-sed"            "sed-4.10.tar.xz"       build_sed
run_step "19-tar"            "tar-1.35.tar.xz"       build_tar
run_step "20-xz"             "xz-5.8.3.tar.xz"       build_xz
run_step "21-binutils-pass2" "binutils-2.47.tar.xz"  build_binutils_pass2
run_step "22-gcc-pass2"      "gcc-16.2.0.tar.xz"     build_gcc_pass2

TOTAL_DT=$(( $(date +%s) - TOTAL_T0 ))
echo "================================================================================"
echo "  STAGE-1 CROSS-TOOLCHAIN + TOOLS 100% VOLTOOID in $((TOTAL_DT / 60))m $((TOTAL_DT % 60))s!"
echo "  Volgende stap (als root): bash /mnt/kaaijkos/work/recipes/03_stage1_chroot_tools.sh"
echo "================================================================================"
