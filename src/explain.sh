#explain.sh
# shellcheck shell=bash
# Sets globals that src/inference.sh and src/terms.sh read:
# shellcheck disable=SC2034
#
# Turns what the search recorded into explanations. The engine
# (src/inference.sh) only records data: a proof is a list of steps (goal,
# what proved it, how long the bindings were at that moment), and a failure
# is the path of steps that led to a dead end plus the reason. Everything
# here is generated from those steps, so any program is explained the same
# way, whatever its rules are.
#
#   explain_answer PROOF SUBST INDENT PREFIX   why an answer is true
#   explain_false NAME ARGS                    why a question is false
#
# A rule step reads:
#
#     grandparent("Alex", "Jamie") is satisfied by:
#       grandparent(x, z) if parent(x, y) AND parent(y, z)
#
#     Variable bindings:
#       x = "Alex"
#       ...
#
#     Proof:
#       parent("Alex", "Sam") is a fact.
#       ...
#
# and a failure walks through the rule that was tried, goal by goal: what
# each goal looked like before it was tried, what it matched, and why the
# last one failed.

# The steps being explained, one array per field.
P_LEVEL=()
P_NAME=()
P_ARGS=()
P_SRC=()
P_LEN=()
P_COUNT=0
EXPLAIN_SUBST=""

# explain_parse PROOF: splits a proof (or failure path) into the P_ arrays.
explain_parse() {
    local step
    local -a steps fields
    P_LEVEL=()
    P_NAME=()
    P_ARGS=()
    P_SRC=()
    P_LEN=()
    split_on "$PROOF_SEP" "$1"
    steps=("${SPLIT[@]}")
    for step in "${steps[@]}"; do
        split_on "$AST_FS" "$step"
        fields=("${SPLIT[@]}")
        P_LEVEL+=("${fields[0]}")
        P_NAME+=("${fields[1]}")
        P_ARGS+=("${fields[2]}")
        P_SRC+=("${fields[3]}")
        P_LEN+=("${fields[4]}")
    done
    P_COUNT="${#P_LEVEL[@]}"
}

# say INDENT TEXT
say() {
    local pad
    printf -v pad '%*s' "$1" ''
    if [[ -z "$2" ]]; then
        echo
    else
        printf '%s%s\n' "$pad" "$2"
    fi
}

# explain_children I -> CHILDREN: the steps that prove step I's goals
# (one level deeper, until the steps leave I's rule).
explain_children() {
    local i="$1" j level="${P_LEVEL[$1]}"
    CHILDREN=()
    for ((j = i + 1; j < P_COUNT; j++)); do
        [[ "${P_LEVEL[j]}" -le "$level" ]] && break
        [[ "${P_LEVEL[j]}" -eq $((level + 1)) ]] && CHILDREN+=("$j")
    done
    return 0
}

# explain_after I -> AFTER: the first step after step I and everything that
# proves it ($P_COUNT if there is none).
explain_after() {
    local i="$1" j level="${P_LEVEL[$1]}"
    for ((j = i + 1; j < P_COUNT; j++)); do
        [[ "${P_LEVEL[j]}" -le "$level" ]] && break
    done
    AFTER="$j"
}

# explain_goal I SUBST [names] -> GOAL_TEXT: step I's goal with the values
# from SUBST filled in. With "names", values that aren't known show their
# variable names; otherwise they show as _.
explain_goal() {
    [[ "$3" == "names" ]] && RESOLVE_KEEP_NAMES=1
    resolve_args "${P_ARGS[$1]}" "$2"
    RESOLVE_KEEP_NAMES=0
    format_goal "${P_NAME[$1]}" "$RESOLVED"
    GOAL_TEXT="$FORMATTED"
}

