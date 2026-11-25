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
