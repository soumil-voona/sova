#!/usr/bin/env bash
#test_functional.sh
#
# Runs functional-style Python translations (list comprehensions) and checks
# they print Sova's answers. Skipped if python3 isn't installed. Cases are in
# translation_lib.sh.

# shellcheck source=tests/translation_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/translation_lib.sh"

if ! command -v python3 > /dev/null; then
    echo "[SKIP] python3 is not installed"
    finish_tests
    exit $?
fi

TRANSLATE_FLAG="--functional"
RUN_PROGRAM="python3 -I"
CHECK_PROGRAM="python3 -I -m py_compile"
PROGRAM_EXT=".py"
run_translation_tests
finish_tests
