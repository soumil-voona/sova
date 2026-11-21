#!/usr/bin/env bash
#test_stress.sh
#
# Regression and stress tests: recursion close to the depth limit, a large
# knowledge base, answers reached by many paths, and heavy backtracking.
# Programs are generated here so the sizes are easy to change. Sizes are kept
# where the whole file runs in well under a minute.

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# check_tail NAME FLAGS SOURCE LINES EXPECTED
# Like check_output, but only compares the last LINES lines of output.
check_tail() {
    local name="$1" flags="$2" source="$3" lines="$4" expected="$5"
    local temp_file actual
    temp_file=$(mktemp)
    printf '%s\n' "$source" > "$temp_file"
    # shellcheck disable=SC2086 # flags is intentionally word-split
    actual="$("$SOVA" $flags "$temp_file" 2>&1 | tail -n "$lines")"
    rm -f "$temp_file"
    test_dump "$name" "$actual"
    if [[ "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
}

# numbers_list FROM TO prints "FROM, FROM+1, ..., TO".
numbers_list() {
    local i out=""
    for ((i = $1; i <= $2; i++)); do
        out+="${out:+, }$i"
    done
    printf '%s' "$out"
}

# --- Deep recursion -------------------------------------------------------

COUNTDOWN='fact down(0)
rule down(n):
    n > 0
    AND m = n - 1
    AND down(m)'

# lib.sh sets the limit to 100: 99 nested rule calls fit, the 100th stops.
# down(99) is proved, but looking for more answers tries the rule for down(0)
# at depth 100, so Sova warns that the search was cut short there.
check_output "Recursion one call under the depth limit" "--brief" \
"$COUNTDOWN
ask down(99)" \
'ask down(99)
  TRUE
  WARNING: stopped at depth limit (100); there may be more answers'

check_output "Recursion that reaches the depth limit" "--brief" \
"$COUNTDOWN
ask down(100)" \
'ask down(100)
  UNKNOWN: depth limit (100) reached; a rule may be calling itself forever'

SOVA_MAX_DEPTH=400
check_output "A raised SOVA_MAX_DEPTH allows deeper recursion" "--brief" \
"$COUNTDOWN
ask down(350)" \
'ask down(350)
  TRUE'
SOVA_MAX_DEPTH=100

LENGTH='fact length([], 0)
rule length([h | t], n):
    length(t, m)
    AND n = m + 1'

check_output "Recursion over a 99-item list" "--brief" \
"$LENGTH
ask length([$(numbers_list 1 99)], n)" \
"ask length([$(numbers_list 1 99)], n)
  n = 99
  TRUE"

check_output "A list too long for the depth limit is UNKNOWN, not a crash" "--brief" \
"$LENGTH
ask length([$(numbers_list 1 150)], n)" \
"ask length([$(numbers_list 1 150)], n)
  UNKNOWN: depth limit (100) reached; a rule may be calling itself forever"

# --- Large knowledge base -------------------------------------------------

# A 2,000-edge chain, with the first 200 edges listed twice, and 1,000
# labels: 3,200 fact lines. Loading this many used to take over 20 seconds
# (a subshell per parsed line, and every fact compared with every earlier one).
big_kb() {
    local i
    for ((i = 1; i <= 2000; i++)); do echo "fact edge($i, $((i + 1)))"; done
    for ((i = 1; i <= 200; i++)); do echo "fact edge($i, $((i + 1)))"; done
    for ((i = 1; i <= 1000; i++)); do echo "fact label($i, \"n$i\")"; done
    cat <<'EOF'
rule reach(x, y):
    edge(x, y)
rule reach(x, y):
    edge(x, z)
    AND reach(z, y)
rule edges(n):
    count(edge(a, b), n)
rule into(y, x):
    edge(x, y)
EOF
}

check_output "Large knowledge base: lookups, duplicates, and long chains" "--brief" \
"$(big_kb)
ask edge(2000, x)
ask into(2000, x)
ask label(x, \"n977\")
ask edges(n)
ask reach(1920, 2001)
ask reach(2001, 1)" \
'ask edge(2000, x)
  x = 2001
  TRUE

ask into(2000, x)
  x = 1999
  TRUE

ask label(x, "n977")
  x = 977
  TRUE

ask edges(n)
  n = 2000
  TRUE

ask reach(1920, 2001)
  TRUE

ask reach(2001, 1)
  FALSE'

# --- Repeated answers -----------------------------------------------------

# s -> a1..a3 -> b1..b3 -> c1..c3 -> d1..d3 -> t, every layer fully
# connected: 81 different paths from s to t, but each node is one answer.
layered_graph() {
    local layer next i j
    for j in 1 2 3; do echo "fact e(\"s\", \"a$j\")"; done
    for layer in a b c; do
        case "$layer" in a) next=b ;; b) next=c ;; c) next=d ;; esac
        for i in 1 2 3; do
            for j in 1 2 3; do echo "fact e(\"$layer$i\", \"$next$j\")"; done
        done
    done
    for j in 1 2 3; do echo "fact e(\"d$j\", \"t\")"; done
    cat <<'EOF'
rule path(x, y):
    e(x, y)
rule path(x, y):
    e(x, z)
    AND path(z, y)
rule ends(n):
    count(path("s", w), n)
rule order(l):
    collect(w, path("s", w), l)
EOF
}

