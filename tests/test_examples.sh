#!/usr/bin/env bash
#test_examples.sh
#
# Golden-output tests: for every examples/NAME.sova that has a matching
# examples/NAME.expected, run ./sova on it and diff against the expected output.
# An example that reads input gets examples/NAME.input (or no input at all).
# To update a golden file after an intended change:
#   ./sova examples/NAME.sova < examples/NAME.input > examples/NAME.expected

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXAMPLES_DIR="$TEST_DIR/../examples"

for source_file in "$EXAMPLES_DIR"/*.sova; do
    expected_file="${source_file%.sova}.expected"
    name="$(basename "$source_file")"
    if [[ ! -f "$expected_file" ]]; then
        echo "[SKIP] $name (no .expected file)"
        continue
    fi
    input_file="${source_file%.sova}.input"
    [[ -f "$input_file" ]] || input_file=/dev/null
    if diff -u "$expected_file" <("$SOVA" "$source_file" < "$input_file" 2>&1) > /dev/null; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff -u "$expected_file" <("$SOVA" "$source_file" < "$input_file" 2>&1) | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
done

finish_tests
