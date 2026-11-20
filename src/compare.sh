#compare.sh
# shellcheck shell=bash
#
# compare_paradigms TARGET shows one predicate written three ways:
#   1. logic (the Sova rules): says what is true
#   2. imperative Python: spells out each step with loops and ifs
#   3. functional Python: describes the results as list comprehensions
# then a table of how the ideas map between them (only the ideas this
# predicate uses), and the answer, which is the same in all three.

# compare_collect NAME: adds NAME and every rule predicate it uses (through
# its goals, including NOT goals) to COMPARE_RULES, in the order first seen.
# Fact tables it reads go in COMPARE_TABLES.
compare_collect() {
    local name="$1" entry rule_index goal goal_name
    local -a goals
    if ! pred_has_rules "$name"; then
        add_unique COMPARE_TABLES "$name"
        return 0
    fi
    for entry in "${COMPARE_RULES[@]}"; do
        [[ "$entry" == "$name" ]] && return 0
    done
    COMPARE_RULES+=("$name")
    pred_has_facts "$name" && add_unique COMPARE_TABLES "$name"
    for entry in "${KB_ALTS[@]}"; do
        rule_index="${entry%%"$AST_FS"*}"
        [[ "${KB_RULES[$rule_index]%%"$AST_FS"*}" == "$name" ]] || continue
        [[ "${KB_RULES[$rule_index]}${entry}" == *"@"* ]] && COMPARE_USES_LISTS=1
        split_on "$GOAL_SEP" "${entry#*"$AST_FS"}"
        goals=("${SPLIT[@]}")
        for goal in "${goals[@]}"; do
            goal_name="${goal%%"$AST_FS"*}"
            if [[ "$goal_name" == "=" ]]; then
                COMPARE_USES_CALCULATION=1
                continue
            fi
            if is_gather "$goal_name"; then
                COMPARE_USES_GATHER=1
                goal_name="${goal_name#*:}"
            fi
            if is_text_builtin "$goal_name" && ! pred_has_rules "$goal_name" &&
                ! pred_has_facts "$goal_name"; then
                COMPARE_USES_TEXT=1
                continue
            fi
            if is_comparison "$goal_name"; then
                COMPARE_USES_COMPARISON=1
                continue
            fi
            if [[ "$goal_name" == "!"* ]]; then
                COMPARE_USES_NOT=1
                goal_name="${goal_name#!}"
            fi
            [[ "$goal_name" == "$name" ]] && COMPARE_USES_RECURSION=1
            compare_collect "$goal_name"
        done
    done
}

# Prints the Sova source of every collected rule -> also sets COMPARE_LINES.
compare_print_rules() {
    local name i goal op count=0
    COMPARE_LINES=0
    for name in "${COMPARE_RULES[@]}"; do
        for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
            [[ "${KB_RULES[$i]%%"$AST_FS"*}" == "$name" ]] || continue
            count=$((count + 1))
            format_goal "$name" "${KB_RULES[$i]#*"$AST_FS"}"
            echo "    rule $FORMATTED:"
            COMPARE_LINES=$((COMPARE_LINES + 1))
            for goal in "${KB_GOALS[@]}"; do
                [[ "${goal%%"$AST_FS"*}" == "$i" ]] || continue
                goal="${goal#*"$AST_FS"}"
                op="${goal%%"$AST_FS"*}"
                [[ "$op" == "OR" ]] && COMPARE_USES_ALTERNATIVES=1
                goal="${goal#*"$AST_FS"}"
                format_goal "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
                if [[ "$op" == "FIRST" ]]; then
                    echo "        $FORMATTED"
                else
                    echo "        $op $FORMATTED"
                fi
                COMPARE_LINES=$((COMPARE_LINES + 1))
            done
        done
        [[ "$count" -gt 1 ]] && COMPARE_USES_ALTERNATIVES=1
        count=0
    done
}

# compare_code_lines TEXT -> CODE_LINES: lines that aren't blank, comments,
# or docstrings.
compare_code_lines() {
    local line
    CODE_LINES=0
    while IFS= read -r line; do
        line="$(trim "$line")"
        [[ -z "$line" || "$line" == "#"* || "$line" == '"""'* ]] && continue
        CODE_LINES=$((CODE_LINES + 1))
    done <<< "$1"
}

compare_row() {
    printf '    %-26s %-34s %s\n' "$1" "$2" "$3"
}

