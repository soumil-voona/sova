#!/usr/bin/env bash
#test_proof.sh
#
# Tests for proof trees and failure explanations (default ./sova run mode).

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAMILY='fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)'

check_output "Fact proof" "" \
"$FAMILY
ask parent(\"Alex\", \"Sam\")" \
'ask parent("Alex", "Sam")
  Proof:
    parent("Alex", "Sam")  [fact]
  TRUE'

check_output "Rule proof shows the facts it used" "" \
"$FAMILY
ask grandparent(\"Alex\", \"Jamie\")" \
'ask grandparent("Alex", "Jamie")
  Proof:
    grandparent("Alex", "Jamie")  [rule grandparent]
      parent("Alex", "Sam")  [fact]
      parent("Sam", "Jamie")  [fact]
  TRUE'

check_output "Each answer gets its own proof" "" \
'fact parent("Ada", "Ben")
fact parent("Ada", "Fay")
ask parent("Ada", kid)' \
'ask parent("Ada", kid)
  kid = "Ben"
    parent("Ada", "Ben")  [fact]
  kid = "Fay"
    parent("Ada", "Fay")  [fact]
  TRUE'

check_output "Nested rules indent deeper and name the clause" "" \
'fact parent("a", "b")
fact parent("b", "c")
rule anc(x, y):
    parent(x, y)
rule anc(x, y):
    parent(x, z)
    AND anc(z, y)
ask anc("a", "c")' \
'ask anc("a", "c")
  Proof:
    anc("a", "c")  [rule anc, clause 2]
      parent("a", "b")  [fact]
      anc("b", "c")  [rule anc, clause 1]
        parent("b", "c")  [fact]
  TRUE'

check_output "OR branch is named" "" \
'fact guardian("Riley", "Jamie")
rule carer(x, y):
    parent(x, y)
    OR guardian(x, y)
ask carer("Riley", "Jamie")' \
'ask carer("Riley", "Jamie")
  Proof:
    carer("Riley", "Jamie")  [rule carer, OR branch 2]
      guardian("Riley", "Jamie")  [fact]
  TRUE'

check_output "Unbound values show as _" "" \
'fact likes(anyone, "cake")
ask likes(who, "cake")' \
'ask likes(who, "cake")
  who = (any value)
    likes(_, "cake")  [fact]
  TRUE'

check_output "FALSE lists dead ends" "" \
"$FAMILY
ask grandparent(\"Sam\", \"Alex\")" \
'ask grandparent("Sam", "Alex")
  FALSE
  Dead ends (no fact or rule matches):
    parent("Jamie", "Alex")'

check_output "FALSE names undefined predicates" "" \
"$FAMILY
ask likes(\"Alex\", \"Sam\")" \
'ask likes("Alex", "Sam")
  FALSE
  No facts or rules define '"'"'likes'"'"''

check_output "Dead ends are capped at five" "" \
'fact p("1")
fact p("2")
fact p("3")
fact p("4")
fact p("5")
fact p("6")
rule r(x):
    p(x)
    AND q(x)
fact q("0")
ask r(n)' \
'ask r(n)
  FALSE
  Dead ends (no fact or rule matches):
    q("1")
    q("2")
    q("3")
    q("4")
    q("5")
    ... and 1 more'

check_output "--brief hides proofs and explanations" "--brief" \
"$FAMILY
ask grandparent(\"Alex\", \"Jamie\")
ask grandparent(\"Sam\", \"Alex\")" \
'ask grandparent("Alex", "Jamie")
  TRUE

ask grandparent("Sam", "Alex")
  FALSE'

finish_tests
