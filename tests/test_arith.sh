#!/usr/bin/env bash
#test_arith.sh
#
# Tests for arithmetic: calculations with =, expressions in comparisons,
# precedence, whole-number division, errors, and small algorithms.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_output "Precedence and grouping" "--brief" \
'rule calc(a, b, c, d, e):
    a = 2 + 3 * 4
    AND b = (2 + 3) * 4
    AND c = 10 - 4 - 3
    AND d = 2 * -3
    AND e = -(2 + 3)
ask calc(a, b, c, d, e)' \
'ask calc(a, b, c, d, e)
  a = 14, b = 20, c = 3, d = -6, e = -5
  TRUE'

check_output "Division and remainder round down" "--brief" \
'rule divs(a, b, q, r):
    q = a / b
    AND r = a % b
ask divs(7, 2, q, r)
ask divs(-7, 2, q, r)
ask divs(7, -2, q, r)
ask divs(-7, -2, q, r)' \
'ask divs(7, 2, q, r)
  q = 3, r = 1
  TRUE

ask divs(-7, 2, q, r)
  q = -4, r = 1
  TRUE

ask divs(7, -2, q, r)
  q = -4, r = -1
  TRUE

ask divs(-7, -2, q, r)
  q = 3, r = -1
  TRUE'

check_output "= gives an unknown side a value, on either side" "--brief" \
'rule double(x, y):
    y = x * 2
rule triple(x, y):
    x * 3 = y
ask double(21, y)
ask triple(4, y)' \
'ask double(21, y)
  y = 42
  TRUE

ask triple(4, y)
  y = 12
  TRUE'

check_output "= checks when both sides are known" "--brief" \
'rule double(x, y):
    y = x * 2
ask double(21, 42)
ask double(21, 43)' \
'ask double(21, 42)
  TRUE

ask double(21, 43)
  FALSE'

check_output "= matches text too" "--brief" \
'rule greeting(who, word):
    word = "hello"
    AND who != word
ask greeting("Sam", w)' \
'ask greeting("Sam", w)
  w = "hello"
  TRUE'

check_output "Expressions in comparisons" "--brief" \
'fact score("Ana", 7)
fact score("Ben", 3)
rule close(x, y):
    score(x, a)
    AND score(y, b)
    AND x != y
    AND a - b <= 4
    AND a + b > 9
ask close(x, y)' \
'ask close(x, y)
  x = "Ana", y = "Ben"
  x = "Ben", y = "Ana"
  TRUE'

check_output "Calculation before its values are known" "--brief" \
'rule r(x, y):
    y = x + 1
ask r(a, b)' \
'ask r(a, b)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'y = x + 1'"'"' needs a value for '"'"'x'"'"' (put the goal that sets it earlier)'

check_output "Dividing by zero" "--brief" \
'rule r(x, y):
    y = 10 / x
ask r(0, y)' \
'ask r(0, y)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'y = 10 / x'"'"' divides by zero'

check_output "Arithmetic on text" "--brief" \
'fact name("Sam")
rule r(y):
    name(n)
    AND y = n + 1
ask r(y)' \
'ask r(y)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'y = n + 1'"'"' needs a number for '"'"'n'"'"', but it is "Sam"'

check_output "Proofs show calculations with their values" "" \
'rule area(w, h, a):
    a = w * h
    AND a > 0
    AND unit = "m2"
ask area(3, 4, a)' \
'ask area(3, 4, a)

TRUE:
  a = 12

  Because area(3, 4, 12) is satisfied by:
    area(w, h, a) if a = w * h AND a > 0 AND unit = "m2"

  Variable bindings:
    a = 12
    w = 3
    h = 4
    unit = "m2"

  Proof:
    a = 3 * 4 = 12 (calculated).
    12 > 0 is true.
    unit = "m2".'

check_output "False calculations are dead ends" "" \
'rule r(x):
    x * 2 = 10
ask r(4)' \
'ask r(4)

FALSE, because:

  Tried:
    r(x) if x * 2 = 10

  First goal:
    4 * 2 = 10

    FAILED:
      4 * 2 is 8, not 10.'

check_output "Factorial" "--brief" \
'fact factorial(0, 1)
rule factorial(n, f):
    n > 0
    AND m = n - 1
    AND factorial(m, g)
    AND f = n * g
ask factorial(10, f)
ask factorial(5, 120)' \
'ask factorial(10, f)
  f = 3628800
  TRUE

ask factorial(5, 120)
  TRUE'

# 27 takes 111 steps, so this needs the real default depth limit.
SOVA_MAX_DEPTH=200 check_output "Collatz steps" "--brief" \
'fact steps(1, 0)
rule steps(n, s):
    n > 1
    AND n % 2 == 0
    AND m = n / 2
    AND steps(m, t)
    AND s = t + 1
rule steps(n, s):
    n > 1
    AND n % 2 == 1
    AND m = 3 * n + 1
    AND steps(m, t)
    AND s = t + 1
ask steps(6, s)
ask steps(27, s)' \
'ask steps(6, s)
  s = 8
  TRUE

ask steps(27, s)
  s = 111
  TRUE'

check_output "Greatest common divisor" "--brief" \
'fact gcd(a, 0, a)
rule gcd(a, b, g):
    b > 0
    AND r = a % b
    AND gcd(b, r, g)
ask gcd(48, 18, g)
ask gcd(17, 5, g)' \
'ask gcd(48, 18, g)
  g = 6
  TRUE

ask gcd(17, 5, g)
  g = 1
  TRUE'

check_output "Long computations aren't stopped by the depth limit" "--brief" \
'fact fib(0, 0)
fact fib(1, 1)
rule fib(n, f):
    n > 1
    AND a = n - 1
    AND b = n - 2
    AND fib(a, fa)
    AND fib(b, fb)
    AND f = fa + fb
ask fib(12, f)' \
'ask fib(12, f)
  f = 144
  TRUE'

finish_tests
