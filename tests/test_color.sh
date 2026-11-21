#!/usr/bin/env bash
#test_color.sh
#
# Tests for colored output: on with SOVA_COLOR=always, off with
# SOVA_COLOR=never, NO_COLOR, or when output isn't a terminal, and never in
# translated programs.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ESC=$'\033'
FILE="$(mktemp)"
printf '%s\n' 'fact parent("Alex", "Sam")' 'rule child(x, y):' '    parent(y, x)' \
    'ask parent("Alex", "Sam")' 'ask parent("Sam", "Alex")' > "$FILE"

# check_color NAME EXPECT(yes|no) COMMAND...
check_color() {
    local name="$1" want="$2" actual has=no
    shift 2
    actual="$("$@" 2>&1)"
    [[ "$actual" == *"${ESC}["* ]] && has=yes
    if [[ "$has" == "$want" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name (color: wanted $want, got $has)"
        FAIL=$((FAIL + 1))
    fi
}

check_color "always turns color on" yes env SOVA_COLOR=always "$SOVA" "$FILE"
check_color "never turns color off" no env SOVA_COLOR=never "$SOVA" "$FILE"
check_color "no color when piped" no env -u SOVA_COLOR "$SOVA" "$FILE"
check_color "NO_COLOR turns color off" no env -u SOVA_COLOR NO_COLOR=1 "$SOVA" "$FILE"
check_color "python stays plain" no env SOVA_COLOR=always "$SOVA" --python child "$FILE"
check_color "javascript stays plain" no env SOVA_COLOR=always "$SOVA" --javascript child "$FILE"

expected_true="${ESC}[1m${ESC}[32mTRUE${ESC}[0m, because:"
if SOVA_COLOR=always "$SOVA" "$FILE" | grep -qF "$expected_true"; then
    echo "[PASS] TRUE is green"; PASS=$((PASS + 1))
else
    echo "[FAIL] TRUE is green"; FAIL=$((FAIL + 1))
fi

rm -f "$FILE"
finish_tests
