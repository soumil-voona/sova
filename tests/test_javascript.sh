#!/usr/bin/env bash
#test_javascript.sh
#
# Runs JavaScript translations with Node.js and checks they print Sova's
# answers. Skipped if node isn't installed. Cases are in translation_lib.sh.

# shellcheck source=tests/translation_lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/translation_lib.sh"

if ! command -v node > /dev/null; then
    echo "[SKIP] node is not installed"
    finish_tests
    exit $?
fi

TRANSLATE_FLAG="--javascript"
RUN_PROGRAM="node"
CHECK_PROGRAM="node --check"
PROGRAM_EXT=".js"
run_translation_tests
finish_tests
