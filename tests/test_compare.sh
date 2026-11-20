#!/usr/bin/env bash
#test_compare.sh
#
# Tests for the paradigm comparison view (./sova --compare TARGET FILE).

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# check_compare NAME TARGET SOURCE EXPECTED
check_compare() {
    local name="$1" target="$2" source="$3" expected="$4"
    local temp_file actual
    temp_file=$(mktemp)
    printf '%s\n' "$source" > "$temp_file"
    actual="$("$SOVA" --compare "$target" "$temp_file" 2>&1)"
    rm -f "$temp_file"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

check_compare 'Comparison and NOT' 'member(who)' \
'# Numbers, comparisons, NOT, and constants in rule heads.

fact age("Sam", 17)
fact age("Jo", 30)
fact age("Bob", 45)
fact age("Ana", 22)
fact banned("Bob")
fact friend("Ana", "Jo")

# Members must be adults who aren'"'"'t banned.
rule member(x):
    age(x, a)
    AND a >= 18
    AND NOT banned(x)

# Anyone can bring a friend who is also a member, as long as it'"'"'s not themself.
rule can_bring(x, guest):
    friend(x, guest)
    AND member(guest)
    AND x != guest

# A constant in a rule head: Sam is the club'"'"'s only junior member.
rule junior("Sam"):
    age("Sam", a)
    AND a < 18

ask member(who)
ask member("Bob")
ask can_bring("Ana", who)
ask junior(who)' \
'Three ways to write member(who)

1. Logic (Sova): say what is true, and let Sova search for answers

    rule member(x):
        age(x, a)
        AND a >= 18
        AND NOT banned(x)

    4 lines, plus 5 facts

2. Imperative (Python): spell out each step with loops and ifs

    def all_member():
        """Return every x where member(x) is true."""
        results = []
        seen = set()
        # rule member: member(x) if age(x, a) AND a >= 18 AND NOT banned(x)
        for (x, a) in age:
            if a >= 18:
                if x not in banned:
                    if x not in seen:
                        seen.add(x)
                        results.append(x)
        return results

    10 lines of code, plus the same facts as lists

3. Functional (Python): describe the results as list comprehensions

    def all_member():
        """Return every x where member(x) is true."""
        return unique(
            # rule member: member(x) if age(x, a) AND a >= 18 AND NOT banned(x)
            [x for (x, a) in age if a >= 18 and x not in banned]
        )

    4 lines of code, plus the facts and a 3-line unique() helper

How the ideas map

    Sova                       Imperative                         Functional
    ----                       ----------                         ----------
    fact                       a row in a list                    a row in a list
    rule                       a function                         a function returning a list
    AND, goal finds values     a nested for loop                  a for clause
    AND, goal only checks      an if                              an if clause
    comparison (a >= 18)       an if (if a >= 18:)                an if clause (if a >= 18)
    NOT p(x)                   if x not in p / not is_p(x)        the same, as an if clause
    variable                   a loop variable                    a comprehension variable
    trying the next match      the loop moves to the next row     the comprehension does too
    each answer once           a seen set                         unique()

Sova'"'"'s answer

    ask member(who)
      who = "Jo"
      who = "Ana"
      TRUE

    Both Python versions compute the same answers, in the same order.'

check_compare 'Recursion with two clauses' 'ancestor("Ada", who)' \
'# Recursive rules: an ancestor is a parent, or a parent of an ancestor.

fact parent("Ada", "Ben")
fact parent("Ben", "Cleo")
fact parent("Cleo", "Dev")
fact parent("Dev", "Eli")
fact parent("Ada", "Fay")

# Base case
rule ancestor(x, y):
    parent(x, y)

# Recursive case
rule ancestor(x, y):
    parent(x, z)
    AND ancestor(z, y)

ask ancestor("Ada", "Eli")
ask ancestor("Eli", "Ada")
ask ancestor("Ada", who)
ask ancestor(who, "Dev")' \
'Three ways to write ancestor("Ada", who)

1. Logic (Sova): say what is true, and let Sova search for answers

    rule ancestor(x, y):
        parent(x, y)
    rule ancestor(x, y):
        parent(x, z)
        AND ancestor(z, y)

    5 lines, plus 5 facts

2. Imperative (Python): spell out each step with loops and ifs

    def ancestor_given_x(x):
        """Return every y where ancestor(x, y) is true."""
        results = []
        seen = set()
        # rule ancestor, clause 1: ancestor(x, y) if parent(x, y)
        for (v1, y) in parent:
            if v1 == x:
                if y not in seen:
                    seen.add(y)
                    results.append(y)
        # rule ancestor, clause 2: ancestor(x, y) if parent(x, z) AND ancestor(z, y)
        for (v1, z) in parent:
            if v1 == x:
                for y in ancestor_given_x(z):
                    if y not in seen:
                        seen.add(y)
                        results.append(y)
        return results

    15 lines of code, plus the same facts as lists

3. Functional (Python): describe the results as list comprehensions

    def ancestor_given_x(x):
        """Return every y where ancestor(x, y) is true."""
        return unique(
            # rule ancestor, clause 1: ancestor(x, y) if parent(x, y)
            [y for (v1, y) in parent if v1 == x]
            # rule ancestor, clause 2: ancestor(x, y) if parent(x, z) AND ancestor(z, y)
            + [y for (v1, z) in parent if v1 == x for y in ancestor_given_x(z)]
        )

    5 lines of code, plus the facts and a 3-line unique() helper

How the ideas map

    Sova                       Imperative                         Functional
    ----                       ----------                         ----------
    fact                       a row in a list                    a row in a list
    rule                       a function                         a function returning a list
    AND, goal finds values     a nested for loop                  a for clause
    AND, goal only checks      an if                              an if clause
    another clause, or OR      another block adding results       another list joined with +
    a rule using itself        a function calling itself          a function calling itself
    variable                   a loop variable                    a comprehension variable
    trying the next match      the loop moves to the next row     the comprehension does too
    each answer once           a seen set                         unique()

Sova'"'"'s answer

    ask ancestor("Ada", who)
      who = "Ben"
      who = "Fay"
      who = "Cleo"
      who = "Dev"
      who = "Eli"
      TRUE

    Both Python versions compute the same answers, in the same order.'

check_compare 'OR, everything known' 'caregiver("Sam", "Jamie")' \
'# OR binds loosest: "a AND b OR c" means (a AND b) OR c.

fact parent("Sam", "Jamie")
fact guardian("Riley", "Jamie")
fact cat("Mochi")
fact owns("Jamie", "Mochi")

rule caregiver(x, y):
    parent(x, y)
    OR guardian(x, y)

rule pet_of_family(pet, adult):
    owns(kid, pet)
    AND caregiver(adult, kid)
    OR owns(adult, pet)

ask caregiver(who, "Jamie")
ask pet_of_family("Mochi", who)' \
'Three ways to write caregiver("Sam", "Jamie")

1. Logic (Sova): say what is true, and let Sova search for answers

    rule caregiver(x, y):
        parent(x, y)
        OR guardian(x, y)

    3 lines, plus 2 facts

2. Imperative (Python): spell out each step with loops and ifs

    def is_caregiver(x, y):
        """Return True if caregiver(x, y) is true."""
        # rule caregiver, OR branch 1: caregiver(x, y) if parent(x, y)
        if (x, y) in parent:
            return True
        # rule caregiver, OR branch 2: caregiver(x, y) if guardian(x, y)
        if (x, y) in guardian:
            return True
        return False

    6 lines of code, plus the same facts as lists

3. Functional (Python): describe the results as list comprehensions

    def is_caregiver(x, y):
        """Return True if caregiver(x, y) is true."""
        return (
            # rule caregiver, OR branch 1: caregiver(x, y) if parent(x, y)
            ((x, y) in parent)
            # rule caregiver, OR branch 2: caregiver(x, y) if guardian(x, y)
            or ((x, y) in guardian)
        )

    5 lines of code, plus the same facts as lists

How the ideas map

    Sova                       Imperative                         Functional
    ----                       ----------                         ----------
    fact                       a row in a list                    a row in a list
    rule                       a function                         a function returning a list
    AND, goal finds values     a nested for loop                  a for clause
    AND, goal only checks      an if                              an if clause
    another clause, or OR      another block adding results       another list joined with +
    variable                   a loop variable                    a comprehension variable
    trying the next match      the loop moves to the next row     the comprehension does too
    each answer once           a seen set                         unique()

Sova'"'"'s answer

    ask caregiver("Sam", "Jamie")
      TRUE

    Both Python versions compute the same answers, in the same order.'

check_compare 'Rule that calls itself first' 'anc("a", w)' \
'fact parent("a", "b")
rule anc(x, y):
    anc(x, z)
    AND parent(z, y)
rule anc(x, y):
    parent(x, y)
ask anc("a", "b")
ask anc("b", "a")' \
'Three ways to write anc("a", w)

1. Logic (Sova): say what is true, and let Sova search for answers

    rule anc(x, y):
        anc(x, z)
        AND parent(z, y)
    rule anc(x, y):
        parent(x, y)

    5 lines, plus 1 facts

2. Imperative (Python): spell out each step with loops and ifs

    def anc_given_x(x):
        """Return every y where anc(x, y) is true."""
        results = []
        seen = set()
        # rule anc, clause 1: anc(x, y) if anc(x, z) AND parent(z, y)
        # WARNING: this calls anc_given_x before doing anything else,
        # with the same input, so it would call itself forever
        for z in anc_given_x(x):
            for (v1, y) in parent:
                if v1 == z:
                    if y not in seen:
                        seen.add(y)
                        results.append(y)
        # rule anc, clause 2: anc(x, y) if parent(x, y)
        for (v1, y) in parent:
            if v1 == x:
                if y not in seen:
                    seen.add(y)
                    results.append(y)
        return results

    15 lines of code, plus the same facts as lists

3. Functional (Python): describe the results as list comprehensions

    def anc_given_x(x):
        """Return every y where anc(x, y) is true."""
        return unique(
            # rule anc, clause 1: anc(x, y) if anc(x, z) AND parent(z, y)
            # WARNING: this calls anc_given_x before doing anything else,
            # with the same input, so it would call itself forever
            [y for z in anc_given_x(x) for (v1, y) in parent if v1 == z]
            # rule anc, clause 2: anc(x, y) if parent(x, y)
            + [y for (v1, y) in parent if v1 == x]
        )

    5 lines of code, plus the facts and a 3-line unique() helper

How the ideas map

    Sova                       Imperative                         Functional
    ----                       ----------                         ----------
    fact                       a row in a list                    a row in a list
    rule                       a function                         a function returning a list
    AND, goal finds values     a nested for loop                  a for clause
    AND, goal only checks      an if                              an if clause
    another clause, or OR      another block adding results       another list joined with +
    a rule using itself        a function calling itself          a function calling itself
    variable                   a loop variable                    a comprehension variable
    trying the next match      the loop moves to the next row     the comprehension does too
    each answer once           a seen set                         unique()

Sova'"'"'s answer

    ask anc("a", w)
      w = "b"
      TRUE
      WARNING: stopped at depth limit (100); there may be more answers

    The Python versions would keep calling themselves until Python stops
    them with a RecursionError: see the WARNING in their code.'

check_compare "Facts-only predicate" "parent" \
'fact parent("a", "b")' \
"'parent' is only facts, so there's no rule to compare. Try a predicate defined by a rule."

check_compare "Undefined predicate" "nothing" \
'fact parent("a", "b")' \
"No facts or rules define 'nothing'"

finish_tests
