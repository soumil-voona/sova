#!/usr/bin/env bash
#test_rules.sh
#
# Tests for rule evaluation in the inference engine (src/inference.sh).

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAMILY='fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
fact parent("Sam", "Riley")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)'

check_output "AND rule, ground query" "--brief" \
"$FAMILY
ask grandparent(\"Alex\", \"Jamie\")" \
'ask grandparent("Alex", "Jamie")
  TRUE'

check_output "AND rule, false" "--brief" \
"$FAMILY
ask grandparent(\"Sam\", \"Jamie\")" \
'ask grandparent("Sam", "Jamie")
  FALSE'

check_output "AND rule, variable answers" "--brief" \
"$FAMILY
ask grandparent(\"Alex\", who)" \
'ask grandparent("Alex", who)
  who = "Jamie"
  who = "Riley"
  TRUE'

check_output "Rule-internal variables are hidden" "--brief" \
"$FAMILY
ask grandparent(g, \"Riley\")" \
'ask grandparent(g, "Riley")
  g = "Alex"
  TRUE'

check_output "Query variable names can match rule variable names" "--brief" \
"$FAMILY
ask grandparent(z, x)" \
'ask grandparent(z, x)
  z = "Alex", x = "Jamie"
  z = "Alex", x = "Riley"
  TRUE'

check_output "Wrong arity for a rule is false" "--brief" \
"$FAMILY
ask grandparent(\"Alex\")" \
'Warning: '"'"'grandparent'"'"' is used with different numbers of arguments (2, 1)
ask grandparent("Alex")
  FALSE'

check_output "OR gives alternatives" "--brief" \
'fact parent("Sam", "Jamie")
fact guardian("Riley", "Jamie")
rule carer(x, y):
    parent(x, y)
    OR guardian(x, y)
ask carer(who, "Jamie")' \
'ask carer(who, "Jamie")
  who = "Sam"
  who = "Riley"
  TRUE'

check_output "OR binds looser than AND" "--brief" \
'fact a("1")
fact c("1")
rule r(x):
    a(x)
    AND b(x)
    OR c(x)
ask r("1")' \
'ask r("1")
  TRUE'

check_output "Constants in a rule body" "--brief" \
'fact likes("Sam", "pizza")
fact likes("Jo", "soup")
rule pizza_fan(x):
    likes(x, "pizza")
ask pizza_fan(who)' \
'ask pizza_fan(who)
  who = "Sam"
  TRUE'

check_output "Rules calling rules" "--brief" \
"$FAMILY
rule has_grandchild(x):
    grandparent(x, y)
ask has_grandchild(who)" \
'ask has_grandchild(who)
  who = "Alex"
  TRUE'

check_output "Recursive rule with two clauses" "--brief" \
'fact parent("a", "b")
fact parent("b", "c")
fact parent("c", "d")
rule anc(x, y):
    parent(x, y)
rule anc(x, y):
    parent(x, z)
    AND anc(z, y)
ask anc("a", who)' \
'ask anc("a", who)
  who = "b"
  who = "c"
  who = "d"
  TRUE'

check_output "Duplicate answers are shown once" "--brief" \
'fact parent("Sam", "Jamie")
fact parent("Sam", "Riley")
rule is_parent(x):
    parent(x, c)
ask is_parent(who)' \
'ask is_parent(who)
  who = "Sam"
  TRUE'

check_output "Repeated variable in a rule body" "--brief" \
'fact edge("a", "a")
fact edge("a", "b")
rule loop(x):
    edge(x, x)
ask loop(n)' \
'ask loop(n)
  n = "a"
  TRUE'

check_output "Facts with variables match anything" "--brief" \
'fact likes(anyone, "cake")
ask likes("Sam", "cake")
ask likes(who, "cake")' \
'ask likes("Sam", "cake")
  TRUE

ask likes(who, "cake")
  who = (any value)
  TRUE'

check_output "Infinite recursion hits the depth limit" "--brief" \
'rule forever(x):
    forever(x)
ask forever(w)' \
'ask forever(w)
  UNKNOWN: depth limit (100) reached; a rule may be calling itself forever'

check_output "A known goal that needs itself is false" "" \
'rule forever(x):
    forever(x)
ask forever("a")' \
'ask forever("a")

FALSE, because:

  Tried:
    forever(x) if forever(x)

  First goal:
    forever("a")

    FAILED:
      It would need itself to be proved first.'

check_output "Cycles in a graph finish" "--brief" \
'fact edge("a", "b")
fact edge("b", "c")
fact edge("c", "a")
fact edge("c", "d")
rule reach(x, y):
    edge(x, y)
rule reach(x, y):
    edge(x, z)
    AND reach(z, y)
ask reach("a", "d")
ask reach("d", "a")' \
'ask reach("a", "d")
  TRUE

ask reach("d", "a")
  FALSE'

check_output "Symmetric rules finish" "--brief" \
'fact knows("a", "b")
rule knows(x, y):
    knows(y, x)
ask knows("b", "a")
ask knows("a", "c")' \
'ask knows("b", "a")
  TRUE

ask knows("a", "c")
  FALSE'

check_output "Left recursion still finds answers" "--brief" \
'fact parent("a", "b")
rule anc(x, y):
    anc(x, z)
    AND parent(z, y)
rule anc(x, y):
    parent(x, y)
ask anc("a", "b")' \
'ask anc("a", "b")
  TRUE
  WARNING: stopped at depth limit (100); there may be more answers'

finish_tests
