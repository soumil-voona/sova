#!/usr/bin/env bash
#lib.sh
#
# Shared helpers for tests. Source this file, call check_output for each case,
# then finish_tests to print the summary and set the exit status.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOVA="$TEST_DIR/../sova"

# Tests run with a lower depth limit than the default (200) so the cases
# that hit it on purpose stay fast. Tests that need more set it themselves.
export SOVA_MAX_DEPTH=100

# Expected outputs are plain text, so color stays off even if the caller
# set SOVA_COLOR.
export SOVA_COLOR=never

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
    # Outputs that mention the file (like --check) show it as FILE.
    actual="${actual//"$temp_file"/FILE}"
    rm -f "$temp_file"

    test_dump "$name" "$actual"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# For updating tests after an intended change in output: with SOVA_TEST_DUMP
# set to a folder, each check saves its actual output there as NAME.txt.
test_dump() {
    [[ -n "$SOVA_TEST_DUMP" ]] || return 0
    printf '%s' "$2" > "$SOVA_TEST_DUMP/${1//\//_}.txt"
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
    test_dump "$name" "$actual"

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