# rule_source RULE_INDEX -> RULE_SOURCE: the rule as written, e.g.
# "grandparent(x, z) if parent(x, y) AND parent(y, z)".
rule_source() {
    local index="$1" goal op text
    format_goal "${KB_RULES[index]%%"$AST_FS"*}" "${KB_RULES[index]#*"$AST_FS"}"
    text="$FORMATTED if"
    for goal in "${KB_GOALS[@]}"; do
        [[ "${goal%%"$AST_FS"*}" == "$index" ]] || continue
        goal="${goal#*"$AST_FS"}"
        op="${goal%%"$AST_FS"*}"
        goal="${goal#*"$AST_FS"}"
        format_goal "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
        if [[ "$op" == "FIRST" ]]; then
            text+=" $FORMATTED"
        else
            text+=" $op $FORMATTED"
        fi
    done
    RULE_SOURCE="$text"
}

# alt_branch ALT -> BRANCH_TEXT (the goals of one OR branch, joined by
# AND), and BRANCH_COUNT (how many branches the rule has).
alt_branch() {
    local alt="$1" rule_index goal text="" i
    local -a goals
    rule_index="${KB_ALTS[alt]%%"$AST_FS"*}"
    split_on "$GOAL_SEP" "${KB_ALTS[alt]#*"$AST_FS"}"
    goals=("${SPLIT[@]}")
    for goal in "${goals[@]}"; do
        format_goal "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
        text="${text:+${text} AND }$FORMATTED"
    done
    BRANCH_TEXT="$text"
    BRANCH_COUNT=0
    for ((i = 0; i < ${#KB_ALTS[@]}; i++)); do
        [[ "${KB_ALTS[i]%%"$AST_FS"*}" == "$rule_index" ]] && BRANCH_COUNT=$((BRANCH_COUNT + 1))
    done
}

# alt_vars ALT -> ALT_VARS: the variables of a rule's head and one of its
# branches, in the order the proof uses them: the branch's goals first,
# then any that only appear in the head.
alt_vars() {
    local alt="$1" rule_index term goal
    local -a goals terms
    rule_index="${KB_ALTS[alt]%%"$AST_FS"*}"
    ALT_VARS=()
    TERM_VARS=()
    split_on "$GOAL_SEP" "${KB_ALTS[alt]#*"$AST_FS"}"
    goals=("${SPLIT[@]}")
    for goal in "${goals[@]}"; do
        # Inside collect or count, variables take a new value for each
        # answer, so only the result belongs to the rule.
        if is_gather "${goal%%"$AST_FS"*}"; then
            gather_parts "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
            term_vars "$GATHER_RESULT"
            continue
        fi
        split_on "$AST_AS" "${goal#*"$AST_FS"}"
        terms=("${SPLIT[@]}")
        for term in "${terms[@]}"; do
            if is_expression "$term"; then
                expr_vars "$term"
                TERM_VARS+=("${EXPR_VARS[@]}")
            else
                term_vars "$term"
            fi
        done
    done
    split_on "$AST_AS" "${KB_RULES[rule_index]#*"$AST_FS"}"
    terms=("${SPLIT[@]}")
    for term in "${terms[@]}"; do
        term_vars "$term"
    done
    for term in "${TERM_VARS[@]}"; do
        add_unique ALT_VARS "$term"
    done
    return 0
}

# say_rule INDENT ALT: the rule a step used, and (for a rule with OR) which
# branch.
say_rule() {
    local indent="$1" alt="$2"
    rule_source "${KB_ALTS[alt]%%"$AST_FS"*}"
    say "$indent" "$RULE_SOURCE"
    alt_branch "$alt"
    [[ "$BRANCH_COUNT" -gt 1 ]] && say "$indent" "(using: $BRANCH_TEXT)"
    return 0
}

# list_length TERM SUBST -> LIST_LENGTH
list_length() {
    local term
    walk "$1" "$2"
    term="$WALKED"
    LIST_LENGTH=0
    while is_cell "$term"; do
        LIST_LENGTH=$((LIST_LENGTH + 1))
        walk "${CELL_TAIL[${term#@}]}" "$2"
        term="$WALKED"
    done
}

# plural N WORD -> PLURAL: "1 answer", "2 answers"
plural() {
    if [[ "$1" -eq 1 ]]; then
        PLURAL="1 $2"
    else
        PLURAL="$1 ${2}s"
    fi
}

# --- Why something is true ----------------------------------------------

# explain_answer PROOF SUBST INDENT PREFIX: explains the first step of
# PROOF (the question's own goal), starting the first line with PREFIX
# (such as "Because ").
explain_answer() {
    explain_parse "$1"
    EXPLAIN_SUBST="$2"
    explain_step 0 "$3" "$4"
}

# explain_step I INDENT PREFIX
explain_step() {
    local i="$1" indent="$2" prefix="$3" src="${P_SRC[$1]}" goal
    explain_goal "$i" "$EXPLAIN_SUBST"
    goal="$GOAL_TEXT"
    case "$src" in
        F*)
            local fact="${KB_FACTS[${src#F}]}"
            if has_variables "${fact#*"$AST_FS"}"; then
                format_goal "${fact%%"$AST_FS"*}" "${fact#*"$AST_FS"}"
                say "$indent" "${prefix}${goal} is a fact (from the fact $FORMATTED)."
            else
                say "$indent" "${prefix}${goal} is a fact."
            fi
            ;;
        C)
            say "$indent" "${prefix}${goal} is true."
            ;;
        E)
            explain_equals "$i"
            say "$indent" "${prefix}${EQUALS_TEXT}"
            ;;
        N)
            say "$indent" "${prefix}${goal}: ${goal#NOT } can't be proved."
            ;;
        G)
            # The template and inner variables take a value per answer, so
            # show their names rather than _.
            explain_goal "$i" "$EXPLAIN_SUBST" names
            goal="$GOAL_TEXT"
            gather_parts "${P_NAME[$i]}" "${P_ARGS[$i]}"
            if [[ "$GATHER_KIND" == "count" ]]; then
                walk "$GATHER_RESULT" "$EXPLAIN_SUBST"
                plural "$WALKED" answer
                say "$indent" "${prefix}${goal}: counted $PLURAL."
            else
                list_length "$GATHER_RESULT" "$EXPLAIN_SUBST"
                plural "$LIST_LENGTH" answer
                say "$indent" "${prefix}${goal}: collected $PLURAL."
            fi
            ;;
        B)
            say "$indent" "${prefix}${goal} is true (built-in)."
            ;;
        A*)
            explain_rule_step "$i" "$indent" "$prefix" "$goal"
            ;;
    esac
}

