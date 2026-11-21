#!/usr/bin/env bash
#color.sh
#
# Colors for terminal output. Each C_* variable is an ANSI escape code, or
# empty when color is off, so output can always be written as
# "${C_GREEN}TRUE${C_RESET}" and reads the same either way.
#
# Color is on when the output goes to a terminal. SOVA_COLOR=always or
# SOVA_COLOR=never overrides that, and NO_COLOR (https://no-color.org) or
# TERM=dumb turns it off. Standard output and standard error are decided
# separately: C_* is for stdout, E_* for messages written to stderr.
#
# Translated programs (--python, --javascript, ...) are never colored, so
# they can be copied or saved and run as they are.
#
# The variables are used by the other files, which shellcheck sees one at
# a time.
# shellcheck disable=SC2034

# color_enabled FD: whether file descriptor FD should get color.
color_enabled() {
    case "${SOVA_COLOR:-auto}" in
        always) return 0 ;;
        never)  return 1 ;;
    esac
    [[ -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" && -t "$1" ]]
}

color_init() {
    if color_enabled 1; then
        C_RESET=$'\033[0m'
        C_BOLD=$'\033[1m'
        C_DIM=$'\033[2m'
        C_RED=$'\033[31m'
        C_GREEN=$'\033[32m'
        C_YELLOW=$'\033[33m'
        C_BLUE=$'\033[34m'
        C_MAGENTA=$'\033[35m'
        C_CYAN=$'\033[36m'
    else
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW=""
        C_BLUE="" C_MAGENTA="" C_CYAN=""
    fi
    if color_enabled 2; then
        E_RESET=$'\033[0m'
        E_RED=$'\033[1;31m'
        E_YELLOW=$'\033[33m'
    else
        E_RESET="" E_RED="" E_YELLOW=""
    fi
}

color_init
