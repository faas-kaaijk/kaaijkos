# KaaijkOS 1.1 — Toon live MOTD 1x bij elke interactieve login-shell
if [[ $- == *i* ]] && [ -t 1 ] && [ -z "${KAAIJKOS_MOTD_SHOWN:-}" ]; then
    export KAAIJKOS_MOTD_SHOWN=1
    command -v motd >/dev/null 2>&1 && motd --clear
fi
