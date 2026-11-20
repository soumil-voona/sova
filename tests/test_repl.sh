#!/usr/bin/env bash
#test_repl.sh
#
# Tests for the interactive prompt (./sova -i). Input is piped in, so no
# prompts are printed.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAMILY='fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
ask parent("Alex", "Sam")'

check_repl "File asks are not run on load" "--brief" "$FAMILY" \
'quit' \
''

check_repl "Questions without ask or with ?" "--brief" "$FAMILY" \
'parent(who, "Jamie")
ask grandparent("Alex", w)?' \
'ask parent(who, "Jamie")
  who = "Sam"
  TRUE
ask grandparent("Alex", w)
  w = "Jamie"
  TRUE'

check_repl "Adding a fact" "--brief" "$FAMILY" \
'fact parent("Jamie", "Kai")
grandparent("Sam", who)
fact parent("Jamie", "Kai")' \
'  Added.
ask grandparent("Sam", who)
  who = "Kai"
  TRUE
  Already known.'

check_repl "Adding a multi-line rule" "--brief" "$FAMILY" \
'fact parent("Jamie", "Kai")
rule great(x, y):
    grandparent(x, z)
    AND parent(z, y)

great("Alex", who)' \
'  Added.
  Added.
ask great("Alex", who)
  who = "Kai"
  TRUE'

check_repl "Syntax errors report the line typed" "--brief" "$FAMILY" \
'fact parent("a"
parent(' \
'Syntax error on line 1: expected fact predicate and arguments
Syntax error on line 1: expected query predicate and arguments'

check_repl "Starting with no file" "--brief" "" \
'fact likes("Sam", "pizza")
likes(who, "pizza")' \
'  Added.
ask likes(who, "pizza")
  who = "Sam"
  TRUE'

check_repl "Proofs are shown by default" "" "$FAMILY" \
'grandparent("Alex", "Jamie")' \
'ask grandparent("Alex", "Jamie")
  Proof:
    grandparent("Alex", "Jamie")  [rule grandparent]
      parent("Alex", "Sam")  [fact]
      parent("Sam", "Jamie")  [fact]
  TRUE'

check_repl "New argument-count warnings appear once" "--brief" "$FAMILY" \
'fact parent("a")
fact parent("b")' \
'Warning: '"'"'parent'"'"' is used with different numbers of arguments (2, 1)
  Added.
  Added.'

check_repl "Input after quit is ignored" "--brief" "$FAMILY" \
'quit
parent(a, b)' \
''

finish_tests
