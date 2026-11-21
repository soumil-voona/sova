#!/usr/bin/env bash
#test_exercises.sh
#
# Tests for the exercises and the checker: every exercise fails as given
# and passes with its reference solution (tests/exercise_solutions/), the
# checker explains failures, and --exercises / --start manage copies.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXERCISES="$TEST_DIR/../exercises"
SOLUTIONS="$TEST_DIR/exercise_solutions"
WORK=$(mktemp -d)

# solved EXERCISE SOLUTION OUT: the exercise with the solution written where
# it says "below this line", as a learner would.
solved() {
    awk -v sol="$2" '{print} /below this line\./{while((getline l < sol)>0) print l}' "$1" > "$3"
}

pass() {
    echo "[PASS] $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "[FAIL] $1"
    [[ -n "$2" ]] && printf '%s\n' "$2" | sed 's/^/    /'
    FAIL=$((FAIL + 1))
}

for exercise in "$EXERCISES"/*.sova; do
    name="$(basename "$exercise")"
    number="${name%%-*}"
    solution="$SOLUTIONS/$number.sova"
    if [[ ! -f "$solution" ]]; then
        fail "$name has a reference solution"
        continue
    fi
    if "$SOVA" --check "$exercise" > /dev/null 2>&1; then
        fail "$name fails before it's solved"
    else
        pass "$name fails before it's solved"
    fi
    solved "$exercise" "$solution" "$WORK/solved.sova"
    output="$("$SOVA" --check "$WORK/solved.sova" 2>&1)"
    if [[ "$?" -eq 0 && "$output" == *"checks pass."* && "$output" != *"✗"* ]]; then
        pass "$name passes with its reference solution"
    else
        fail "$name passes with its reference solution" "$output"
    fi
done

CHECKS='fact parent("Ada", "Ben")
rule child(c, p):
    parent(p, c)
hint "A child c of p means p is a parent of c."
expect child("Ben", "Ada")
expect NOT child("Ada", "Ben")
expect child(who, "Ada") gives "Ben"
expect parent(a, b) gives ("Ada", "Ben")
expect child(c, p) gives ("Ben", "Ada"), ("Fay", "Ada")'

check_output "Checker output: passes, a missing answer, and hints" "--check" "$CHECKS" \
"Checking FILE

  ✓ child(\"Ben\", \"Ada\") is true
  ✓ child(\"Ada\", \"Ben\") is false
  ✓ child(who, \"Ada\") gives \"Ben\"
  ✓ parent(a, b) gives (\"Ada\", \"Ben\")
  ✗ child(c, p) gives (\"Ben\", \"Ada\"), (\"Fay\", \"Ada\")
      Sova gave: (\"Ben\", \"Ada\")
      Missing: (\"Fay\", \"Ada\")

4 of 5 checks pass.
Hint: A child c of p means p is a parent of c."

check_output "Checker output: something true that should be false" "--check" \
'fact parent("Ada", "Ben")
rule child(c, p):
    parent(c, p)
expect NOT child("Ada", "Ben")' \
'Checking FILE

  ✗ child("Ada", "Ben") is false
      But Sova can prove it:
        child("Ada", "Ben") is satisfied by:
          child(c, p) if parent(c, p)

        Variable bindings:
          c = "Ada"
          p = "Ben"

        Proof:
          parent("Ada", "Ben") is a fact.

0 of 1 checks pass.'

check_output "Checker output: nothing written yet" "--check" \
'expect grandparent("Ada", "Cy")
expect NOT grandparent("Ben", "Cy")' \
"Checking FILE

Nothing defines 'grandparent' yet: write it where the file says.

  ✗ grandparent(\"Ada\", \"Cy\") is true
  ✗ grandparent(\"Ben\", \"Cy\") is false

0 of 2 checks pass."

check_output "Checker output: errors and unexpected answers" "--check" \
'fact n(1)
fact n(2)
rule big(x):
    x > 1
    AND n(x)
rule any(x):
    n(x)
expect big(x) gives 2
expect any(x) gives 1' \
"Checking FILE

  ✗ big(x) gives 2
      Sova found no answers.
      Error: 'x > 1' needs a value for 'x' (put the goal that sets it earlier)
  ✗ any(x) gives 1
      Sova gave: 1, 2
      Not expected: 2

0 of 2 checks pass."

check_output "All passing suggests --compare" "--check" \
'fact parent("Ada", "Ben")
rule child(c, p):
    parent(p, c)
expect child("Ben", "Ada")' \
"Checking FILE

  ✓ child(\"Ben\", \"Ada\") is true

All 1 checks pass.
See your rule written as code: ./sova --compare child FILE"

check_output "A file without checks" "--check" 'fact a("b")' \
"FILE has no expect lines to check."

check_output "Bad expect lines are syntax errors" "--check" \
'expect parent(a, b) gives "Ada"' \
"Syntax error on line 1: with 2 variables, write each answer in parentheses, like (\"a\", 1)"

check_output "Normal runs ignore expect and hint lines" "--brief" \
'fact a("b")
hint "x"
expect a("b")
ask a(x)' \
'ask a(x)
  x = "b"
  TRUE'

# --exercises and --start, in a fresh work folder.
export SOVA_EXERCISE_DIR="$WORK/mine"
listing="$("$SOVA" --exercises)"
if [[ "$listing" == *" 3  AND "*"not started"* && "$listing" == *"10  Putting it together"* ]]; then
    pass "--exercises lists every exercise"
else
    fail "--exercises lists every exercise" "$listing"
fi

started="$("$SOVA" --start 3)"
if [[ -f "$WORK/mine/03-and.sova" && "$started" == *"Created"* ]]; then
    pass "--start copies an exercise"
else
    fail "--start copies an exercise" "$started"
fi

listing="$("$SOVA" --exercises)"
if [[ "$listing" == *" 3  AND"*"0 of 6 checks pass"* ]]; then
    pass "--exercises shows progress"
else
    fail "--exercises shows progress" "$listing"
fi

solved "$WORK/mine/03-and.sova" "$SOLUTIONS/03.sova" "$WORK/solved.sova"
cp "$WORK/solved.sova" "$WORK/mine/03-and.sova"
listing="$("$SOVA" --exercises)"
if [[ "$listing" == *" 3  AND"*"done"* ]]; then
    pass "--exercises shows finished exercises"
else
    fail "--exercises shows finished exercises" "$listing"
fi

again="$("$SOVA" --start 3)"
if [[ "$again" == *"already have"* ]] && cmp -s "$WORK/solved.sova" "$WORK/mine/03-and.sova"; then
    pass "--start never overwrites your work"
else
    fail "--start never overwrites your work" "$again"
fi

missing="$("$SOVA" --start 99 2>&1)"
if [[ "$missing" == "There is no exercise 99."* ]]; then
    pass "--start with an unknown number"
else
    fail "--start with an unknown number" "$missing"
fi

rm -rf "$WORK"
finish_tests
