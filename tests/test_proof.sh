#!/usr/bin/env bash
#test_proof.sh
#
# Tests for explanations (the default ./sova run mode): why an answer is
# true (the rule used, its variable bindings, and the proof of each goal),
# and why a question is false (each goal of the rule tried, up to the one
# that failed). See src/explain.sh.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check_output 'A. A rule: the rule, every binding, then the proof' "" \
'fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
ask grandparent("Alex", "Jamie")' \
'ask grandparent("Alex", "Jamie")

TRUE, because:
  grandparent("Alex", "Jamie") is satisfied by:
    grandparent(x, z) if parent(x, y) AND parent(y, z)

  Variable bindings:
    x = "Alex"
    y = "Sam"
    z = "Jamie"

  Proof:
    parent("Alex", "Sam") is a fact.
    parent("Sam", "Jamie") is a fact.'

check_output 'B. A fact' "" \
'fact parent("Alex", "Sam")
ask parent("Alex", "Sam")' \
'ask parent("Alex", "Sam")

TRUE, because:
  parent("Alex", "Sam") is a fact.'

check_output 'C. One answer to a question with a variable' "" \
'fact parent("Sam", "Jamie")
ask parent(who, "Jamie")' \
'ask parent(who, "Jamie")

TRUE:
  who = "Sam"

  Because parent("Sam", "Jamie") is a fact.'

check_output 'C2. Several answers, each with its own explanation' "" \
'fact parent("Alex", "Jamie")
fact parent("Sam", "Jamie")
ask parent(who, "Jamie")' \
'ask parent(who, "Jamie")

TRUE, 2 answers:

  Answer 1:
    who = "Alex"

    Because parent("Alex", "Jamie") is a fact.

  Answer 2:
    who = "Sam"

    Because parent("Sam", "Jamie") is a fact.'

check_output 'C3. Several variables are listed one per line' "" \
'fact pair("a", 1)
ask pair(x, n)' \
'ask pair(x, n)

TRUE:
  x = "a"
  n = 1

  Because pair("a", 1) is a fact.'

check_output 'D. No matching fact and no rule' "" \
'fact parent("Alex", "Sam")
ask parent("Jamie", "Alex")' \
'ask parent("Jamie", "Alex")

FALSE:
  No matching fact exists.
  No rule defines parent.'

check_output 'D2. Nothing defines it' "" \
'ask likes("Alex", "Sam")' \
'ask likes("Alex", "Sam")

FALSE:
  Nothing defines likes: there are no facts or rules for it.'

check_output 'E. A rule that fails: each goal up to the one that failed' "" \
'fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
ask grandparent("Sam", "Alex")' \
'ask grandparent("Sam", "Alex")

FALSE, because:

  Tried:
    grandparent(x, z) if parent(x, y) AND parent(y, z)

  First goal:
    parent("Sam", y)

    Matched:
      y = "Jamie"

  Second goal:
    parent("Jamie", "Alex")

    FAILED:
      No matching fact exists.'

check_output 'E2. Other ways that failed the same way are counted' "" \
'fact parent("Ada", "Ben")
fact parent("Ada", "Fay")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
ask grandparent("Ada", "Zed")' \
'ask grandparent("Ada", "Zed")

FALSE, because:

  Tried:
    grandparent(x, z) if parent(x, y) AND parent(y, z)

  First goal:
    parent("Ada", y)

    Matched:
      y = "Ben"

  Second goal:
    parent("Ben", "Zed")

    FAILED:
      No matching fact exists.

  Sova also tried 1 other way with this rule; it failed too.'

check_output 'Recursion nests each rule'"'"'s explanation' "" \
'fact parent("a", "b")
fact parent("b", "c")
rule anc(x, y):
    parent(x, y)
rule anc(x, y):
    parent(x, z)
    AND anc(z, y)
ask anc("a", "c")' \
'ask anc("a", "c")

TRUE, because:
  anc("a", "c") is satisfied by:
    anc(x, y) if parent(x, z) AND anc(z, y)

  Variable bindings:
    x = "a"
    z = "b"
    y = "c"

  Proof:
    parent("a", "b") is a fact.

    anc("b", "c") is satisfied by:
      anc(x, y) if parent(x, y)

    Variable bindings:
      x = "b"
      y = "c"

    Proof:
      parent("b", "c") is a fact.'

check_output 'A failure inside a recursive call, and every rule tried' "" \
'fact parent("a", "b")
rule anc(x, y):
    parent(x, y)
rule anc(x, y):
    parent(x, z)
    AND anc(z, y)
ask anc("a", "z")' \
'ask anc("a", "z")

FALSE, because:

  Tried:
    anc(x, y) if parent(x, y)

  First goal:
    parent("a", "z")

    FAILED:
      No matching fact exists.

  Tried:
    anc(x, y) if parent(x, z) AND anc(z, y)

  First goal:
    parent("a", z)

    Matched:
      z = "b"

  Second goal:
    anc("b", "z")

    Tried:
      anc(x, y) if parent(x, y)

    First goal:
      parent("b", "z")

      FAILED:
        No matching fact exists.

  Sova also tried 1 other way with this rule; it failed too.'

check_output 'OR says which branch was used' "" \
'fact guardian("Riley", "Jamie")
rule carer(x, y):
    parent(x, y)
    OR guardian(x, y)
