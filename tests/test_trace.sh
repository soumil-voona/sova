#!/usr/bin/env bash
#test_trace.sh
#
# Tests for trace mode (--trace, and "trace" at the prompt): the search
# printed step by step: each goal, the option tried, what it matched, dead
# ends, going back to other options, and the answers. See src/trace.sh.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FAMILY='fact parent("Sam", "Jamie")
fact parent("Sam", "Alex")
fact parent("Alex", "Ben")
rule grandparent(x, z):
    parent(x, y)
    AND parent(y, z)'

check_output 'A dead end, then going back to the other option' "--trace" \
"$FAMILY
ask grandparent(\"Sam\", who)" \
'ask grandparent("Sam", who)

Trace:
  [1] grandparent("Sam", who)
      Try rule grandparent(x, z) if parent(x, y) AND parent(y, z)
      matches, with x = "Sam", z = who
      [2] parent("Sam", y)
          2 options: 2 facts match
          Try fact parent("Sam", "Jamie"): matches, with y = "Jamie"
      [3] parent("Jamie", z)
          ✗ No matching fact exists.
      ↩ Back to [2] parent("Sam", y): option 2 of 2
          Try fact parent("Sam", "Alex"): matches, with y = "Alex"
      [4] parent("Alex", z)
          Try fact parent("Alex", "Ben"): matches, with z = "Ben"
  ✓ Answer 1: who = "Ben"
  Search finished: 1 answer, 4 goals tried.

TRUE:
  who = "Ben"

  Because grandparent("Sam", "Ben") is satisfied by:
    grandparent(x, z) if parent(x, y) AND parent(y, z)

  Variable bindings:
    x = "Sam"
    y = "Alex"
    z = "Ben"

  Proof:
    parent("Sam", "Alex") is a fact.
    parent("Alex", "Ben") is a fact.'

check_output 'A FALSE answer' "--trace --brief" \
"$FAMILY
ask grandparent(\"Ben\", who)" \
'ask grandparent("Ben", who)

Trace:
  [1] grandparent("Ben", who)
      Try rule grandparent(x, z) if parent(x, y) AND parent(y, z)
      matches, with x = "Ben", z = who
      [2] parent("Ben", y)
          ✗ No matching fact exists.
  Search finished: 0 answers, 2 goals tried.

  FALSE'

check_output 'Recursion and several answers' "--trace --brief" \
'fact parent("Ada", "Ben")
fact parent("Ben", "Cy")
rule ancestor(x, z):
    parent(x, z)
rule ancestor(x, z):
    parent(x, y)
    AND ancestor(y, z)
ask ancestor("Ada", who)' \
'ask ancestor("Ada", who)

Trace:
  [1] ancestor("Ada", who)
      2 options: 2 rules match
      Try rule ancestor(x, z) if parent(x, z)
      matches, with x = "Ada", z = who
      [2] parent("Ada", z)
          Try fact parent("Ada", "Ben"): matches, with z = "Ben"
  ✓ Answer 1: who = "Ben"
  ↩ Back to [1] ancestor("Ada", who): option 2 of 2
      Try rule ancestor(x, z) if parent(x, y) AND ancestor(y, z)
      matches, with x = "Ada", z = who
      [3] parent("Ada", y)
          Try fact parent("Ada", "Ben"): matches, with y = "Ben"
      [4] ancestor("Ben", z)
          2 options: 2 rules match
          Try rule ancestor(x, z) if parent(x, z)
          matches, with x = "Ben"
          [5] parent("Ben", z)
              Try fact parent("Ben", "Cy"): matches, with z = "Cy"
  ✓ Answer 2: who = "Cy"
      ↩ Back to [4] ancestor("Ben", z): option 2 of 2
          Try rule ancestor(x, z) if parent(x, y) AND ancestor(y, z)
          matches, with x = "Ben"
          [6] parent("Ben", y)
              Try fact parent("Ben", "Cy"): matches, with y = "Cy"
          [7] ancestor("Cy", z)
              2 options: 2 rules match
              Try rule ancestor(x, z) if parent(x, z)
              matches, with x = "Cy"
              [8] parent("Cy", z)
                  ✗ No matching fact exists.
          ↩ Back to [7] ancestor("Cy", z): option 2 of 2
              Try rule ancestor(x, z) if parent(x, y) AND ancestor(y, z)
              matches, with x = "Cy"
              [9] parent("Cy", y)
                  ✗ No matching fact exists.
  Search finished: 2 answers, 9 goals tried.

  who = "Ben"
  who = "Cy"
  TRUE'

check_output 'The same answer found twice is counted once' "--trace --brief" \
'fact likes("Jo", "tea")
rule fan(p):
    likes(p, "tea")
    OR likes(p, d)
ask fan(who)' \
'ask fan(who)

Trace:
  [1] fan(who)
      2 options: 2 OR branches match
      Try rule fan(p) if likes(p, "tea") OR likes(p, d)
      (using: likes(p, "tea"))
      matches, with p = who
      [2] likes(p, "tea")
          Try fact likes("Jo", "tea"): matches, with p = "Jo"
  ✓ Answer 1: who = "Jo"
  ↩ Back to [1] fan(who): option 2 of 2
      Try rule fan(p) if likes(p, "tea") OR likes(p, d)
      (using: likes(p, d))
      matches, with p = who
      [3] likes(p, d)
          Try fact likes("Jo", "tea"): matches, with p = "Jo", d = "tea"
  ✓ Same answer again: who = "Jo" (shown once)
  Search finished: 1 answer, 3 goals tried.

  who = "Jo"
  TRUE'

check_output 'NOT runs its own search' "--trace --brief" \
'fact banned("Bob")
fact person("Bob")
fact person("Jo")
rule ok(p):
    person(p)
    AND NOT banned(p)
ask ok(who)' \
'ask ok(who)

Trace:
  [1] ok(who)
      Try rule ok(p) if person(p) AND NOT banned(p)
      matches, with p = who
      [2] person(p)
          2 options: 2 facts match
          Try fact person("Bob"): matches, with p = "Bob"
      [3] NOT banned("Bob")
          Check whether banned("Bob") can be proved:
          [4] banned("Bob")
              Try fact banned("Bob"): matches
          ✓ It can be proved.
          ✗ banned("Bob") can be proved, so NOT banned("Bob") is false.
      ↩ Back to [2] person(p): option 2 of 2
          Try fact person("Jo"): matches, with p = "Jo"
      [5] NOT banned("Jo")
          Check whether banned("Jo") can be proved:
          [6] banned("Jo")
              ✗ No matching fact exists.
          ✓ banned("Jo") can'"'"'t be proved, so NOT banned("Jo") is true.
  ✓ Answer 1: who = "Jo"
  Search finished: 1 answer, 6 goals tried.

  who = "Jo"
  TRUE'

check_output 'Comparisons and calculations' "--trace --brief" \
'fact age("Jo", 20)
fact age("Al", 12)
rule adult(p):
    age(p, a)
    AND a >= 18
rule next(n, m):
    m = n + 1
ask adult("Al")
ask next(3, m)' \
'ask adult("Al")

Trace:
  [1] adult("Al")
      Try rule adult(p) if age(p, a) AND a >= 18
      matches, with p = "Al"
      [2] age("Al", a)
          Try fact age("Al", 12): matches, with a = 12
      [3] 12 >= 18
          ✗ 12 >= 18 is false.
  Search finished: 0 answers, 3 goals tried.

  FALSE

ask next(3, m)

Trace:
  [1] next(3, m)
      Try rule next(n, m) if m = n + 1
      matches, with n = 3
      [2] m = 3 + 1
          ✓ m = 4
  ✓ Answer 1: m = 4
  Search finished: 1 answer, 2 goals tried.

  m = 4
  TRUE'

check_output 'count and collect' "--trace --brief" \
'fact n(1)
fact n(2)
rule how_many(c):
    count(n(v), c)
rule all(l):
    collect(v, n(v), l)
ask how_many(c)
ask all(l)' \
'ask how_many(c)

Trace:
  [1] how_many(c)
      Try rule how_many(c) if count(n(v), c)
      matches
      [2] count(n(v), c)
          Find every answer to n(v):
          [3] n(v)
              2 options: 2 facts match
              Try fact n(1): matches, with v = 1
          ✓ Found: v = 1
          ↩ Back to [3] n(v): option 2 of 2
              Try fact n(2): matches, with v = 2
          ✓ Found: v = 2
          ✓ Counted them: c = 2
  ✓ Answer 1: c = 2
  Search finished: 1 answer, 3 goals tried.

  c = 2
  TRUE

ask all(l)

Trace:
  [1] all(l)
      Try rule all(l) if collect(v, n(v), l)
      matches
      [2] collect(v, n(v), l)
          Find every answer to n(v):
          [3] n(v)
              2 options: 2 facts match
              Try fact n(1): matches, with v = 1
          ✓ Found: v = 1
          ↩ Back to [3] n(v): option 2 of 2
              Try fact n(2): matches, with v = 2
          ✓ Found: v = 2
          ✓ Collected them: l = [1, 2]
  ✓ Answer 1: l = [1, 2]
  Search finished: 1 answer, 3 goals tried.

  l = [1, 2]
  TRUE'

check_output 'A built-in with several results' "--trace --brief" \
'ask concat(a, b, "hi")' \
'ask concat(a, b, "hi")

Trace:
  [1] concat(a, b, "hi")
      3 options: 3 possible results
      ✓ a = "", b = "hi"
  ✓ Answer 1: a = "", b = "hi"
  ↩ Back to [1] concat(a, b, "hi"): option 2 of 3
      ✓ a = "h", b = "i"
  ✓ Answer 2: a = "h", b = "i"
  ↩ Back to [1] concat(a, b, "hi"): option 3 of 3
      ✓ a = "hi", b = ""
  ✓ Answer 3: a = "hi", b = ""
  Search finished: 3 answers, 1 goal tried.

  a = "", b = "hi"
  a = "h", b = "i"
  a = "hi", b = ""
  TRUE'

check_output 'A goal that needs itself' "--trace --brief" \
'fact edge("a", "b")
fact edge("b", "a")
rule path(x, y):
    edge(x, y)
rule path(x, y):
    edge(x, z)
    AND path(z, y)
ask path("a", "c")' \
'ask path("a", "c")

Trace:
  [1] path("a", "c")
      2 options: 2 rules match
      Try rule path(x, y) if edge(x, y)
      matches, with x = "a", y = "c"
      [2] edge("a", "c")
          ✗ No matching fact exists.
  ↩ Back to [1] path("a", "c"): option 2 of 2
      Try rule path(x, y) if edge(x, z) AND path(z, y)
      matches, with x = "a", y = "c"
      [3] edge("a", z)
          Try fact edge("a", "b"): matches, with z = "b"
      [4] path("b", "c")
          2 options: 2 rules match
          Try rule path(x, y) if edge(x, y)
          matches, with x = "b", y = "c"
          [5] edge("b", "c")
              ✗ No matching fact exists.
      ↩ Back to [4] path("b", "c"): option 2 of 2
          Try rule path(x, y) if edge(x, z) AND path(z, y)
          matches, with x = "b", y = "c"
          [6] edge("b", z)
              Try fact edge("b", "a"): matches, with z = "a"
          [7] path("a", "c")
              ✗ It would need itself to be proved first.
  Search finished: 0 answers, 7 goals tried.

  FALSE'

check_output 'A goal that cannot be checked yet' "--trace --brief" \
'rule big(x):
    x > 3
ask big(y)' \
'ask big(y)

Trace:
  [1] big(y)
      Try rule big(x) if x > 3
      matches, with x = y
      [2] x > 3
          ✗ It can'"'"'t be checked yet (see the error after the trace).
  Search finished: 0 answers, 2 goals tried.

  UNKNOWN: some goals could not be checked
  ERROR: '"'"'x > 3'"'"' needs a value for '"'"'x'"'"' (put the goal that sets it earlier)'

SOVA_MAX_DEPTH=3 check_output 'The depth limit' "--trace --brief" \
'rule loop(x):
    loop(x)
ask loop(q)' \
'ask loop(q)

Trace:
  [1] loop(q)
      Try rule loop(x) if loop(x)
      matches, with x = q
      [2] loop(x)
          Try rule loop(x) if loop(x)
          matches
          [3] loop(x)
              Try rule loop(x) if loop(x)
              matches
              [4] loop(x)
                  ✗ Stopped: rules are nested 3 deep here (the depth limit).
  Search finished: 0 answers, 4 goals tried.

  UNKNOWN: depth limit (3) reached; a rule may be calling itself forever'

SOVA_TRACE_LIMIT=3 check_output 'The trace stops after SOVA_TRACE_LIMIT goals' "--trace --brief" \
"$FAMILY
ask grandparent(\"Sam\", who)" \
'ask grandparent("Sam", who)

Trace:
  [1] grandparent("Sam", who)
      Try rule grandparent(x, z) if parent(x, y) AND parent(y, z)
      matches, with x = "Sam", z = who
      [2] parent("Sam", y)
          2 options: 2 facts match
          Try fact parent("Sam", "Jamie"): matches, with y = "Jamie"
      [3] parent("Jamie", z)
          ✗ No matching fact exists.
      ↩ Back to [2] parent("Sam", y): option 2 of 2
          Try fact parent("Sam", "Alex"): matches, with y = "Alex"
  ... the trace stops here, after 3 goals (set SOVA_TRACE_LIMIT to see more); the search keeps going.
  Search finished: 1 answer, 4 goals tried (the trace shows the first 3).

  who = "Ben"
  TRUE'

check_repl 'trace at the prompt' "" \
"$FAMILY" \
'trace parent(who, "Jamie")?
parent(who, "Jamie")' \
'ask parent(who, "Jamie")

Trace:
  [1] parent(who, "Jamie")
      Try fact parent("Sam", "Jamie"): matches, with who = "Sam"
  ✓ Answer 1: who = "Sam"
  Search finished: 1 answer, 1 goal tried.

TRUE:
  who = "Sam"

  Because parent("Sam", "Jamie") is a fact.
ask parent(who, "Jamie")

TRUE:
  who = "Sam"

  Because parent("Sam", "Jamie") is a fact.'

finish_tests
