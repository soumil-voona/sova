#!/usr/bin/env bash
#test_lists.sh
#
# Tests for lists: syntax, matching [head | tail], list algorithms,
# comparisons, NOT, and how lists appear in proofs and explanations.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

LISTS="$(grep -v '^ask ' "$TEST_DIR/../examples/lists.sova")"

check_output "Lists in facts, shown as written" "--kb" \
'fact empty([])
fact nums([1, 2, 3])
fact nested([["a", 1], ["b", 2]], [])
fact pattern([h | t])' \
'Facts (4):
  empty([])
  nums([1, 2, 3])
  nested([["a", 1], ["b", 2]], [])
  pattern([h | t])
Rules (0):'

check_output "Matching [head | tail]" "--brief" \
'rule split(l, h, t):
    l = [h | t]
ask split([1, 2, 3], h, t)
ask split([1], h, t)
ask split([], h, t)' \
'ask split([1, 2, 3], h, t)
  h = 1, t = [2, 3]
  TRUE

ask split([1], h, t)
  h = 1, t = []
  TRUE

ask split([], h, t)
  FALSE'

check_output "Matching several items and a tail" "--brief" \
'rule first_two([a, b | rest], a, b, rest):
    a != b
ask first_two([1, 2, 3, 4], a, b, r)
ask first_two([1], a, b, r)' \
'ask first_two([1, 2, 3, 4], a, b, r)
  a = 1, b = 2, r = [3, 4]
  TRUE

ask first_two([1], a, b, r)
  FALSE'

check_output "Nested lists" "--brief" \
'fact pairs([["a", 1], ["b", 2]])
rule second_pair_name(n):
    pairs([first, [n, v]])
ask second_pair_name(n)' \
'ask second_pair_name(n)
  n = "b"
  TRUE'

check_output "length, sum, reverse, max" "--brief" \
"$LISTS
ask length([5, 6, 7], n)
ask sum([1, 2, 3, 4], s)
ask reverse([1, 2, 3], r)
ask max_of([3, 9, 2], m)
ask length([], n)" \
'ask length([5, 6, 7], n)
  n = 3
  TRUE

ask sum([1, 2, 3, 4], s)
  s = 10
  TRUE

ask reverse([1, 2, 3], r)
  r = [3, 2, 1]
  TRUE

ask max_of([3, 9, 2], m)
  m = 9
  TRUE

ask length([], n)
  n = 0
  TRUE'

check_output "append forwards and backwards" "--brief" \
"$LISTS
ask append([1, 2], [3], all)
ask append(front, back, [1, 2])
ask append(x, [3], [1, 2, 3])" \
'ask append([1, 2], [3], all)
  all = [1, 2, 3]
  TRUE

ask append(front, back, [1, 2])
  front = [], back = [1, 2]
  front = [1], back = [2]
  front = [1, 2], back = []
  TRUE

ask append(x, [3], [1, 2, 3])
  x = [1, 2]
  TRUE'

check_output "member finds or checks items" "--brief" \
"$LISTS
ask member(x, [\"a\", \"b\"])
ask member(\"b\", [\"a\", \"b\"])
ask member(\"c\", [\"a\", \"b\"])" \
'ask member(x, ["a", "b"])
  x = "a"
  x = "b"
  TRUE

ask member("b", ["a", "b"])
  TRUE

ask member("c", ["a", "b"])
  FALSE'

check_output "Insertion sort" "--brief" \
"$LISTS
ask sort([3, 1, 2, 5, 4], s)
ask sort([], s)" \
'ask sort([3, 1, 2, 5, 4], s)
  s = [1, 2, 3, 4, 5]
  TRUE

ask sort([], s)
  s = []
  TRUE'

check_output "== and != compare lists by contents" "--brief" \
'rule same(a, b):
    a == b
rule different(a, b):
    a != b
ask same([1, [2]], [1, [2]])
ask same([1, 2], [2, 1])
ask different([1, 2], [2, 1])' \
'ask same([1, [2]], [1, [2]])
  TRUE

ask same([1, 2], [2, 1])
  FALSE

ask different([1, 2], [2, 1])
  TRUE'

check_output "NOT with a list" "--brief" \
"$LISTS
rule missing(x, l):
    NOT member(x, l)
ask missing(5, [1, 2])
ask missing(1, [1, 2])" \
'ask missing(5, [1, 2])
  TRUE

ask missing(1, [1, 2])
  FALSE'

check_output "Arithmetic on a list item that isn't a number" "--brief" \
"$LISTS
ask sum([1, \"a\"], s)" \
'ask sum([1, "a"], s)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'total = x + rest'"'"' needs a number for '"'"'x'"'"', but it is "a"'

check_output "Lists in proofs and dead ends" "" \
'rule split(l, h, t):
    l = [h | t]
ask split([1, 2], h, t)
ask split([], h, t)' \
'ask split([1, 2], h, t)
  h = 1, t = [2]
    split([1, 2], 1, [2])  [rule split]
      [1, 2] = [1, 2]  [match]
  TRUE

ask split([], h, t)
  FALSE
  Dead ends (these goals could not be proved):
    [] = [_ | _]  (false)'

check_output "Unknown items show as _" "--brief" \
"$LISTS
ask length(l, 2)" \
'ask length(l, 2)
  l = [_, _]
  TRUE
  WARNING: stopped at depth limit (100); there may be more answers'

check_output "Syntax errors in lists" "" \
'fact f([1, 2)' \
'Syntax error on line 1: expected fact predicate and arguments'

finish_tests
