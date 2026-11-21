#!/usr/bin/env bash
#test_install.sh
#
# Tests that ./sova finds its src/ folder however it is started: through an
# absolute symlink, a relative symlink, a chain of symlinks, a folder name
# with spaces, from PATH, and from another working directory.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REAL_SOVA="$(cd "$TEST_DIR/.." && pwd)/sova"
LINK_DIR="$(mktemp -d)"
trap 'rm -rf "$LINK_DIR"' EXIT

mkdir -p "$LINK_DIR/abs" "$LINK_DIR/rel" "$LINK_DIR/with space"
ln -s "$REAL_SOVA" "$LINK_DIR/abs/sova"
ln -s ../abs/sova "$LINK_DIR/rel/sova"
ln -s ../rel/sova "$LINK_DIR/with space/sova"

PROGRAM='fact parent("Ada", "Ben")
ask parent("Ada", who)'
EXPECTED='ask parent("Ada", who)
  who = "Ben"
  TRUE'

SOVA="$REAL_SOVA"
check_output "install/direct" "--brief" "$PROGRAM" "$EXPECTED"

SOVA="$LINK_DIR/abs/sova"
check_output "install/absolute symlink" "--brief" "$PROGRAM" "$EXPECTED"

SOVA="$LINK_DIR/rel/sova"
check_output "install/relative symlink" "--brief" "$PROGRAM" "$EXPECTED"

SOVA="$LINK_DIR/with space/sova"
check_output "install/chained symlink, path with spaces" "--brief" "$PROGRAM" "$EXPECTED"

# From PATH, run from another folder.
cd "$LINK_DIR" || exit 1
SOVA="sova"
PATH="$LINK_DIR/rel:$PATH" check_output "install/from PATH in another folder" "--brief" "$PROGRAM" "$EXPECTED"

# check_true NAME COMMAND...: passes when COMMAND succeeds.
check_true() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        FAIL=$((FAIL + 1))
    fi
}

# install.sh, run against a throwaway HOME so it never touches the real one.
CLONE="$(cd "$TEST_DIR/.." && pwd)"
FAKE_HOME="$LINK_DIR/home"
mkdir -p "$FAKE_HOME"
run_install() { HOME="$FAKE_HOME" SOVA_HOME="" SOVA_BIN_DIR="" bash "$@"; }
INSTALLED="$FAKE_HOME/.local/share/sova"
LINKED="$FAKE_HOME/.local/bin/sova"

check_true "install.sh/from a clone" run_install "$CLONE/install.sh"
check_true "install.sh/makes the link" test -L "$LINKED"
check_true "install.sh/copies examples and exercises" test -f "$INSTALLED/examples/family.sova" -a -d "$INSTALLED/exercises"
SOVA="$LINKED"
check_output "install.sh/installed sova runs" "--brief" "$PROGRAM" "$EXPECTED"
check_true "install.sh/runs again to update" run_install "$CLONE/install.sh"

# Hints name the command "sova" when it was found on PATH.
mkdir -p "$LINK_DIR/work"
cd "$LINK_DIR/work" || exit 1
hint="$(PATH="$FAKE_HOME/.local/bin:$PATH" sova --start 1 2>&1 | tail -1)"
check_true "install.sh/--start hint says sova when on PATH" test "$hint" = "  sova --check my-exercises/01-facts.sova"
cd "$LINK_DIR" || exit 1

check_true "install.sh/--uninstall" run_install "$CLONE/install.sh" --uninstall
check_true "install.sh/uninstall removes the folder" test ! -e "$INSTALLED"
check_true "install.sh/uninstall removes the link" test ! -L "$LINKED"

# Piped (curl | bash): there is no script file, so it downloads SOVA_URL.
tar -czf "$LINK_DIR/sova.tar.gz" -C "$(dirname "$CLONE")" \
    "$(basename "$CLONE")/sova" "$(basename "$CLONE")/src" \
    "$(basename "$CLONE")/examples" "$(basename "$CLONE")/exercises"
piped_install() { HOME="$FAKE_HOME" SOVA_URL="file://$LINK_DIR/sova.tar.gz" bash < "$CLONE/install.sh"; }
check_true "install.sh/piped download" piped_install
check_true "install.sh/piped install runs" "$LINKED" --brief "$INSTALLED/examples/family.sova"
run_install "$CLONE/install.sh" --uninstall >/dev/null 2>&1

# Refuses to replace a folder that isn't a Sova install.
mkdir -p "$LINK_DIR/not-sova"
touch "$LINK_DIR/not-sova/keep"
HOME="$FAKE_HOME" SOVA_HOME="$LINK_DIR/not-sova" bash "$CLONE/install.sh" >/dev/null 2>&1
check_true "install.sh/won't overwrite another folder" test -f "$LINK_DIR/not-sova/keep"

# Uninstall leaves a hand-made link to a clone alone.
mkdir -p "$FAKE_HOME/.local/bin"
ln -sf "$CLONE/sova" "$LINKED"
run_install "$CLONE/install.sh" --uninstall >/dev/null 2>&1
check_true "install.sh/uninstall keeps a link to a clone" test -L "$LINKED"

finish_tests
