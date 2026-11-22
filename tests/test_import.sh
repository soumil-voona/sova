#!/usr/bin/env bash
#test_import.sh
#
# Tests for import "FILE": paths, nested imports, files read once, skipped
# asks, errors inside imported files, and imports at the REPL.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# write PATH TEXT: creates $WORK/PATH containing TEXT.
write() {
    mkdir -p "$(dirname "$WORK/$1")"
    printf '%s\n' "$2" > "$WORK/$1"
}

# check_import NAME FLAGS MAIN_FILE EXPECTED [INPUT]
# Runs ./sova FLAGS on $WORK/MAIN_FILE from another folder (so relative paths
# can't be found by accident) and compares stdout+stderr to EXPECTED. With
# INPUT, it is piped in (for -i).
check_import() {
    local name="$1" flags="$2" main="$3" expected="$4" input="${5-}" actual
    # shellcheck disable=SC2086 # flags is intentionally word-split
    actual="$(cd / && printf '%s\n' "$input" | "$SOVA" $flags "$WORK/$main" 2>&1)"
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

write lib/family.sova 'fact parent("Ada", "Ben")
fact parent("Ben", "Cy")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
ask parent("Ada", "Ben")
expect parent("Ada", "Ben")
hint "not shown"'

write main.sova 'import "lib/family.sova"
ask grandparent("Ada", who)'
check_import "Facts and rules come from the imported file" "--brief" main.sova \
'ask grandparent("Ada", who)
  who = "Cy"
  TRUE'

write after_rule.sova 'rule child(c, p):
    parent(p, c)
import "lib/family.sova"
ask child(who, "Ben")'
check_import "An import ends the rule before it" "--brief" after_rule.sova \
'ask child(who, "Ben")
  who = "Cy"
  TRUE'

write lib/kids.sova 'import "family.sova"
fact parent("Cy", "Dee")'
write nested.sova 'import "lib/kids.sova"
ask grandparent("Ben", who)'
check_import "Nested imports are relative to the importing file" "--brief" nested.sova \
'ask grandparent("Ben", who)
  who = "Dee"
  TRUE'

write twice.sova 'import "lib/family.sova"
import "lib/../lib/family.sova"
import "lib/kids.sova"
ask parent(p, c)'
check_import "Each file is read once" "--brief" twice.sova \
'ask parent(p, c)
  p = "Ada", c = "Ben"
  p = "Ben", c = "Cy"
  p = "Cy", c = "Dee"
  TRUE'

write lib/a.sova 'import "b.sova"
fact a(1)'
write lib/b.sova 'import "a.sova"
fact b(2)'
write cycle.sova 'import "lib/a.sova"
import "cycle.sova"
ask a(x)
ask b(y)'
check_import "Import cycles stop" "--brief" cycle.sova \
'ask a(x)
  x = 1
  TRUE

ask b(y)
  y = 2
  TRUE'

write abs.sova "import \"$WORK/lib/family.sova\"
ask parent(\"Ben\", who)"
check_import "Absolute paths" "--brief" abs.sova \
'ask parent("Ben", who)
  who = "Cy"
  TRUE'

write kb.sova 'import "lib/family.sova"'
check_import "Imported files show in --kb" "--kb" kb.sova \
"$(cd / && "$SOVA" --kb "$WORK/lib/family.sova" 2>&1)"

write check.sova 'import "lib/family.sova"
expect grandparent("Ada", "Cy")'
actual="$(cd / && "$SOVA" --check "$WORK/check.sova" 2>&1)"
if [[ "$actual" == *"All 1 checks pass."* ]]; then
    echo "[PASS] Imported expect lines aren't checked"
    PASS=$((PASS + 1))
else
    echo "[FAIL] Imported expect lines aren't checked"
    printf '%s\n' "$actual" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
fi

write missing.sova 'fact x(1)
import "lib/nope.sova"'
check_import "Missing file" "" missing.sova \
"Syntax error on line 2: can't import 'lib/nope.sova': no such file"

write unquoted.sova 'import lib/family.sova'
check_import "Path must be quoted" "" unquoted.sova \
'Syntax error on line 1: write the file to import in quotes, like import "family.sova"'

write lib/inner.sova 'fact ok(1)

fact oops('
write lib/outer.sova 'import "inner.sova"'
write broken.sova 'import "lib/outer.sova"'
check_import "Errors name the imported file" "" broken.sova \
'Syntax error in lib/inner.sova, line 3: expected fact predicate and arguments'

write lib/missing_inner.sova 'import "gone.sova"'
write broken2.sova 'import "lib/missing_inner.sova"'
check_import "Missing nested file" "" broken2.sova \
"Syntax error in lib/missing_inner.sova, line 1: can't import 'lib/gone.sova': no such file"

write repl.sova 'fact parent("Cy", "Dee")'
check_import "REPL imports relative to the loaded file" "-i --brief" repl.sova \
'  Added.
ask grandparent("Ben", who)
  who = "Dee"
  TRUE' \
'import "lib/family.sova"
grandparent("Ben", who)'

check_import "REPL loads a file's imports" "-i --brief" main.sova \
'ask grandparent(a, b)
  a = "Ada", b = "Cy"
  TRUE' \
'grandparent(a, b)'

check_import "REPL reports import errors" "-i --brief" repl.sova \
"Syntax error on line 1: can't import 'nope.sova': no such file
ask parent(p, \"Dee\")
  p = \"Cy\"
  TRUE" \
'import "nope.sova"
parent(p, "Dee")'

finish_tests
