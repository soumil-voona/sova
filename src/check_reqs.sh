#check_reqs.sh
# shellcheck shell=bash
check_reqs() {
    file_path=$1
    if [[ -z "$file_path" ]]; then
        echo "Missing file path"
        exit 1
    fi
    if [[ ! -f "$file_path" ]]; then
        echo "Error: File '$file_path' does not exist"
        exit 1
    fi
}