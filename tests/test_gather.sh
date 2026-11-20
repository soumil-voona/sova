#!/usr/bin/env bash
#test_gather.sh
#
# Tests for collect (gather answers into a list) and count.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

GATHER="$(cat "$TEST_DIR/translations/gather.sova")"

check_output "collect makes a list of answers" "--brief" \
"$GATHER
ask children(\"Ada\", k)
ask children(\"Cy\", k)" \
'ask children("Ada", k)
  k = ["Ben", "Fay"]
  TRUE

ask children("Cy", k)
  k = []
  TRUE'

check_output "count counts answers" "--brief" \
"$GATHER
ask how_many(\"Ada\", n)
ask how_many(\"Cy\", n)
ask how_many(\"Ben\", 1)
ask how_many(\"Ben\", 2)
ask everyone_counted(n)" \
'ask how_many("Ada", n)
  n = 2
  TRUE

ask how_many("Cy", n)
  n = 0
  TRUE

ask how_many("Ben", 1)
  TRUE

ask how_many("Ben", 2)
  FALSE

ask everyone_counted(n)
  n = 3
  TRUE'

check_output "Collecting lists, over a rule" "--brief" \
"$GATHER
ask kid_ages(\"Ada\", a)" \
'ask kid_ages("Ada", a)
  a = [["Ben", 30], ["Fay", 25]]
  TRUE'

check_output "Using a collected list" "--brief" \
"$GATHER
ask total_age(\"Ada\", t)" \
'ask total_age("Ada", t)
  t = 55
  TRUE'

check_output "count after a goal that gives the value" "--brief" \
"$GATHER
ask big_family(p)" \
'ask big_family(p)
  p = "Ada"
  TRUE'

check_output "A value that is still needed must be known first" "--brief" \
"$GATHER
ask children(p, k)
rule busy(p):
    count(parent(p, c), n)
    AND n >= 2
ask busy(p)" \
'ask children(p, k)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'collect(c, parent(p, c), kids)'"'"' needs a value for '"'"'p'"'"' first (otherwise it would collect over every p)

ask busy(p)
  UNKNOWN: some goals could not be checked
  ERROR: '"'"'count(parent(p, c), n)'"'"' needs a value for '"'"'p'"'"' first (otherwise it would count over every p)'

check_output "Proofs show what was gathered" "" \
"$GATHER
ask total_age(\"Ada\", t)" \
'ask total_age("Ada", t)
  t = 55
    total_age("Ada", 55)  [rule total_age]
      collect(a, kid_age("Ada", c, a), [30, 25])  [collect]
      sum([30, 25], 55)  [rule sum]
        sum([25], 25)  [rule sum]
          sum([], 0)  [fact]
          25 = 25 + 0  [calculation]
        55 = 30 + 25  [calculation]
  TRUE'

check_output "A wrong count is a dead end" "" \
"$GATHER
ask how_many(\"Ben\", 2)" \
'ask how_many("Ben", 2)
  FALSE
  Dead ends (these goals could not be proved):
    count(parent("Ben", c), 2)  (gives 1)'

check_output "collect and count are shown as written" "--kb" \
'rule r(p, k, n):
    collect([c, 1], parent(p, c), k)
    AND count(parent(p, c), n)' \
'Facts (0):
Rules (1):
  r(p, k, n):
    collect([c, 1], parent(p, c), k)
    AND count(parent(p, c), n)'

check_output "A predicate named count is still a normal call" "--brief" \
'fact count("apples", 3)
ask count("apples", n)' \
'ask count("apples", n)
  n = 3
  TRUE'

check_output "collect without a call inside is an ordinary call" "" \
'rule r(k):
    collect(c, 5, k)
ask r(k)' \
'ask r(k)
  FALSE
  No facts or rules define '"'"'collect'"'"''

finish_tests
