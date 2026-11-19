#!/usr/bin/env bash
#test_query.sh
#
# Tests for answering ask queries against stored facts (./sova run mode).

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAMILY='fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
fact parent("Alex", "Riley")'

check_output "Ground query that is true" "--brief" \
"$FAMILY
ask parent(\"Alex\", \"Sam\")" \
'ask parent("Alex", "Sam")
  TRUE'

check_output "Ground query that is false" "--brief" \
"$FAMILY
ask parent(\"Jamie\", \"Alex\")" \
'ask parent("Jamie", "Alex")
  FALSE'

check_output "Unknown predicate is false" "--brief" \
"$FAMILY
ask likes(\"Alex\", \"Sam\")" \
'ask likes("Alex", "Sam")
  FALSE'

check_output "Single variable binding" "--brief" \
"$FAMILY
ask parent(who, \"Jamie\")" \
'ask parent(who, "Jamie")
  who = "Sam"
  TRUE'

check_output "Multiple answers" "--brief" \
"$FAMILY
ask parent(\"Alex\", child)" \
'ask parent("Alex", child)
  child = "Sam"
  child = "Riley"
  TRUE'

check_output "Two variables" "--brief" \
'fact parent("Alex", "Sam")
ask parent(a, b)' \
'ask parent(a, b)
  a = "Alex", b = "Sam"
  TRUE'

check_output "Repeated variable must match the same value" "--brief" \
'fact same("a", "a")
fact same("a", "b")
ask same(x, x)' \
'ask same(x, x)
  x = "a"
  TRUE'

check_output "Arity mismatch is false" "--brief" \
"$FAMILY
ask parent(\"Alex\")" \
'ask parent("Alex")
  FALSE'

check_output "Syntax errors stop the run" "--brief" \
'fact parent("Alex"' \
'Syntax error on line 1: expected fact predicate and arguments'

finish_tests