compare_paradigms() {
    local target="$1" name args imperative functional table facts=0 fact
    COMPARE_RULES=()
    COMPARE_TABLES=()
    COMPARE_USES_COMPARISON=0
    COMPARE_USES_CALCULATION=0
    COMPARE_USES_LISTS=0
    COMPARE_USES_GATHER=0
    COMPARE_USES_TEXT=0
    COMPARE_USES_NOT=0
    COMPARE_USES_RECURSION=0
    COMPARE_USES_ALTERNATIVES=0

    if [[ "$target" =~ $NAME_PATTERN ]]; then
        name="$target"
    elif parse_call "$target"; then
        name="$CALL_NAME"
    else
        echo "Expected a predicate name or call, like ancestor or ancestor(\"Ada\", who)" >&2
        return 1
    fi
    if ! pred_has_rules "$name"; then
        if pred_has_facts "$name"; then
            echo "'$name' is only facts, so there's no rule to compare. Try a predicate defined by a rule." >&2
        else
            echo "No facts or rules define '$name'" >&2
        fi
        return 1
    fi

    compare_collect "$name"
    # TRANSLATE_FUNCTIONS_ONLY is read by translate_to (src/pseudocode.sh).
    # shellcheck disable=SC2034
    TRANSLATE_FUNCTIONS_ONLY=1
    imperative="$(translate_to python "$target")"
    functional="$(translate_to functional "$target")"
    # shellcheck disable=SC2034
    TRANSLATE_FUNCTIONS_ONLY=0

    if [[ "$target" =~ $NAME_PATTERN ]]; then
        pred_params "$name"
        args="$(join_args "${PARAMS[@]}")"
    else
        args="$CALL_ARGS"
    fi
    format_goal "$name" "$args"
    echo "Three ways to write $FORMATTED"
    echo

    echo "1. Logic (Sova): say what is true, and let Sova search for answers"
    echo
    compare_print_rules
    for table in "${COMPARE_TABLES[@]}"; do
        for fact in "${KB_FACTS[@]}"; do
            [[ "${fact%%"$AST_FS"*}" == "$table" ]] && facts=$((facts + 1))
        done
    done
    echo
    echo "    $COMPARE_LINES lines, plus $facts facts"
    echo

    echo "2. Imperative (Python): spell out each step with loops and ifs"
    echo
    printf '%s\n' "${imperative%$'\n'}" | sed 's/^/    /'
    compare_code_lines "$imperative"
    echo
    echo "    $CODE_LINES lines of code, plus the same facts as lists"
    echo

    echo "3. Functional (Python): describe the results as list comprehensions"
    echo
    printf '%s\n' "${functional%$'\n'}" | sed 's/^/    /'
    compare_code_lines "$functional"
    echo
    if [[ "$functional" == *"return unique("* ]]; then
        echo "    $CODE_LINES lines of code, plus the facts and a 3-line unique() helper"
    else
        echo "    $CODE_LINES lines of code, plus the same facts as lists"
    fi
    echo

    echo "How the ideas map"
    echo
    compare_row "Sova" "Imperative" "Functional"
    compare_row "----" "----------" "----------"
    compare_row "fact" "a row in a list" "a row in a list"
    compare_row "rule" "a function" "a function returning a list"
    compare_row "AND, goal finds values" "a nested for loop" "a for clause"
    compare_row "AND, goal only checks" "an if" "an if clause"
    if [[ "$COMPARE_USES_COMPARISON" -eq 1 ]]; then
        compare_row "comparison (a >= 18)" "an if (if a >= 18:)" "an if clause (if a >= 18)"
    fi
    if [[ "$COMPARE_USES_CALCULATION" -eq 1 ]]; then
        compare_row "calculation (m = n - 1)" "an assignment (m = n - 1)" "for m in [n - 1]"
    fi
    if [[ "$COMPARE_USES_LISTS" -eq 1 ]]; then
        compare_row "list pattern [h | t]" "check it's a list; h = l[0]" "the same, as for clauses"
        compare_row "" "and t = l[1:]" ""
    fi
    if [[ "$COMPARE_USES_GATHER" -eq 1 ]]; then
        compare_row "collect / count" "a loop adding to a list" "[x for ...] / sum(1 for ...)"
    fi
    if [[ "$COMPARE_USES_TEXT" -eq 1 ]]; then
        compare_row "concat / chars / text_length" "a + b, list(t), len(t)" "the same"
    fi
    if [[ "$COMPARE_USES_NOT" -eq 1 ]]; then
        compare_row "NOT p(x)" "if x not in p / not is_p(x)" "the same, as an if clause"
    fi
    if [[ "$COMPARE_USES_ALTERNATIVES" -eq 1 ]]; then
        compare_row "another clause, or OR" "another block adding results" "another list joined with +"
    fi
    if [[ "$COMPARE_USES_RECURSION" -eq 1 ]]; then
        compare_row "a rule using itself" "a function calling itself" "a function calling itself"
    fi
    compare_row "variable" "a loop variable" "a comprehension variable"
    compare_row "trying the next match" "the loop moves to the next row" "the comprehension does too"
    compare_row "each answer once" "a seen set" "unique()"
    echo

    echo "Sova's answer"
    echo
    if [[ "$target" =~ $NAME_PATTERN ]]; then
        pred_params "$name"
        args="$(join_args "${PARAMS[@]}")"
    else
        parse_call "$target"
        args="$CALL_ARGS"
    fi
    local saved_brief="$SOVA_BRIEF"
    SOVA_BRIEF=1
    kb_ask "$name" "$args" | sed 's/^/    /'
    SOVA_BRIEF="$saved_brief"
    echo
    if [[ "$imperative" == *"call itself forever"* ]]; then
        echo "    The Python versions would keep calling themselves until Python stops"
        echo "    them with a RecursionError: see the WARNING in their code."
    else
        echo "    Both Python versions compute the same answers, in the same order."
    fi
}
