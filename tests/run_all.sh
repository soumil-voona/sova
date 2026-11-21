#!/usr/bin/env bash
#run_all.sh
#
# Usage: tests/run_all.sh [SUITE...]
# Runs every tests/test_*.sh file, or only the named suites (test_rules or
# rules both work), and exits non-zero if any of them failed.
#
# With SOVA_TEST_STRICT=1 (as CI sets it), a suite that prints [SKIP]
# because python3 or node is missing counts as a failure.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=()
skipped=()
passed=0
failed_cases=0

if [[ "$#" -eq 0 ]]; then
    test_files=("$TEST_DIR"/test_*.sh)
else
    test_files=()
    for suite in "$@"; do
        suite="${suite%.sh}"
        suite="test_${suite#test_}"
        if [[ ! -f "$TEST_DIR/$suite.sh" ]]; then
            echo "No such test suite: $suite" >&2
            exit 2
        fi
        test_files+=("$TEST_DIR/$suite.sh")
    done
fi

for test_file in "${test_files[@]}"; do
    name="$(basename "$test_file")"
    echo "== $name"
    output="$(bash "$test_file" 2>&1)"
    status=$?
    printf '%s\n' "$output"
    [[ "$status" -eq 0 ]] || failed+=("$name")
    [[ "$output" == *"[SKIP]"* ]] && skipped+=("$name")
    if [[ "$output" =~ Results:\ ([0-9]+)\ passed,\ ([0-9]+)\ failed ]]; then
        passed=$((passed + BASH_REMATCH[1]))
        failed_cases=$((failed_cases + BASH_REMATCH[2]))
    fi
    echo
done

echo "Total: $passed passed, $failed_cases failed"
if [[ "${#skipped[@]}" -gt 0 ]]; then
    echo "Skipped: ${skipped[*]}"
    [[ "$SOVA_TEST_STRICT" == 1 ]] && failed+=("${skipped[@]}")
fi

if [[ "${#failed[@]}" -eq 0 ]]; then
    echo "All test files passed."
else
    echo "Failed: ${failed[*]}"
    exit 1
fi
