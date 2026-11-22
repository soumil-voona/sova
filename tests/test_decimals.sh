#!/usr/bin/env bash
#test_decimals.sh
#
# Tests for decimal numbers: how they are written, exact arithmetic,
# division, comparisons, matching, errors, and the token view.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# calc EXPRESSION... -> a program asking for each expression's value.
calc() {
    local expression i=0 out=""
    for expression in "$@"; do
        out+="rule c$i(v):"$'\n'"    v = $expression"$'\n'"ask c$i(v)"$'\n'
        i=$((i + 1))
    done
    printf '%s' "$out"
}

# values EXPRESSION...: the answers calc's program gives, one per line.
values() {
    local temp_file
    temp_file=$(mktemp)
    calc "$@" > "$temp_file"
    "$SOVA" --brief "$temp_file" 2>&1 | grep -E '^  (v = |UNKNOWN|ERROR)' | sed 's/^  //'
    rm -f "$temp_file"
}

# check_values NAME EXPECTED EXPRESSION...
check_values() {
    local name="$1" expected="$2" actual
    shift 2
    actual="$(values "$@")"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

check_values "Decimals are written in a standard form" \
'v = 2.5
v = 3.0
v = 0.5
v = -0.25
v = 0.0
v = 7' \
'02.50' '3.000' '0.50 + 0' '-0.250' '-0.0' '007'

check_values "Exact addition and subtraction" \
'v = 0.3
v = 3.25
v = -0.5
v = 0.0' \
'0.1 + 0.2' '3 + 0.25' '0.5 - 1' '1.5 - 1.5'

check_values "Multiplication keeps a decimal a decimal" \
'v = 5.0
v = -1.5
v = 0.0001
v = 6' \
'2.5 * 2' '-0.5 * 3' '0.01 * 0.01' '2 * 3'

check_values "Division" \
'v = 0.25
v = 0.3333333333
v = 0.6666666667
v = -3.75
v = 2.0
v = 3
v = -4' \
'1 / 4.0' '1 / 3.0' '2 / 3.0' '-7.5 / 2' '5.0 / 2.5' '7 / 2' '-7 / 2'

check_values "Remainders round the quotient down" \
'v = 1.5
v = 0.5
v = 1' \
'7.5 % 2' '-1.5 % 2' '7 % 3'

check_values "Precedence, grouping, and minus" \
'v = 6.25
v = 0.5
v = -2.5' \
'(3 + 0.25) * 2 - 0.25' '-(0.5 - 1)' '-(2.5)'

check_values "Errors" \
"UNKNOWN: some goals could not be checked
ERROR: 'v = 1.5 / 0' divides by zero
UNKNOWN: some goals could not be checked
ERROR: 'v = 2.5 % 0.0' divides by zero
UNKNOWN: some goals could not be checked
ERROR: 'v = 999999999999.5 * 99999999.5' gives a number too big for Sova (decimals can have up to 18 digits)" \
'1.5 / 0' '2.5 % 0.0' '999999999999.5 * 99999999.5'

check_output "Comparisons work by value" "--brief" \
'rule checks(x):
    x = 1
    AND 5 == 5.0
    AND 2.5 >= 2.50
    AND 0.1 + 0.2 == 0.3
    AND 1.25 < 2
    AND -0.5 > -1
    AND 3.0 != 3.5
    AND 10 = 5.0 * 2
ask checks(x)' \
'ask checks(x)
  x = 1
  TRUE'

check_output "A false comparison" "--brief" \
'rule cheap(p):
    p = 4.5
    AND p < 4
ask cheap(p)' \
'ask cheap(p)
  FALSE'

check_output "Decimals in facts" "--brief" \
'fact price("tea", 2.50)
fact price("cake", 3.75)
rule total(t):
    price("tea", a)
    AND price("cake", b)
    AND t = a + b
ask price(x, 2.5)
ask total(t)' \
'ask price(x, 2.5)
  x = "tea"
  TRUE

ask total(t)
  t = 6.25
  TRUE'

check_output "5 and 5.0 don't match in facts" "--brief" \
'fact size(5)
ask size(5.0)
ask size(5)' \
'ask size(5.0)
  FALSE

ask size(5)
  TRUE'

check_output "Explaining a wrong decimal calculation" "" \
'rule check(x):
    x = 2.5
    AND 4 = x * 2
ask check(x)' \
'ask check(x)

FALSE, because:

  Tried:
    check(x) if x = 2.5 AND 4 = x * 2

  First goal:
    x = 2.5

    Matched:
      x = 2.5

  Second goal:
    4 = 2.5 * 2

    FAILED:
      2.5 * 2 is 5.0, not 4.'

check_output "A decimal that isn't a number" "--brief" \
'rule r(v):
    x = "2.5"
    AND v = x + 1
ask r(v)' \
"ask r(v)
  UNKNOWN: some goals could not be checked
  ERROR: 'v = x + 1' needs a number for 'x', but it is \"2.5\""

check_output "Decimals in the token view" "--tokens" \
'fact p(2.5, -0.75)' \
'KEYWORD: fact
IDENTIFIER: p
LEFT_PAREN
NUMBER: 2.5
COMMA
NUMBER: -0.75
RIGHT_PAREN'

finish_tests
