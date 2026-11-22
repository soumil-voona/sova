#!/usr/bin/env bash
#translation_lib.sh
#
# Shared by test_python.sh and test_javascript.sh. Each case generates a
# program with ./sova FLAG TARGET FILE, runs it, and checks that it prints
# the same answers, in the same order, as Sova itself.
#
# Before calling run_translation_tests, set:
#   TRANSLATE_FLAG   --python or --javascript
#   RUN_PROGRAM      command that runs a generated file (e.g. "python3 -I")
#   CHECK_PROGRAM    command that only checks a file's syntax
#   PROGRAM_EXT      file extension for generated programs (.py, .js)

# shellcheck source=tests/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXAMPLES="$TEST_DIR/../examples"
CASES="$TEST_DIR/translations"

# new_program -> PROGRAM: an empty file with the right extension (tools
# like node read the extension, and mktemp names contain dots).
new_program() {
    PROGRAM_DIR=$(mktemp -d)
    PROGRAM="$PROGRAM_DIR/program$PROGRAM_EXT"
}

# normalize: how answers are compared. Languages print lists and strings
# differently (["a", "b"], ['a', 'b'], ["a","b"]), so quotes and spaces
# inside brackets are dropped.
normalize() {
    sed -E "s/[\"']//g; s/\[ /[/g; s/ \]/]/g; s/,([^ ])/, \1/g"
}

# sova_answers FILE TARGET [INPUT]: Sova's answers as the programs print
# them: one line per answer, values separated by spaces. A query with no
# variables prints TRUE or FALSE. Lines the program itself prints (print in
# a rule) are kept as they are. INPUT is given to Sova's read built-ins.
sova_answers() {
    local temp_file line has_vars=0
    temp_file=$(mktemp)
    grep -v '^[[:space:]]*ask ' "$1" > "$temp_file"
    printf 'ask %s\n' "$2" >> "$temp_file"
    [[ "$2" =~ \([^\"]*[a-z_] || "$2" =~ ,[[:space:]]*[a-z_] ]] && has_vars=1
    printf '%s' "$3" | SOVA_MAX_DEPTH=200 "$SOVA" --brief "$temp_file" 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            "ask "* | "") ;;
            "  TRUE")  [[ "$has_vars" -eq 1 ]] || echo "TRUE" ;;
            "  FALSE")
                if [[ "$has_vars" -eq 1 ]]; then
                    echo "(no answers)"
                else
                    echo "FALSE"
                fi
                ;;
            "  "*" = "*)
                # "x = [1, 2], y = 3" -> "[1, 2] 3": split before each
                # ", name = " (not on commas inside lists).
                line="${line#  }"
                printf '%s\n' "$line" | perl -pe 's/, (?=[a-z_][a-z0-9_]* = )/\t/g; s/(^|\t)[a-z_][a-z0-9_]* = /$1/g; s/\t/ /g'
                ;;
            "  "*) ;;
            *) printf '%s\n' "$line" ;;
        esac
    done | normalize
    rm -f "$temp_file"
}

# check_translation NAME FILE TARGET [INPUT]
check_translation() {
    local name="$1" file="$2" target="$3" input="${4-}" program expected actual
    new_program
    program="$PROGRAM"
    "$SOVA" "$TRANSLATE_FLAG" "$target" "$file" > "$program" 2>&1
    expected="$(sova_answers "$file" "$target" "$input")"
    # shellcheck disable=SC2086 # RUN_PROGRAM is a command with arguments
    actual="$(printf '%s' "$input" | $RUN_PROGRAM "$program" 2>&1 | normalize)"
    [[ -z "$actual" ]] && actual="(no answers)"
    if [[ -n "$expected" && "$actual" == "$expected" ]]; then
        echo "[PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] $name"
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /'
        FAIL=$((FAIL + 1))
    fi
    rm -rf "$PROGRAM_DIR"
}