# explain_equals I -> EQUALS_TEXT: an = step. When one side is a variable,
# show it with how its value came about: "m = 2 - 1 = 1" for a
# calculation, "word = "hello"" for a match. Otherwise "... is true."
explain_equals() {
    local i="$1" left right var="" other value
    left="${P_ARGS[$i]%%"$AST_AS"*}"
    right="${P_ARGS[$i]#*"$AST_AS"}"
    if is_variable "$left"; then
        var="$left"
        other="$right"
    elif is_variable "$right"; then
        var="$right"
        other="$left"
    fi
    if [[ -z "$var" ]]; then
        explain_goal "$i" "$EXPLAIN_SUBST"
        EQUALS_TEXT="$GOAL_TEXT is true."
        return 0
    fi
    term_text "$var" "$EXPLAIN_SUBST"
    value="$TERM_TEXT"
    if is_expression "$other"; then
        resolve_args "$other" "$EXPLAIN_SUBST"
        expr_pretty "$RESOLVED"
        EQUALS_TEXT="${var%%#*} = $PRETTY = $value (calculated)."
    elif is_cell "$other"; then
        # A list pattern: show the pattern as written.
        term_text "$other"
        source_name "$TERM_TEXT"
        EQUALS_TEXT="${var%%#*} = $value matches $SOURCE_NAME."
    elif is_variable "$other"; then
        EQUALS_TEXT="${var%%#*} = $value (matched)."
    else
        EQUALS_TEXT="${var%%#*} = $value."
    fi
}

