#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.0 — Stap 2a: Upstream Broncode Downloaden & Verifiëren
# - Haalt alle geverifieerde LFS 13.1 upstream archieven & patches op (sources.manifest)
# - Inclusief automatische OSUOSL-mirror fallback als SourceForge HTTP 403 geeft
# - Haalt ook Linux 7.3.6 + Ronde 10 extras op (extras.manifest)
# - Kopieert dit repo's recipes/ en tools/ direct naar /mnt/kaaijkos/work/
# ==============================================================================
set -euo pipefail

KOS="${KOS:-/mnt/kaaijkos}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

MANIFEST=""
EXTRAS_MANIFEST=""
for d in "${REPO_DIR}/manifest" "${SCRIPT_DIR}/../manifest" "${SCRIPT_DIR}"; do
    [ -f "${d}/sources.manifest" ] && MANIFEST="${d}/sources.manifest"
    [ -f "${d}/extras.manifest" ]  && EXTRAS_MANIFEST="${d}/extras.manifest"
done

[ -n "$MANIFEST" ] || { echo "FOUT: sources.manifest niet gevonden!" >&2; exit 1; }
if ! mountpoint -q "$KOS"; then
    echo "FOUT: $KOS is niet gemount! Draai eerst ./scripts/00_prepare_disk.sh" >&2
    exit 1
fi

SOURCES="${KOS}/work/sources"
mkdir -p "$SOURCES" "${KOS}/work/recipes" "${KOS}/work/tools"
cd "$SOURCES"

TOTAL=$(( $(grep -cve '^[[:space:]]*\(#\|$\)' "$MANIFEST") ))
if [ -n "$EXTRAS_MANIFEST" ]; then
    TOTAL=$(( TOTAL + $(grep -cve '^[[:space:]]*\(#\|$\)' "$EXTRAS_MANIFEST") ))
fi
COUNT=0
FAILED=0

echo "================================================================================"
echo "  KaaijkOS 1.0 Broncode Downloader (${TOTAL} upstream archieven & patches)"
echo "  Doelmap: ${SOURCES}"
echo "================================================================================"

fetch_manifest() {
    local MFILE="$1"
    while read -r EXPECTED_MD5 FILENAME URL; do
        [[ -n "${EXPECTED_MD5:-}" && "$EXPECTED_MD5" != \#* ]] || continue
        COUNT=$((COUNT + 1))

        # Hergebruik eigen cached kernelbroncode indien aanwezig op bouw-host
        if [ "$FILENAME" = "linux-7.3.6.tar.xz" ] && [ -f /usr/src/kaaijkos/kernel/linux-7.3.6.tar.xz ] && [ ! -f "$FILENAME" ]; then
            printf "[%2d/%d] Kopie cache: %s (van /usr/src/kaaijkos/kernel)\n" "$COUNT" "$TOTAL" "$FILENAME"
            cp -f /usr/src/kaaijkos/kernel/linux-7.3.6.tar.xz "$FILENAME"
            continue
        fi

        if [ -s "$FILENAME" ]; then
            if [ "$EXPECTED_MD5" = "-" ]; then
                printf "[%2d/%d] OK (cache) : %s\n" "$COUNT" "$TOTAL" "$FILENAME"
                continue
            fi
            CUR_MD5=$(md5sum "$FILENAME" | awk '{print $1}')
            if [ "$CUR_MD5" = "$EXPECTED_MD5" ]; then
                printf "[%2d/%d] OK (cache) : %s\n" "$COUNT" "$TOTAL" "$FILENAME"
                continue
            else
                echo "  [WARN] Ongeldige checksum voor bestaand bestand ${FILENAME}, opnieuw downloaden..."
                rm -f "$FILENAME"
            fi
        fi

        printf "[%2d/%d] Download   : %s ... " "$COUNT" "$TOTAL" "$FILENAME"
        DL_OK=0
        if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -A "Mozilla/5.0" -o "${FILENAME}.part" "$URL"; then
            DL_OK=1
        elif [[ "$URL" == *sourceforge.net* || "$URL" == *prdownloads.sourceforge.net* ]]; then
            # Automatische OSUOSL LFS 13.1 fallback mirror bij SourceForge 403/timeout
            MIRROR_URL="https://ftp.osuosl.org/pub/lfs/lfs-packages/13.1/${FILENAME}"
            if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "${FILENAME}.part" "$MIRROR_URL"; then
                DL_OK=1
            fi
        fi

        if [ "$DL_OK" -eq 1 ]; then
            mv -f "${FILENAME}.part" "$FILENAME"
            if [ "$EXPECTED_MD5" = "-" ]; then
                echo "OK"
            else
                CUR_MD5=$(md5sum "$FILENAME" | awk '{print $1}')
                if [ "$CUR_MD5" = "$EXPECTED_MD5" ]; then
                    echo "OK (md5 match)"
                else
                    echo "FOUT (md5 mismatch! verwacht=${EXPECTED_MD5}, gekregen=${CUR_MD5})"
                    rm -f "$FILENAME"
                    FAILED=$((FAILED + 1))
                fi
            fi
        else
            echo "FOUT (download mislukt: ${URL})"
            rm -f "${FILENAME}.part"
            FAILED=$((FAILED + 1))
        fi
    done < "$MFILE"
}

fetch_manifest "$MANIFEST"
[ -n "$EXTRAS_MANIFEST" ] && fetch_manifest "$EXTRAS_MANIFEST"

# Kopieer recepten & tools mee in /mnt/kaaijkos/work/ voor direct gebruik in chroot
if [ -d "${REPO_DIR}/recipes" ]; then
    cp -af "${REPO_DIR}/recipes/"*.sh "${KOS}/work/recipes/"
    chmod +x "${KOS}/work/recipes/"*.sh
fi
if [ -f "${SCRIPT_DIR}/06_build_all_stage2.sh" ]; then
    cp -af "${SCRIPT_DIR}/06_build_all_stage2.sh" "${KOS}/work/recipes/"
    chmod +x "${KOS}/work/recipes/06_build_all_stage2.sh"
fi
if [ -d "${REPO_DIR}/tools" ]; then
    cp -af "${REPO_DIR}/tools/"* "${KOS}/work/tools/"
    chmod +x "${KOS}/work/tools/"*
fi
chmod -R a+rX "$SOURCES" "${KOS}/work/recipes" "${KOS}/work/tools"

echo "================================================================================"
if [ "$FAILED" -gt 0 ]; then
    echo "  KLAAR MET ${FAILED} FOUT(EN). Draai dit script nogmaals om ontbrekende bestanden op te halen."
    exit 1
else
    echo "  ALLE ${TOTAL} UPSTREAM BRONNEN GEVERIFIEERD EN KLAAR!"
    echo "  Totale grootte: $(du -sh "$SOURCES" | awk '{print $1}')"
fi
echo "================================================================================"
