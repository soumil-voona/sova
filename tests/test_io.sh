#!/usr/bin/env bash
#test_io.sh
#
# Tests for print, read, and read_number: output order, values, the end of
# the input, errors, explanations, and reading at the interactive prompt.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# check_input NAME FLAGS SOURCE INPUT EXPECTED: like check_output, with
# INPUT piped in.
check_input() {
    local name="$1" flags="$2" source="$3" input="$4" expected="$5"
    local temp_file actual
    temp_file=$(mktemp)
    printf '%s\n' "$source" > "$temp_file"
    # shellcheck disable=SC2086 # flags is intentionally word-split
    actual="$(printf '%s' "$input" | "$SOVA" $flags "$temp_file" 2>&1)"
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

check_input "print writes values without quotes" "--brief" \
'rule show(x):
    x = 2.5
    AND print("x is", x, [1, "a"], [])
ask show(v)' '' \
'ask show(v)
x is 2.5 [1, "a"] []
  v = 2.5
  TRUE'

check_input "print runs for every answer" "--brief" \
'fact pet("Mochi")
fact pet("Rex")
rule show(p):
    pet(p)
    AND print("trying", p)
    AND p != "Rex"
ask show(p)' '' \
'ask show(p)
trying Mochi
trying Rex
  p = "Mochi"
  TRUE'

check_input "print needs its values" "--brief" \
'rule bad(x):
    print(x)
ask bad(y)' '' \
"ask bad(y)
  UNKNOWN: some goals could not be checked
  ERROR: 'print(x)' needs a value for 'x' (put the goal that sets it earlier)"

check_input "print with several values is no arity warning" "--brief" \
'rule a(x):
    print(x)
    AND print(x, x)
ask a(1)' '' \
'ask a(1)
1
1 1
  TRUE'

check_input "read gives a line as text" "--brief" \
'rule greet(m):
    read(name)
    AND concat("Hi ", name, m)
ask greet(m)
ask greet(m)' $'Ada Lovelace\n  spaced  \n' \
'ask greet(m)
  m = "Hi Ada Lovelace"
  TRUE

ask greet(m)
  m = "Hi   spaced  "
  TRUE'

check_input "read is false at the end of the input" "" \
'rule greet(name):
    read(name)
ask greet(n)' '' \
'ask greet(n)

FALSE, because:

  Tried:
    greet(name) if read(name)

  First goal:
    read(name)

    FAILED:
      There is no more input to read.'

check_input "read reads a last line with no newline" "--brief" \
'rule r(x):
    read(x)
ask r(x)' 'last' \
'ask r(x)
  x = "last"
  TRUE'

check_input "read_number reads whole numbers and decimals" "--brief" \
'rule add(t):
    read_number(a)
    AND read_number(b)
    AND t = a + b
ask add(t)' $' 3 \n0.25\n' \
'ask add(t)
  t = 3.25
  TRUE'

check_input "read_number reports a line that isn't a number" "--brief" \
'rule n(x):
    read_number(x)
ask n(x)' $'seven\n' \
"ask n(x)
  UNKNOWN: some goals could not be checked
  ERROR: 'read_number(x)' read \"seven\", which isn't a number"

check_input "read checks a known value" "--brief" \
'rule said(w):
    read(w)
ask said("yes")
ask said("yes")' $'yes\nno\n' \
'ask said("yes")
  TRUE

ask said("yes")
  FALSE'

check_input "Proofs show what was read and printed" "" \
'rule echo(x):
    read(x)
    AND print(x)
ask echo(x)' $'hi\n' \
'ask echo(x)
hi

TRUE:
  x = "hi"

  Because echo("hi") is satisfied by:
    echo(x) if read(x) AND print(x)

  Variable bindings:
    x = "hi"

  Proof:
    read("hi") is true (built-in).
    print("hi") is true (built-in).'

check_input "A program's own print replaces the built-in" "--brief" \
'fact print("defined")
ask print(x)' '' \
'ask print(x)
  x = "defined"
  TRUE'

check_repl "read at the prompt takes the next line" "--brief" \
'rule greet(m):
    read(name)
    AND concat("Hi ", name, m)' \
'greet(m)
Sam
print("after")' \
'ask greet(m)
  m = "Hi Sam"
  TRUE
ask print("after")
after
  TRUE'

finish_tests