# explain_rule_step I INDENT PREFIX GOAL: a goal proved by a rule.
explain_rule_step() {
    local i="$1" indent="$2" prefix="$3" goal="$4" src="${P_SRC[$1]}" var value
    local alt="${src#A}" suffix
    alt="${alt%%.*}"
    suffix="${src#*.}"

    say "$indent" "${prefix}${goal} is satisfied by:"
    say_rule $((indent + 2)) "$alt"

    alt_vars "$alt"
    local -a vars=("${ALT_VARS[@]}")
    if [[ "${#vars[@]}" -gt 0 ]]; then
        say 0 ""
        say "$indent" "Variable bindings:"
        for var in "${vars[@]}"; do
            walk "${var}#${suffix}" "$EXPLAIN_SUBST"
            if is_variable "$WALKED"; then
                value="(any value)"
            else
                term_text "${var}#${suffix}" "$EXPLAIN_SUBST"
                value="$TERM_TEXT"
            fi
            say $((indent + 2)) "$var = $value"
        done
    fi

    explain_children "$i"
    local -a children=("${CHILDREN[@]}")
    local child n
    say 0 ""
    say "$indent" "Proof:"
    for ((n = 0; n < ${#children[@]}; n++)); do
        child="${children[n]}"
        # A rule inside the proof gets blank lines around it, so each
        # rule's explanation stands apart.
        if [[ "$n" -gt 0 && ( "${P_SRC[child]}" == A* || "${P_SRC[children[n - 1]]}" == A* ) ]]; then
            say 0 ""
        fi
        explain_step "$child" $((indent + 2)) ""
    done
}

# --- Why something is false ---------------------------------------------

ORDINALS=(First Second Third Fourth Fifth Sixth Seventh Eighth Ninth Tenth)

# explain_false NAME ARGS: why the question NAME(ARGS) has no answers, from
# the failures the search recorded (FAIL_KEYS, FAIL_PATHS, ...).
explain_false() {
    local name="$1" ref i has_facts=0 has_rules=0
    local -a ids
    ref="KBF_${name}[@]"
    ids=("${!ref}")
    [[ "${#ids[@]}" -gt 0 ]] && has_facts=1
    ref="KBA_${name}[@]"
    ids=("${!ref}")
    [[ "${#ids[@]}" -gt 0 ]] && has_rules=1
    is_text_builtin "$name" && has_rules=1

    if [[ "$has_facts" -eq 0 && "$has_rules" -eq 0 ]]; then
        say 0 "${C_BOLD}${C_RED}FALSE${C_RESET}:"
        say 2 "Nothing defines $name: there are no facts or rules for it."
        return 0
    fi

    local -a rule_groups=()
    for ((i = 0; i < ${#FAIL_KEYS[@]}; i++)); do
        [[ "${FAIL_KEYS[i]}" == A* ]] && rule_groups+=("$i")
    done

    if [[ "${#rule_groups[@]}" -eq 0 ]]; then
        say 0 "${C_BOLD}${C_RED}FALSE${C_RESET}:"
        local reason="Sova could not prove it."
        for ((i = 0; i < ${#FAIL_KEYS[@]}; i++)); do
            [[ "${FAIL_KEYS[i]}" == "top" ]] || continue
            explain_parse "${FAIL_PATHS[i]}"
            reason="${P_SRC[P_COUNT - 1]#X}"
        done
        if [[ "$reason" == "No matching fact exists." ]]; then
            say 2 "No matching fact exists."
            say 2 "No rule defines $name."
        elif [[ "$reason" == "No rule for "* ]]; then
            RESOLVE_KEEP_NAMES=1
            resolve_args "$2" "$SUBST_SEP"
            RESOLVE_KEEP_NAMES=0
            format_goal "$name" "$RESOLVED"
            [[ "$has_facts" -eq 1 ]] && say 2 "No matching fact exists."
            say 2 "No rule for $name matches $FORMATTED."
        else
            say 2 "$reason"
        fi
        return 0
    fi

    say 0 "${C_BOLD}${C_RED}FALSE${C_RESET}, because:"
    if [[ "$has_facts" -eq 1 ]]; then
        say 0 ""
        say 2 "No matching fact exists."
    fi
    local group others
    for group in "${rule_groups[@]}"; do
        say 0 ""
        explain_parse "${FAIL_PATHS[group]}"
        EXPLAIN_SUBST="${FAIL_PATH_SUBSTS[group]}"
        explain_tried 0 2
        others=$((FAIL_COUNTS[group] - 1))
        if [[ "$others" -gt 0 ]]; then
            say 0 ""
            if [[ "$others" -eq 1 ]]; then
                say 2 "Sova also tried 1 other way with this rule; it failed too."
            else
                say 2 "Sova also tried $others other ways with this rule; they failed too."
            fi
        fi
    done
}

# explain_tried I INDENT: step I was proved with a rule that then failed.
# Walks through that rule's goals in order, up to the one that failed.
explain_tried() {
    local i="$1" indent="$2" src="${P_SRC[$1]}" alt
    alt="${src#A}"
    alt="${alt%%.*}"
    say "$indent" "${C_BOLD}Tried:${C_RESET}"
    say_rule $((indent + 2)) "$alt"

    explain_children "$i"
    local -a children=("${CHILDREN[@]}")
    local child k=0 ordinal before
    for child in "${children[@]}"; do
        if [[ "$k" -lt 10 ]]; then
            ordinal="${ORDINALS[k]} goal"
        else
            ordinal="Goal $((k + 1))"
        fi
        k=$((k + 1))
        say 0 ""
        say "$indent" "${C_BOLD}$ordinal:${C_RESET}"
        before="${EXPLAIN_SUBST:0:${P_LEN[child]}}"
        explain_goal "$child" "$before" names
        say $((indent + 2)) "$GOAL_TEXT"
        say 0 ""
        explain_after "$child"
        if [[ "${P_SRC[child]}" == X* ]]; then
            say $((indent + 2)) "${C_BOLD}${C_RED}FAILED:${C_RESET}"
            say $((indent + 4)) "${P_SRC[child]#X}"
        elif [[ "${P_SRC[child]}" == A* && "$AFTER" -ge "$P_COUNT" ]]; then
            # The failure is inside this goal's own rule.
            explain_tried "$child" $((indent + 2))
        else
            explain_matched "$child" "$before" $((indent + 2))
        fi
    done
}

# explain_matched I BEFORE INDENT: a goal that worked, and the values it
# found (variables that had no value before it and have one after).
explain_matched() {
    local i="$1" before="$2" indent="$3" after_subst term var
    explain_after "$i"
    after_subst="${EXPLAIN_SUBST:0:${P_LEN[AFTER]}}"
    local -a terms found=()
    split_on "$AST_AS" "${P_ARGS[$i]}"
    terms=("${SPLIT[@]}")
    TERM_VARS=()
    for term in "${terms[@]}"; do
        if is_expression "$term"; then
            expr_vars "$term"
            TERM_VARS+=("${EXPR_VARS[@]}")
        else
            term_vars "$term"
        fi
    done
    local -a vars=("${TERM_VARS[@]}")
    for var in "${vars[@]}"; do
        walk "$var" "$before"
        is_variable "$WALKED" || continue
        walk "$var" "$after_subst"
        is_variable "$WALKED" && continue
        term_text "$var" "$after_subst"
        add_unique found "${var%%#*} = $TERM_TEXT"
    done
    if [[ "${#found[@]}" -gt 0 ]]; then
        say "$indent" "Matched:"
        for var in "${found[@]}"; do
            say $((indent + 2)) "$var"
        done
        return 0
    fi
    case "${P_SRC[$i]}" in
        F*) say "$indent" "Matched: it is a fact." ;;
        A*) say "$indent" "Matched: by the rule for ${P_NAME[$i]}." ;;
        *) say "$indent" "True." ;;
    esac
}