ask carer("Riley", "Jamie")' \
'ask carer("Riley", "Jamie")

TRUE, because:
  carer("Riley", "Jamie") is satisfied by:
    carer(x, y) if parent(x, y) OR guardian(x, y)
    (using: guardian(x, y))

  Variable bindings:
    x = "Riley"
    y = "Jamie"

  Proof:
    guardian("Riley", "Jamie") is a fact.'

check_output 'Comparisons, calculations, and NOT' "" \
'fact age("Jo", 30)
rule member(x, next):
    age(x, a)
    AND a >= 18
    AND next = a + 1
    AND NOT banned(x)
ask member("Jo", n)' \
'ask member("Jo", n)

TRUE:
  n = 31

  Because member("Jo", 31) is satisfied by:
    member(x, next) if age(x, a) AND a >= 18 AND next = a + 1 AND NOT banned(x)

  Variable bindings:
    x = "Jo"
    a = 30
    next = 31

  Proof:
    age("Jo", 30) is a fact.
    30 >= 18 is true.
    next = 30 + 1 = 31 (calculated).
    NOT banned("Jo"): banned("Jo") can'"'"'t be proved.'

check_output 'A comparison that fails' "" \
'fact age("Sam", 17)
rule adult(x):
    age(x, a)
    AND a >= 18
ask adult("Sam")' \
'ask adult("Sam")

FALSE, because:

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

check_output 'A NOT that fails' "" \
'fact person("Bob")
fact banned("Bob")
rule welcome(x):
    person(x)
    AND NOT banned(x)
ask welcome("Bob")' \
'ask welcome("Bob")

FALSE, because:

  Tried:
    welcome(x) if person(x) AND NOT banned(x)

  First goal:
    person("Bob")

    Matched: it is a fact.

  Second goal:
    NOT banned("Bob")

    FAILED:
      banned("Bob") can be proved.'

check_output 'A fact with variables' "" \
'fact same(x, x)
ask same(1, 1)' \
'ask same(1, 1)

TRUE, because:
  same(1, 1) is a fact (from the fact same(x, x)).'

check_output 'collect and count' "" \
'fact parent("Ada", "Ben")
fact parent("Ada", "Fay")
rule kids(p, list, n):
    collect(c, parent(p, c), list)
    AND count(parent(p, c), n)
ask kids("Ada", list, n)' \
'ask kids("Ada", list, n)

TRUE:
  list = ["Ben", "Fay"]
  n = 2

  Because kids("Ada", ["Ben", "Fay"], 2) is satisfied by:
    kids(p, list, n) if collect(c, parent(p, c), list) AND count(parent(p, c), n)

  Variable bindings:
    list = ["Ben", "Fay"]
    n = 2
    p = "Ada"

  Proof:
    collect(c, parent("Ada", c), ["Ben", "Fay"]): collected 2 answers.
    count(parent("Ada", c), 2): counted 2 answers.'

check_output 'A count that gives a different number' "" \
'fact parent("Ben", "Cy")
rule two_kids(p):
    count(parent(p, c), 2)
ask two_kids("Ben")' \
'ask two_kids("Ben")

FALSE, because:

  Tried:
    two_kids(p) if count(parent(p, c), 2)

  First goal:
    count(parent("Ben", c), 2)

    FAILED:
      It counted 1 answer, not 2.'

check_output 'Built-ins' "" \
'rule greet(name, message):
    concat("Hi, ", name, message)
ask greet("Sam", m)' \
'ask greet("Sam", m)

TRUE:
  m = "Hi, Sam"

  Because greet("Sam", "Hi, Sam") is satisfied by:
    greet(name, message) if concat("Hi, ", name, message)

  Variable bindings:
    name = "Sam"
    message = "Hi, Sam"

  Proof:
    concat("Hi, ", "Sam", "Hi, Sam") is true (built-in).'

check_output 'A rule whose head doesn'"'"'t match' "" \
'rule likes("Sam", food):
    food = "pizza"
ask likes("Jo", f)' \
'ask likes("Jo", f)

FALSE:
  No rule for likes matches likes("Jo", f).'

check_output 'A goal that would need itself' "" \
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

check_output 'Errors still say UNKNOWN' "" \
'rule r(x, y):
    y = x + 1
ask r(a, b)' \
'ask r(a, b)

UNKNOWN: some goals could not be checked
  ERROR: '"'"'y = x + 1'"'"' needs a value for '"'"'x'"'"' (put the goal that sets it earlier)'

check_output 'A warning after the answers' "" \
'fact parent("a", "b")
rule anc(x, y):
    anc(x, z)
    AND parent(z, y)
rule anc(x, y):
    parent(x, y)
ask anc("a", "b")' \
'ask anc("a", "b")

TRUE, because:
  anc("a", "b") is satisfied by:
    anc(x, y) if parent(x, y)

  Variable bindings:
    x = "a"
    y = "b"

  Proof:
    parent("a", "b") is a fact.

WARNING: stopped at depth limit (100); there may be more answers'

check_output "--brief hides explanations" "--brief" \
'fact parent("Alex", "Sam")
fact parent("Sam", "Jamie")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)
ask grandparent("Alex", "Jamie")
ask grandparent("Sam", "Alex")' \
'ask grandparent("Alex", "Jamie")
  TRUE

ask grandparent("Sam", "Alex")
  FALSE'

finish_tests
