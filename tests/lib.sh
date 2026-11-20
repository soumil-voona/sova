#!/usr/bin/env bash
#lib.sh
#
# Shared helpers for tests. Source this file, call check_output for each case,
# then finish_tests to print the summary and set the exit status.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOVA="$TEST_DIR/../sova"

PASS=0
FAIL=0

# check_output NAME SOVA_FLAGS SOURCE EXPECTED
# Runs ./sova with SOVA_FLAGS on SOURCE and compares stdout+stderr to EXPECTED.
check_output() {
    local name="$1" flags="$2" source="$3" expected="$4"
    local temp_file actual
    temp_file=$(mktemp)
    printf '%s\n' "$source" > "$temp_file"

    # shellcheck disable=SC2086 # flags is intentionally word-split
    actual="$("$SOVA" $flags "$temp_file" 2>&1)"
    rm -f "$temp_file"

    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# check_repl NAME FLAGS SOURCE INPUT EXPECTED
# Starts ./sova -i FLAGS on SOURCE (no file if SOURCE is empty), types INPUT,
# and compares stdout+stderr to EXPECTED.
check_repl() {
    local name="$1" flags="$2" source="$3" input="$4" expected="$5"
    local temp_file="" actual
    if [[ -n "$source" ]]; then
        temp_file=$(mktemp)
        printf '%s\n' "$source" > "$temp_file"
    fi

    # shellcheck disable=SC2086 # flags is intentionally word-split
    actual="$(printf '%s\n' "$input" | "$SOVA" -i $flags $temp_file 2>&1)"
    [[ -n "$temp_file" ]] && rm -f "$temp_file"

    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

finish_tests() {
    echo
    echo "Results: $PASS passed, $FAIL failed"
    [[ "$FAIL" -eq 0 ]]
}
