#!/usr/bin/env bash
#test_kb.sh
#
# Tests for the knowledge base built by kb_load (checked through ./sova --kb).

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_output "Facts are stored" "--kb" \
'fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")' \
'Facts (2):
  parent("Alex", "Sam")
  parent("Sam", "Jamie")
Rules (0):'

check_output "Duplicate facts are dropped" "--kb" \
'fact parent("Alex", "Sam")
fact parent("Alex", "Sam")' \
'Facts (1):
  parent("Alex", "Sam")
Rules (0):'

check_output "Strings with spaces and commas survive" "--kb" \
'fact name("Smith, Alex")' \
'Facts (1):
  name("Smith, Alex")
Rules (0):'

check_output "Rule goals are grouped under their rule" "--kb" \
'rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
rule sibling(x, y):
    parent(p, x)
    OR parent(p, y)' \
'Facts (0):
Rules (2):
  grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
  sibling(x, y):
    parent(p, x)
    OR parent(p, y)'

check_output "Rules with the same name are separate clauses" "--kb" \
'rule ancestor(x, y):
    parent(x, y)
rule ancestor(x, y):
    parent(x, z)
    AND ancestor(z, y)' \
'Facts (0):
Rules (2):
  ancestor(x, y):
    parent(x, y)
  ancestor(x, y):
    parent(x, z)
    AND ancestor(z, y)'

check_output "Queries are not facts" "--kb" \
'ask parent("Alex", "Sam")' \
'Facts (0):
Rules (0):'

finish_tests
