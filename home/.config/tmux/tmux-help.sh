#!/bin/sh
# Minidite tmux keybindings (colors aligned with show-help in ~/.bashrc)

BOLD='\033[1m'
LCYAN='\033[96m'
LYELLOW='\033[93m'
GRAY='\033[90m'
RED='\033[91m'
NC='\033[0m'

show-help() {
    echo -e "\n${BOLD}${LCYAN}=== Tmux keybindings ===${NC}\n"
    echo -e "Prefix: ${LYELLOW}Ctrl${NC} + ${LYELLOW}a${NC}"
    echo -e "${GRAY}  Press Ctrl+a twice to send a literal Ctrl+a\n"


    echo -e "${BOLD}${LCYAN}Config${NC}"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}C${NC}   reload config"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}h${NC}   this help (this script)\n"

    echo -e "${BOLD}${LCYAN}Sessions${NC}"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}s${NC}   new session (prompt for name)"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}S${NC}   next session"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}R${NC}   rename session"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}K${NC}   kill session (confirm)"
    echo -e "  ${LYELLOW}Ctrl${NC} + ${LYELLOW}d${NC}   detach (session keeps running)"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}Ctrl${NC} + ${LYELLOW}d${NC}   send EOF (exit shell, Python REPL, etc.)\n"

    echo -e "${BOLD}${LCYAN}Windows${NC}"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}w${NC}   new window"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}W${NC}   next window"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}r${NC}   rename window"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}Q${NC}   kill window (confirm)"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}Tab${NC}   last window\n"

    echo -e "${BOLD}${LCYAN}Panes${NC}"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}arrow keys${NC}   split (same path as current pane)"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}q${NC}   kill pane"
    echo -e "  ${LYELLOW}Alt${NC} + ${LYELLOW}arrow keys${NC}   move between panes (no prefix)"
    echo -e "  ${LYELLOW}mouse${NC}   drag borders to resize\n"

    echo -e "${BOLD}${LCYAN}Copy mode${NC}"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}Enter${NC}   enter copy mode"
    echo -e "  ${LYELLOW}v / y / C-v / Esc${NC}   vi-style selection"
    echo -e "  ${RED}prefix${NC} + ${LYELLOW}p${NC}   paste buffer\n"

    echo -e "${BOLD}${LCYAN}Bypass tmux for select/copy/paste${NC}"
    echo -e "  Hold ${LYELLOW}Shift${NC} while selecting/copying/pasting\n"
}

show-help
