#!/usr/bin/env bash
#run_all.sh
#
# Usage: tests/run_all.sh
# Runs every tests/test_*.sh file and exits non-zero if any of them failed.

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=()

for test_file in "$TEST_DIR"/test_*.sh; do
    echo "== $(basename "$test_file")"
    bash "$test_file" || failed+=("$(basename "$test_file")")
    echo
done

if [[ "${#failed[@]}" -eq 0 ]]; then
    echo "All test files passed."
else
    echo "Failed: ${failed[*]}"
    exit 1
fi