run_translation_tests() {
    check_translation "grandparent, nothing known" "$EXAMPLES/family.sova" 'grandparent(x, z)'
    check_translation "grandparent, all known" "$EXAMPLES/family.sova" 'grandparent("Alex", "Jamie")'
    check_translation "grandparent, false" "$EXAMPLES/family.sova" 'grandparent("Sam", "Alex")'
    check_translation "ancestor, nothing known" "$EXAMPLES/ancestor.sova" 'ancestor(x, y)'
    check_translation "ancestor, first known" "$EXAMPLES/ancestor.sova" 'ancestor("Ada", who)'
    check_translation "ancestor, second known" "$EXAMPLES/ancestor.sova" 'ancestor(who, "Dev")'
    check_translation "ancestor, all known" "$EXAMPLES/ancestor.sova" 'ancestor("Ada", "Eli")'
    check_translation "OR branches" "$EXAMPLES/or.sova" 'caregiver(who, "Jamie")'
    check_translation "OR with nested rules" "$EXAMPLES/or.sova" 'pet_of_family("Mochi", who)'
    check_translation "Comparisons and NOT" "$EXAMPLES/club.sova" 'member(who)'
    check_translation "NOT, false" "$EXAMPLES/club.sova" 'member("Bob")'
    check_translation "Rule calling a rule" "$EXAMPLES/club.sova" 'can_bring("Ana", who)'
    check_translation "Constant in a rule head" "$EXAMPLES/club.sova" 'junior(who)'
    check_translation "Repeated variable" "$CASES/edge.sova" 'loop(n)'
    check_translation "NOT of a rule" "$CASES/edge.sova" 'root(r)'
    check_translation "Swapped head arguments" "$CASES/edge.sova" 'r(a, b)'
    check_translation "Swapped head arguments, one known" "$CASES/edge.sova" 'r("b", who)'
    check_translation "Swapped head arguments, all known" "$CASES/edge.sova" 'r("b", "a")'
    check_translation "Facts and rules together" "$CASES/edge.sova" 'likes(who, what)'
    check_translation "Negative numbers and ranges" "$CASES/edge.sova" 'mild(c)'
    check_translation "Keywords as names" "$CASES/names.sova" 'takes(who, what)'
    check_translation "Variables named like tables" "$CASES/names.sova" 'odd(a, b)'
    check_translation "Backslash in a string" "$CASES/names.sova" 'p(w)'
    check_translation "JavaScript keywords as names" "$CASES/names.sova" 'js_names(a, b)'
    check_translation "Factorial" "$CASES/arith.sova" 'factorial(10, f)'
    check_translation "Factorial, all known" "$CASES/arith.sova" 'factorial(5, 120)'
    check_translation "Collatz steps" "$CASES/arith.sova" 'steps(27, s)'
    check_translation "GCD with a fact containing variables" "$CASES/arith.sova" 'gcd(48, 18, g)'
    check_translation "Division rounds down" "$CASES/arith.sova" 'divs(-7, 2, q, r)'
    check_translation "Division with a negative divisor" "$CASES/arith.sova" 'divs(7, -2, q, r)'
    check_translation "Precedence and grouping" "$CASES/arith.sova" 'calc(a, b, c, d, e)'
    check_translation "= with the unknown on the right" "$CASES/arith.sova" 'triple(4, y)'
    check_translation "Expressions in comparisons" "$CASES/arith.sova" 'close(x, y)'
    check_translation "= with text and a computed comparison" "$CASES/arith.sova" 'labelled(x, u)'
    check_translation "length" "$EXAMPLES/lists.sova" 'length([5, 6, 7], n)'
    check_translation "sum" "$EXAMPLES/lists.sova" 'sum([1, 2, 3, 4], s)'
    check_translation "append" "$EXAMPLES/lists.sova" 'append([1, 2], [3], all)'
    check_translation "append backwards, splitting a list" "$EXAMPLES/lists.sova" 'append(front, back, [1, 2])'
    check_translation "member finding items" "$EXAMPLES/lists.sova" 'member(x, ["a", "b"])'
    check_translation "member checking an item" "$EXAMPLES/lists.sova" 'member("b", ["a", "b"])'
    check_translation "reverse with an accumulator" "$EXAMPLES/lists.sova" 'reverse([1, 2, 3], r)'
    check_translation "max of a list" "$EXAMPLES/lists.sova" 'max_of([3, 9, 2], m)'
    check_translation "insertion sort" "$EXAMPLES/lists.sova" 'sort([3, 1, 2, 5, 4], s)'
    check_translation "[head | tail] with =" "$CASES/lists.sova" 'split([1, 2, 3], h, t)'
    check_translation "[head | tail] on an empty list" "$CASES/lists.sova" 'split([], h, t)'
    check_translation "Several items and a tail" "$CASES/lists.sova" 'first_two([1, 2, 3, 4], a, b, r)'
    check_translation "Nested lists in a fact" "$CASES/lists.sova" 'second_pair_name(n)'
    check_translation "== on lists" "$CASES/lists.sova" 'same([1, [2]], [1, [2]])'
    check_translation "== on different lists" "$CASES/lists.sova" 'same([1, 2], [2, 1])'
    check_translation "NOT with a list" "$CASES/lists.sova" 'missing(5, [1, 2])'
    check_translation "Lists of text in facts" "$CASES/lists.sova" 'buys(who, item)'
    check_translation "An empty list in a goal" "$CASES/lists.sova" 'empty_basket(w)'
    check_translation "collect" "$CASES/gather.sova" 'children("Ada", k)'
    check_translation "collect with no answers" "$CASES/gather.sova" 'children("Cy", k)'
    check_translation "count" "$CASES/gather.sova" 'how_many("Ada", n)'
    check_translation "count, all known" "$CASES/gather.sova" 'how_many("Ben", 1)'
    check_translation "count after a generator" "$CASES/gather.sova" 'big_family(p)'
    check_translation "collect pairs over a rule" "$CASES/gather.sova" 'kid_ages("Ada", a)'
    check_translation "Summing a collected list" "$CASES/gather.sova" 'total_age("Ada", t)'
    check_translation "count over every row" "$CASES/gather.sova" 'everyone_counted(n)'
    check_translation "concat joining text" "$CASES/text.sova" 'greet("Sam", m)'
    check_translation "chars and reverse: a palindrome" "$CASES/text.sova" 'palindrome("level")'
    check_translation "Not a palindrome" "$CASES/text.sova" 'palindrome("sova")'
    check_translation "chars both ways" "$CASES/text.sova" 'shout("hi", l)'
    check_translation "text_length in a comparison" "$CASES/text.sova" 'long_word("banana")'
    check_translation "concat taking off an ending" "$CASES/text.sova" 'suffix_of("walking", "ing", s)'
    check_translation "concat splitting every way" "$CASES/text.sova" 'splits("abc", a, b)'
    check_translation "Decimal facts and a sum" "$CASES/decimals.sova" 'total("tea", "cake", t)'
    check_translation "Comparing decimals" "$CASES/decimals.sova" 'cheap(item)'
    check_translation "Decimal arithmetic" "$CASES/decimals.sova" 'calc(name, v)'
    check_translation "Whole numbers still round down" "$CASES/decimals.sova" 'halves(7, h)'
    check_translation "Decimal division" "$CASES/decimals.sova" 'share(10.5, 4, s)'
    check_translation "print in a rule" "$CASES/io.sova" 'hello("Sam")'
    check_translation "read a line" "$CASES/io.sova" 'greet(m)' $'Ada\n'
    check_translation "read_number and print" "$CASES/io.sova" 'add(total)' $'3\n4.25\n'
    check_translation "read at the end of the input" "$CASES/io.sova" 'greet(m)' ''
    check_translation "print for every answer" "$CASES/io.sova" 'show_all(x)'

    # Every example rule should at least pass a syntax check.
    local file name program compiled=0 failed=""
    local -a names
    for file in "$EXAMPLES"/*.sova; do
        names=()
        while IFS= read -r name; do
            names+=("$name")
        done < <(grep -oE '^rule [a-z_]+' "$file" | awk '{print $2}' | sort -u)
        for name in "${names[@]}"; do
            new_program
            program="$PROGRAM"
            "$SOVA" "$TRANSLATE_FLAG" "$name" "$file" > "$program" 2>&1
            # shellcheck disable=SC2086 # CHECK_PROGRAM is a command with arguments
            if $CHECK_PROGRAM "$program" > /dev/null 2>&1; then
                compiled=$((compiled + 1))
            else
                failed+=" $(basename "$file"):$name"
            fi
            rm -rf "$PROGRAM_DIR"
        done
    done
    if [[ -z "$failed" ]]; then
        echo "[PASS] All $compiled example rules pass a syntax check"
        PASS=$((PASS + 1))
    else
        echo "[FAIL] These fail a syntax check:$failed"
        FAIL=$((FAIL + 1))
    fi
}
