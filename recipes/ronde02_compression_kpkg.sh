#!/usr/bin/env bash
set -euo pipefail
export MAKEFLAGS="-j$(nproc)"
mkdir -p /work/stage /work/logs /work/build /var/lib/kpkg /var/cache/kpkg
cd /work/build

echo "=== [1/5] Zlib 1.3.2 ==="
rm -rf zlib-1.3.2
tar -xf /work/sources/zlib-1.3.2.tar.gz && cd zlib-1.3.2
./configure --prefix=/usr
make && make install
rm -fv /usr/lib/libz.a
cd /work/build && rm -rf zlib-1.3.2

echo "=== [2/5] Bzip2 1.0.8 ==="
rm -rf bzip2-1.0.8
tar -xf /work/sources/bzip2-1.0.8.tar.gz && cd bzip2-1.0.8
patch -Np1 -i /work/sources/bzip2-1.0.8-install_docs-1.patch
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so
make clean
make
make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do ln -sfv bzip2 "$i"; done
rm -fv /usr/lib/libbz2.a
cd /work/build && rm -rf bzip2-1.0.8

echo "=== [3/5] Xz 5.8.3 ==="
rm -rf xz-5.8.3
tar -xf /work/sources/xz-5.8.3.tar.xz && cd xz-5.8.3
./configure --prefix=/usr --disable-static --docdir=/usr/share/doc/xz-5.8.3
make && make install
cd /work/build && rm -rf xz-5.8.3

echo "=== [4/5] Lz4 1.10.0 ==="
rm -rf lz4-1.10.0
tar -xf /work/sources/lz4-1.10.0.tar.gz && cd lz4-1.10.0
make BUILD_STATIC=no PREFIX=/usr
make BUILD_STATIC=no PREFIX=/usr install
cd /work/build && rm -rf lz4-1.10.0

echo "=== [5/5] Zstd 1.5.7 ==="
rm -rf zstd-1.5.7
tar -xf /work/sources/zstd-1.5.7.tar.gz && cd zstd-1.5.7
make prefix=/usr
make prefix=/usr install
rm -fv /usr/lib/libzstd.a
cd /work/build && rm -rf zstd-1.5.7

echo "=== Eigen /usr/bin/kpkg (v2.0) installeren ==="
if [ -f /work/tools/kpkg ]; then
    cp -f /work/tools/kpkg /usr/bin/kpkg
else
    cat << 'KPKG_EOF' > /usr/bin/kpkg
#!/usr/bin/env bash
set -euo pipefail

DB_DIR="/var/lib/kpkg"
CACHE_DIR="/var/cache/kpkg"
mkdir -p "$DB_DIR" "$CACHE_DIR"

usage() {
    cat << 'USAGE'
KaaijkOS Package Manager (kpkg 2.0)
Gebruik:
  kpkg pack <stage_dir> <naam> <versie>  Verpak een DESTDIR-map naar .kpkg.tar.zst
  kpkg build <src_dir> <naam> <versie>   Compileer (CMake/Meson/Autotools/Make) -> .kpkg.tar.zst
  kpkg install <bestand.kpkg.tar.zst>    Installeer pakket & registreer alle bestanden
  kpkg remove <naam> [--force]           Verwijder pakket schoon (beschermt gedeelde bestanden)
  kpkg list                              Toon alle geinstalleerde KaaijkOS pakketten
  kpkg info <naam>                       Toon metadata van een pakket
  kpkg files <naam>                      Toon alle bestanden van een pakket
  kpkg owns <pad>                        Toon welk pakket eigenaar is van een bestand
USAGE
    exit 1
}

