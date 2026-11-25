#!/usr/bin/env bash
# ==============================================================================
# KaaijkOS 1.1 — Fase 5b: Live MOTD (TrueColor K-logo), Pre-Login /etc/issue &
# Dynamische bash-prompt (\h > Root / user)
# ==============================================================================
set -euo pipefail

S=/work/stage/kaaijkos-motd
rm -rf "$S"
mkdir -p "$S/usr/bin" "$S/etc/profile.d"

if [ -f /work/tools/motd ]; then
    cp -f /work/tools/motd "$S/usr/bin/motd"
else
    echo "FOUT: /work/tools/motd ontbreekt (kopieer tools/motd uit de KaaijkOS repo)." >&2
    exit 1
fi
chmod 755 "$S/usr/bin/motd"

cat << 'PROF_EOF' > "$S/etc/profile.d/kaaijkos-motd.sh"
# KaaijkOS 1.1 — Toon live MOTD 1x bij elke interactieve login-shell
if [[ $- == *i* ]] && [ -t 1 ] && [ -z "${KAAIJKOS_MOTD_SHOWN:-}" ]; then
    export KAAIJKOS_MOTD_SHOWN=1
    command -v motd >/dev/null 2>&1 && motd --clear
fi
PROF_EOF
chmod 644 "$S/etc/profile.d/kaaijkos-motd.sh"

if ! grep -q '/etc/profile.d' /etc/profile 2>/dev/null; then
    cat << 'ADD_PROF' >> /etc/profile

for _f in /etc/profile.d/*.sh; do
    [ -r "$_f" ] && . "$_f"
done
unset _f
ADD_PROF
fi

kpkg pack "$S" kaaijkos-motd 1.1
kpkg install /var/cache/kpkg/kaaijkos-motd-1.1.kpkg.tar.zst
rm -rf "$S"

echo "=== Veilig pre-login /etc/issue (zonder interne systeeminfo) ==="
python3 - << 'PY_ISSUE'
LOGO = [
    "                        -=----",
    "            :--        =====--",
    "         ---===      ++++====-",
    "        --===++   =++++++++   ",
    "        ==++*#%+=++++++++     ",
    "        ++###++++++++++       ",
    "        ##*++++++++++         ",
    "        +++++***++====        ",
    "        +++++++======+++++    ",
    "        ==+++++ ===+++++++++  ",
    "        -=====+    ++++++++===",
    "            -==       +++====-",
]
R, D, C, W = "\x1b[0m", "\x1b[2m", "\x1b[1;36m", "\x1b[1;37m"
def color_line(r, line):
    out = []
    for c, ch in enumerate(line):
        if ch == " ":
            out.append(" "); continue
        if c <= 15 and r <= 4:
            col = "\x1b[1;33m" if r <= 2 else "\x1b[1;31m"
        elif c <= 15:
            col = "\x1b[1;34m" if r <= 8 else "\x1b[1;36m"
        elif r <= 6:
            col = "\x1b[1;36m"
        else:
            col = "\x1b[1;35m"
        out.append(f"{col}{ch}")
    out.append(R)
    return "".join(out)

right = {
    3: f"{C}KaaijkOS 1.1{R}",
    4: f"{D}------------------------------{R}",
    5: f"{W}Host  {R}: \\n",
    6: f"{W}IP    {R}: \\4",
    7: f"{W}TTY   {R}: \\l",
    8: f"{D}------------------------------{R}",
    9: f"{D}Geautoriseerde toegang alleen.{R}",
}
lines = ["\x1b[H\x1b[2J"]
for i, raw in enumerate(LOGO):
    left = color_line(i, raw)
    txt = right.get(i, "")
    lines.append(f"{left}    {txt}" if txt else left)
lines.extend(["", ""])
open("/etc/issue", "w", encoding="utf-8").write("\n".join(lines))
PY_ISSUE

echo "=== Dynamische bash prompt (\h > Root / user) ==="
cat << 'BASHRC_EOF' > /etc/bash.bashrc
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

__kaaijkos_prompt() {
    local rc=$?
    local C_RESET='\[\e[0m\]'
    local C_DIM='\[\e[2m\]'
    local C_CYAN='\[\e[1;36m\]'
    local C_BLUE='\[\e[1;34m\]'
    local C_RED='\[\e[1;31m\]'
    local C_GREEN='\[\e[1;32m\]'

    local err_tag=""
    local sym_col="$C_GREEN"
    if [ "$rc" -ne 0 ]; then
        err_tag=" ${C_RED}[${rc}]${C_RESET}"
        sym_col="$C_RED"
    fi

    if [ "$(id -u)" -eq 0 ]; then
        PS1="${C_CYAN}\h${C_RESET} ${C_DIM}>${C_RESET} ${C_RED}Root${C_RESET} ${C_BLUE}\w${C_RESET}${err_tag} ${C_RED}#${C_RESET} "
    else
        PS1="${C_CYAN}\h${C_RESET} ${C_DIM}>${C_RESET} ${C_GREEN}\u${C_RESET} ${C_BLUE}\w${C_RESET}${err_tag} ${sym_col}>${C_RESET} "
    fi
}

PROMPT_COMMAND=__kaaijkos_prompt
BASHRC_EOF

systemctl is-system-running >/dev/null 2>&1 && systemctl restart getty@tty1.service || true
echo "=== Fase 5b KLAAR! ==="
