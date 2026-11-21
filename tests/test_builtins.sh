#!/usr/bin/env bash
#test_builtins.sh
#
# Tests for numbers, comparisons, NOT, constants in rule heads, and
# argument-count warnings.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PEOPLE='fact age("Sam", 17)
fact age("Jo", 30)
fact age("Bob", 45)
fact banned("Bob")
rule adult(x):
    age(x, a)
    AND a >= 18
rule welcome(x):
    adult(x)
    AND NOT banned(x)'

check_output "Numbers match by value" "--brief" \
'fact age("Kit", 007)
ask age(who, 7)' \
'ask age(who, 7)
  who = "Kit"
  TRUE'

check_output "Comparison filters answers" "--brief" \
"$PEOPLE
ask adult(who)" \
'ask adult(who)
  who = "Jo"
  who = "Bob"
  TRUE'

check_output "Each comparison operator" "--brief" \
'fact n(5)
rule lt(x):
    n(x)
    AND x < 6
rule gt(x):
    n(x)
    AND x > 6
rule le(x):
    n(x)
    AND x <= 5
rule ge(x):
    n(x)
    AND x >= 6
rule eq(x):
    n(x)
    AND x == 5
rule ne(x):
    n(x)
    AND x != 5
ask lt(5)
ask gt(5)
ask le(5)
ask ge(5)
ask eq(5)
ask ne(5)' \
'ask lt(5)
  TRUE

ask gt(5)
  FALSE

ask le(5)
  TRUE

ask ge(5)
  FALSE

ask eq(5)
  TRUE

ask ne(5)
  FALSE'

check_output "Negative numbers compare correctly" "--brief" \
'fact temp("Oslo", -3)
fact temp("Rome", 12)
rule freezing(city):
    temp(city, t)
    AND t < 0
ask freezing(c)' \
'ask freezing(c)
  c = "Oslo"
  TRUE'

check_output "!= on strings (siblings are different people)" "--brief" \
'fact parent("Ann", "Sam")
fact parent("Ann", "Jo")
rule sibling(x, y):
    parent(p, x)
    AND parent(p, y)
    AND x != y
ask sibling("Sam", who)' \
'ask sibling("Sam", who)
  who = "Jo"
  TRUE'

check_output "< on strings is an error" "--brief" \
'fact name("a")
rule r(x):
    name(x)
    AND x < "b"
ask r(n)' \
'ask r(n)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'"a" < "b"'"'"' can only compare numbers'

check_output "Comparison before its variable has a value" "--brief" \
'fact age("Jo", 30)
rule r(x):
    a > 18
    AND age(x, a)
ask r(who)' \
'ask r(who)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'a > 18'"'"' needs a value for '"'"'a'"'"' (put the goal that sets it earlier)'

check_output "NOT removes provable answers" "--brief" \
"$PEOPLE
ask welcome(who)" \
'ask welcome(who)
  who = "Jo"
  TRUE'

check_output "NOT of an undefined predicate is true" "--brief" \
'fact p("a")
rule r(x):
    p(x)
    AND NOT q(x)
ask r(x)' \
'ask r(x)
  x = "a"
  TRUE'

check_output "NOT before its variable has a value" "--brief" \
"$PEOPLE
rule early(x):
    NOT banned(x)
    AND age(x, a)
ask early(who)" \
'ask early(who)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'NOT banned(x)'"'"' needs a value for '"'"'x'"'"' (put the goal that sets it earlier)'

check_output "NOT works through rules" "--brief" \
'fact parent("a", "b")
fact person("a")
fact person("b")
rule has_parent(x):
    parent(p, x)
rule root(x):
    person(x)
    AND NOT has_parent(x)
ask root(who)' \
'ask root(who)
  who = "a"
  TRUE'

check_output "Proofs show comparisons and NOT" "" \
"$PEOPLE
ask welcome(\"Jo\")" \
'ask welcome("Jo")

TRUE, because:
  welcome("Jo") is satisfied by:
    welcome(x) if adult(x) AND NOT banned(x)

  Variable bindings:
    x = "Jo"

  Proof:
    adult("Jo") is satisfied by:
      adult(x) if age(x, a) AND a >= 18

    Variable bindings:
      x = "Jo"
      a = 30

    Proof:
      age("Jo", 30) is a fact.
      30 >= 18 is true.

    NOT banned("Jo"): banned("Jo") can'"'"'t be proved.'

check_output "FALSE explains comparisons and NOT" "" \
"$PEOPLE
ask welcome(\"Bob\")
ask welcome(\"Sam\")" \
'ask welcome("Bob")

FALSE, because:

  Tried:
    welcome(x) if adult(x) AND NOT banned(x)

  First goal:
    adult("Bob")

    Matched: by the rule for adult.

  Second goal:
    NOT banned("Bob")

    FAILED:
      banned("Bob") can be proved.

ask welcome("Sam")

FALSE, because:

  Tried:
    welcome(x) if adult(x) AND NOT banned(x)

  First goal:
    adult("Sam")

    Tried:
      adult(x) if age(x, a) AND a >= 18

    First goal:
      age("Sam", a)

      Matched:
        a = 17

    Second goal:
      17 >= 18

      FAILED:
        17 >= 18 is false.'

check_output "Constants in a rule head" "--brief" \
'fact tasty("pizza")
rule likes("Sam", food):
    tasty(food)
ask likes(who, what)
ask likes("Jo", "pizza")' \
'ask likes(who, what)
  who = "Sam", what = "pizza"
  TRUE

ask likes("Jo", "pizza")
  FALSE'

check_output "Argument-count warning" "--brief" \
'fact parent("a", "b")
fact parent("a", "b", "c")
ask parent("a", "b")' \
'Warning: '"'"'parent'"'"' is used with different numbers of arguments (2, 3)
ask parent("a", "b")
  TRUE'

check_output "No warning when counts agree" "--brief" \
'fact parent("a", "b")
rule g(x, z):
    parent(x, y)
    AND parent(y, z)
    AND x != z
ask g("a", w)' \
'ask g("a", w)
  FALSE'

finish_tests