cmd="${1:-}"
case "$cmd" in
    pack)
        [ $# -eq 4 ] || usage
        STAGE="$(realpath "$2")"
        NAME="$3"
        VER="$4"
        cat << META > "${STAGE}/.KPKGINFO"
NAME=${NAME}
VERSION=${VER}
BUILT_AT=$(date -Iseconds)
ARCH=$(uname -m)
META
        PKG_FILE="${CACHE_DIR}/${NAME}-${VER}.kpkg.tar.zst"
        tar -C "$STAGE" --zstd -cpf "$PKG_FILE" .
        echo "  [kpkg] Verpakt: ${PKG_FILE} ($(du -h "$PKG_FILE" | awk '{print $1}'))"
        ;;
    build)
        [ $# -eq 4 ] || usage
        SRC="$(realpath "$2")"
        NAME="$3"
        VER="$4"
        STAGE="$(mktemp -d "/tmp/kpkg-stage-${NAME}.XXXXXX")"
        trap 'rm -rf "$STAGE"' EXIT
        cd "$SRC"
        if [ -f CMakeLists.txt ]; then
            cmake -B _kpkg_build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
            cmake --build _kpkg_build -j"$(nproc)"
            DESTDIR="$STAGE" cmake --install _kpkg_build
        elif [ -f meson.build ]; then
            meson setup _kpkg_build --prefix=/usr --buildtype=release
            ninja -C _kpkg_build -j"$(nproc)"
            DESTDIR="$STAGE" ninja -C _kpkg_build install
        elif [ -x configure ]; then
            ./configure --prefix=/usr
            make -j"$(nproc)"
            make DESTDIR="$STAGE" install
        elif [ -f Makefile ] || [ -f makefile ]; then
            make -j"$(nproc)"
            make DESTDIR="$STAGE" install PREFIX=/usr
        else
            echo "Fout: geen CMakeLists.txt, meson.build, configure of Makefile in $SRC" >&2
            exit 1
        fi
        kpkg pack "$STAGE" "$NAME" "$VER"
        ;;
    install)
        [ $# -eq 2 ] || usage
        PKG="$2"
        [ -f "$PKG" ] || { echo "Bestand niet gevonden: $PKG" >&2; exit 1; }
        META_TMP="$(mktemp)"
        trap 'rm -f "$META_TMP"' EXIT
        tar --zstd -xOf "$PKG" ./.KPKGINFO > "$META_TMP" 2>/dev/null || \
        tar --zstd -xOf "$PKG" .KPKGINFO > "$META_TMP"
        # shellcheck disable=SC1090
        source "$META_TMP"

        tar --zstd -tf "$PKG" | sed 's|^\./||' | grep -v -E '^$|/$|^\.KPKGINFO$' > "${DB_DIR}/${NAME}.list"
        cat << INFO > "${DB_DIR}/${NAME}.info"
NAME=${NAME}
VERSION=${VERSION}
ARCH=${ARCH:-$(uname -m)}
INSTALLED_AT=$(date -Iseconds)
INFO
        if ! tar --keep-directory-symlink -C / --zstd --exclude='./.KPKGINFO' --exclude='.KPKGINFO' -xpf "$PKG" 2>/dev/null; then
            EXT_DIR="$(mktemp -d /tmp/kpkg-ext.XXXXXX)"
            tar -C "$EXT_DIR" --zstd --exclude='./.KPKGINFO' --exclude='.KPKGINFO' -xpf "$PKG"
            (cd "$EXT_DIR" && find . -mindepth 1 -type d) | while IFS= read -r d; do mkdir -p "/${d#./}"; done
            (cd "$EXT_DIR" && find . -mindepth 1 ! -type d) | while IFS= read -r f; do cp -a --remove-destination "${EXT_DIR}/${f#./}" "/${f#./}"; done
            rm -rf "$EXT_DIR"
        fi
        ldconfig 2>/dev/null || true
        echo "  [kpkg] Geinstalleerd: ${NAME} (${VERSION}) [$(wc -l < "${DB_DIR}/${NAME}.list") bestanden]"
        ;;
    remove)
        [ $# -ge 2 ] || usage
        NAME="$2"
        FORCE="${3:-}"
        case "$NAME" in
            glibc|bash|coreutils|systemd|kpkg|util-linux)
                if [ "$FORCE" != "--force" ]; then
                    echo "WEIGERING: '${NAME}' is een kritiek KaaijkOS kernpakket (gebruik --force op eigen risico)." >&2
                    exit 1
                fi ;;
        esac
        LIST="${DB_DIR}/${NAME}.list"
        [ -f "$LIST" ] || { echo "Niet geinstalleerd: $NAME" >&2; exit 1; }
        tac "$LIST" | while IFS= read -r f; do
            [ -n "$f" ] || continue
            SHARED=0
            for other in "${DB_DIR}"/*.list; do
                [ "$other" = "$LIST" ] && continue
                [ -f "$other" ] || continue
                if grep -Fxq "$f" "$other"; then SHARED=1; break; fi
            done
            if [ "$SHARED" -eq 0 ]; then
                rm -f "/$f"
                d="$(dirname "/$f")"
                while [ "$d" != "/" ] && [ "$d" != "/usr" ] && [ "$d" != "/etc" ]; do
                    rmdir "$d" 2>/dev/null || break
                    d="$(dirname "$d")"
                done
            fi
        done
        rm -f "$LIST" "${DB_DIR}/${NAME}.info"
        ldconfig 2>/dev/null || true
        echo "  [kpkg] Verwijderd: ${NAME}"
        ;;
    list)
        COUNT=0
        for info in "${DB_DIR}"/*.info; do
            [ -e "$info" ] || continue
            COUNT=$((COUNT + 1))
            # shellcheck disable=SC1090
            source "$info"
            printf "%-24s %-16s %s\n" "$NAME" "$VERSION" "${ARCH:-x86_64}"
        done
        echo "--- Totaal: ${COUNT} KaaijkOS pakketten ---"
        ;;
    info)
        [ $# -eq 2 ] || usage
        cat "${DB_DIR}/$2.info"
        ;;
    files)
        [ $# -eq 2 ] || usage
        cat "${DB_DIR}/$2.list"
        ;;
    owns)
        [ $# -eq 2 ] || usage
        TARGET="${2#/}"
        grep -lFx "$TARGET" "${DB_DIR}"/*.list 2>/dev/null | sed 's|.*/||; s|\.list$||' || echo "Geen pakket gevonden voor /$TARGET"
        ;;
    *)
        usage
        ;;
esac
KPKG_EOF
fi
chmod 755 /usr/bin/kpkg

# Basis-pakketten registreren in /var/lib/kpkg
for entry in "iana-etc:20260805" "man-pages:6.18" "glibc:2.44" "zlib:1.3.2" "bzip2:1.0.8" "xz:5.8.3" "lz4:1.10.0" "zstd:1.5.7"; do
    N="${entry%%:*}"; V="${entry##*:}"
    printf 'NAME=%s\nVERSION=%s\nARCH=%s\nINSTALLED_AT=%s\n' "$N" "$V" "$(uname -m)" "$(date -Iseconds)" > "/var/lib/kpkg/${N}.info"
    : > "/var/lib/kpkg/${N}.list"
done
echo "usr/bin/kpkg" > /var/lib/kpkg/kpkg.list
printf 'NAME=kpkg\nVERSION=2.0\nARCH=%s\nINSTALLED_AT=%s\n' "$(uname -m)" "$(date -Iseconds)" > /var/lib/kpkg/kpkg.info

echo "=== RONDE 2 KLAAR! ==="
kpkg list