check_output "Answers reached by many paths appear once, in first-found order" "--brief" \
"$(layered_graph)
ask path(\"s\", \"t\")
ask path(w, \"t\")
ask ends(n)
ask order(l)" \
'ask path("s", "t")
  TRUE

ask path(w, "t")
  w = "d1"
  w = "d2"
  w = "d3"
  w = "s"
  w = "a1"
  w = "a2"
  w = "a3"
  w = "b1"
  w = "b2"
  w = "b3"
  w = "c1"
  w = "c2"
  w = "c3"
  TRUE

ask ends(n)
  n = 13
  TRUE

ask order(l)
  l = ["a1", "a2", "a3", "b1", "b2", "b3", "c1", "c2", "c3", "d1", "d2", "d3", "t"]
  TRUE'

# --- Backtracking ---------------------------------------------------------

PERMS='fact select(x, [x | t], t)
rule select(x, [h | t], [h | r]):
    select(x, t, r)
fact perm([], [])
rule perm(l, [h | t]):
    select(h, l, r)
    AND perm(r, t)
rule nperms(n):
    count(perm([1, 2, 3, 4], p), n)'

QUEENS='fact safe([])
rule safe([q | qs]):
    noattack(q, qs, 1)
    AND safe(qs)
fact noattack(q, [], d)
rule noattack(q, [q1 | qs], d):
    q1 - q != d
    AND q - q1 != d
    AND d1 = d + 1
    AND noattack(q, qs, d1)
rule queens(qs):
    perm([1, 2, 3, 4], qs)
    AND safe(qs)
rule last_perm(p):
    perm([1, 2, 3, 4], p)
    AND p = [4, 3, 2, 1]'

check_output "Permutations and 4-queens" "--brief" \
"$PERMS
$QUEENS
ask queens(qs)
ask nperms(n)
ask last_perm(p)" \
'ask queens(qs)
  qs = [2, 4, 1, 3]
  qs = [3, 1, 4, 2]
  TRUE

ask nperms(n)
  n = 24
  TRUE

ask last_perm(p)
  p = [4, 3, 2, 1]
  TRUE'

# Mainland Australia with three colors: 6 colorings in all.
COLORING='fact color("red")
fact color("green")
fact color("blue")
rule coloring(wa, nt, sa, q, nsw, v):
    color(wa)
    AND color(nt)
    AND color(sa)
    AND wa != nt
    AND wa != sa
    AND nt != sa
    AND color(q)
    AND q != nt
    AND q != sa
    AND color(nsw)
    AND nsw != q
    AND nsw != sa
    AND color(v)
    AND v != sa
    AND v != nsw
rule first_coloring(wa, nt, sa, q, nsw, v):
    coloring(wa, nt, sa, q, nsw, v)
    AND wa == "blue"
    AND nt == "green"
rule colorings(n):
    count(coloring(a, b, c, d, e, f), n)'

check_output "Map coloring backtracks through every choice" "--brief" \
"$COLORING
ask first_coloring(wa, nt, sa, q, nsw, v)
ask colorings(n)" \
'ask first_coloring(wa, nt, sa, q, nsw, v)
  wa = "blue", nt = "green", sa = "red", q = "blue", nsw = "green", v = "blue"
  TRUE

ask colorings(n)
  n = 6
  TRUE'

export SOVA_TRACE_LIMIT=5
check_tail "A long trace stops printing but the search finishes" "--trace --brief" \
"$PERMS
ask nperms(n)" 6 \
'  ... the trace stops here, after 5 goals (set SOVA_TRACE_LIMIT to see more); the search keeps going.
  Search finished: 1 answer, 196 goals tried (the trace shows the first 5).

  n = 24
  TRUE'
unset SOVA_TRACE_LIMIT

finish_tests
