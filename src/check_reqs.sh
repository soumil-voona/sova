#check_reqs.sh
# shellcheck shell=bash
check_reqs() {
    file_path=$1
    if [[ -z "$file_path" ]]; then
        echo "${C_BOLD}${C_RED}Missing file path${C_RESET}"
        exit 1
    fi
    if [[ ! -f "$file_path" ]]; then
        echo "${C_BOLD}${C_RED}Error:${C_RESET} File '$file_path' does not exist"
        exit 1
    fi
}