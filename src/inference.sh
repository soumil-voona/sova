#inference.sh
# shellcheck shell=bash
#
# Answers queries using the knowledge base built by kb_load. The search goes
# depth-first, takes goals left to right, and backtracks (the same strategy as Prolog).
#
# Terms:          a quoted string ("Alex") is a constant; a bare name (who) is
#                 a variable.
# Goal list:      goals joined by $GOAL_SEP; each goal is
#                 "<level> FS <name> FS <args>", where level is how deeply the
#                 goal is nested inside rules (0 = the query itself).
# Substitution:   variable bindings stored as one string, each entry
#                 "var=value" followed by $SUBST_SEP and the string starting
#                 with $SUBST_SEP. Strings are copied on every call, so
#                 backtracking needs no undo step: a failed branch just drops
#                 its copy. (Bash 3.2 on macOS has no associative arrays.)
# Proof:          one line per proved goal, joined by $PROOF_SEP, in the order
#                 they were proved:
#                 "<level> FS <name> FS <args> FS <F | A<KB_ALTS index>>"
#                 Arguments keep their variables; they are filled in from the
#                 final substitution once a solution is found.
#
# A predicate's clauses are tried facts first, then rules in source order.
# Each time a rule (or a fact containing variables) is used, its variables are
# renamed (x -> x#7) so recursive calls don't share them. Source names can't
# contain '#', so renamed variables never clash with the user's.
#
# The search stops going deeper at $SOVA_MAX_DEPTH steps. This keeps rules
# that call themselves forever (e.g. left recursion) from crashing Bash.
#
# Built-in goals:
#   comparisons (a > 18, x != "Bob"): both sides need values. <, >, <=, >=
#     compare integers; == and != compare numbers by value, anything else as text.
#   NOT p(x): true when p(x) can't be proved ("negation as failure"). Its
#     arguments need values first, since "NOT p(x)" with x unknown is ambiguous.
# A built-in that runs before its variables have values records an error, and
# the answer becomes UNKNOWN instead of a misleading FALSE.
#
# Set SOVA_BRIEF=1 to print answers without proofs or failure notes.

SUBST_SEP=$'\x1c'
PROOF_SEP=$'\x1a'
SOVA_MAX_DEPTH="${SOVA_MAX_DEPTH:-100}"
SOVA_BRIEF="${SOVA_BRIEF:-0}"
MAX_DEAD_ENDS=5

RENAME_COUNTER=0
QUERY_VARS=()
SOLUTIONS=()
SOLUTION_PROOFS=()
DEAD_ENDS=()
UNDEFINED=()
ERRORS=()
DEPTH_LIMIT_HIT=0

# split_on SEP TEXT -> SPLIT array. Pure parameter expansion (no subshells).
split_on() {
    local sep="$1" text="$2"
    SPLIT=()
    while [[ "$text" == *"$sep"* ]]; do
        SPLIT+=("${text%%"$sep"*}")
        text="${text#*"$sep"}"
    done
    SPLIT+=("$text")
}

# walk TERM SUBST -> WALKED: follows bindings until reaching a constant or an
# unbound variable.
walk() {
    local term="$1" subst="$2" rest
    while is_variable "$term" && [[ "$subst" == *"${SUBST_SEP}${term}="* ]]; do
        rest="${subst#*"${SUBST_SEP}${term}="}"
        term="${rest%%"$SUBST_SEP"*}"
    done
    WALKED="$term"
}

# resolve_args ARGS SUBST -> RESOLVED: ARGS (joined by $AST_AS) with
# variables filled in. Variables that are still unbound are shown as _.
resolve_args() {
    local subst="$2" term out=""
    local -a terms
    split_on "$AST_AS" "$1"
    terms=("${SPLIT[@]}")
    for term in "${terms[@]}"; do
        walk "$term" "$subst"
        term="$WALKED"
        is_variable "$term" && term="_"
        out="${out:+${out}${AST_AS}}${term}"
    done
    RESOLVED="$out"
}

# unify_args ARGS1 ARGS2 SUBST -> UNIFY_SUBST. Either side may hold variables.
# Fails if the argument counts differ or two constants disagree.
unify_args() {
    local -a left right
    local subst="$3" i a b
    split_on "$AST_AS" "$1"
    left=("${SPLIT[@]}")
    split_on "$AST_AS" "$2"
    right=("${SPLIT[@]}")
    [[ "${#left[@]}" -eq "${#right[@]}" ]] || return 1

    for ((i = 0; i < ${#left[@]}; i++)); do
        walk "${left[$i]}" "$subst"
        a="$WALKED"
        walk "${right[$i]}" "$subst"
        b="$WALKED"
        [[ "$a" == "$b" ]] && continue
        if is_variable "$a"; then
            subst+="${a}=${b}${SUBST_SEP}"
        elif is_variable "$b"; then
            subst+="${b}=${a}${SUBST_SEP}"
        else
            return 1
        fi
    done
    UNIFY_SUBST="$subst"
}

# rename_args ARGS SUFFIX -> RENAMED_ARGS
rename_args() {
    local suffix="$2" term out="" first=1
    split_on "$AST_AS" "$1"
    for term in "${SPLIT[@]}"; do
        is_variable "$term" && term+="#${suffix}"
        if [[ "$first" -eq 1 ]]; then
            out="$term"
            first=0
        else
            out+="${AST_AS}${term}"
        fi
    done
    RENAMED_ARGS="$out"
}

# rename_goals GOALS SUFFIX LEVEL -> RENAMED_GOALS
# GOALS are "<name> FS <args>" (as stored in KB_ALTS); the result has each
# goal prefixed with LEVEL.
rename_goals() {
    local suffix="$2" level="$3" goal out=""
    local -a goal_list
    split_on "$GOAL_SEP" "$1"
    goal_list=("${SPLIT[@]}")
    for goal in "${goal_list[@]}"; do
        rename_args "${goal#*"$AST_FS"}" "$suffix"
        out="${out:+${out}${GOAL_SEP}}${level}${AST_FS}${goal%%"$AST_FS"*}${AST_FS}${RENAMED_ARGS}"
    done
    RENAMED_GOALS="$out"
}

# True if any argument is a variable (not a quoted string or a number).
has_variables() {
    [[ "${AST_AS}$1" == *"${AST_AS}"[!\"0-9-]* ]]
}

# rule_label ALT_INDEX -> LABEL: describes the KB_ALTS entry that was used.
# "rule name", plus ", clause N" when the predicate has several rules and
# ", OR branch N" when the rule body has several OR alternatives.
rule_label() {
    local alt_index="$1" rule_index name i count=0 position=0 branches=0 branch=0
    rule_index="${KB_ALTS[$alt_index]%%"$AST_FS"*}"
    name="${KB_RULES[$rule_index]%%"$AST_FS"*}"
    for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
        [[ "${KB_RULES[$i]%%"$AST_FS"*}" == "$name" ]] || continue
        count=$((count + 1))
        [[ "$i" -eq "$rule_index" ]] && position="$count"
    done
    for ((i = 0; i < ${#KB_ALTS[@]}; i++)); do
        [[ "${KB_ALTS[$i]%%"$AST_FS"*}" == "$rule_index" ]] || continue
        branches=$((branches + 1))
        [[ "$i" -eq "$alt_index" ]] && branch="$branches"
    done
    LABEL="rule $name"
    [[ "$count" -gt 1 ]] && LABEL+=", clause $position"
    [[ "$branches" -gt 1 ]] && LABEL+=", OR branch $branch"
    return 0
}

# render_proof PROOF SUBST -> RENDERED: an indented tree, one goal per line.
render_proof() {
    local subst="$2" line level name args source indent out=""
    local -a lines fields
    split_on "$PROOF_SEP" "$1"
    lines=("${SPLIT[@]}")
    for line in "${lines[@]}"; do
        split_on "$AST_FS" "$line"
        fields=("${SPLIT[@]}")
        level="${fields[0]}"
        name="${fields[1]}"
        args="${fields[2]}"
        source="${fields[3]}"

        resolve_args "$args" "$subst"
        format_goal "$name" "$RESOLVED"
        case "$source" in
            F) LABEL="fact" ;;
            C) LABEL="comparison" ;;
            N) LABEL="not provable" ;;
            *) rule_label "${source#A}" ;;
        esac
        printf -v indent '%*s' $((4 + 2 * level)) ''
        out+="${indent}${FORMATTED}  [${LABEL}]"$'\n'
    done
    RENDERED="${out%$'\n'}"
}

# Saves the query variables' values (and the proof) as one answer,
# skipping answers already found.
record_solution() {
    local subst="$1" proof="$2" var answer="" existing
    for var in "${QUERY_VARS[@]}"; do
        walk "$var" "$subst"
        [[ -n "$answer" ]] && answer+=", "
        if is_variable "$WALKED"; then
            answer+="$var = (any value)"
        else
            answer+="$var = $WALKED"
        fi
    done
    for existing in "${SOLUTIONS[@]}"; do
        [[ "$existing" == "$answer" ]] && return 0
    done
    SOLUTIONS+=("$answer")
    render_proof "$proof" "$subst"
    SOLUTION_PROOFS+=("$RENDERED")
}

# solve GOALS SUBST DEPTH PROOF: proves every goal in GOALS and records each
# solution it finds. Every variable here must be local, since recursive
# calls would otherwise overwrite the caller's loop state.
solve() {
    local goals="$1" subst="$2" depth="$3" proof="$4"
    local goal rest level name args clause clause_args entry rule_index head body
    local suffix next step alt defined=0 matched=0

    if [[ -z "$goals" ]]; then
        record_solution "$subst" "$proof"
        return 0
    fi
    if ((depth >= SOVA_MAX_DEPTH)); then
        DEPTH_LIMIT_HIT=1
        return 0
    fi

    goal="${goals%%"$GOAL_SEP"*}"
    rest=""
    [[ "$goals" == *"$GOAL_SEP"* ]] && rest="${goals#*"$GOAL_SEP"}"
    level="${goal%%"$AST_FS"*}"
    goal="${goal#*"$AST_FS"}"
    name="${goal%%"$AST_FS"*}"
    args="${goal#*"$AST_FS"}"
    step="${level}${AST_FS}${name}${AST_FS}${args}${AST_FS}"
    proof="${proof:+${proof}${PROOF_SEP}}"

    if is_comparison "$name"; then
        solve_comparison "$name" "$args" "$subst" || return 0
        solve "$rest" "$subst" $((depth + 1)) "${proof}${step}C"
        return 0
    fi
    if [[ "$name" == "!"* ]]; then
        solve_not "${name#!}" "$args" "$subst" "$level" "$depth" || return 0
        solve "$rest" "$subst" $((depth + 1)) "${proof}${step}N"
        return 0
    fi

    # Facts
    for clause in "${KB_FACTS[@]}"; do
        [[ "${clause%%"$AST_FS"*}" == "$name" ]] || continue
        defined=1
        clause_args="${clause#*"$AST_FS"}"
        if has_variables "$clause_args"; then
            RENAME_COUNTER=$((RENAME_COUNTER + 1))
            rename_args "$clause_args" "$RENAME_COUNTER"
            clause_args="$RENAMED_ARGS"
        fi
        if unify_args "$args" "$clause_args" "$subst"; then
            matched=1
            solve "$rest" "$UNIFY_SUBST" $((depth + 1)) "${proof}${step}F"
        fi
    done

    # Rules: one entry per alternative body
    for ((alt = 0; alt < ${#KB_ALTS[@]}; alt++)); do
        entry="${KB_ALTS[$alt]}"
        rule_index="${entry%%"$AST_FS"*}"
        head="${KB_RULES[$rule_index]}"
        [[ "${head%%"$AST_FS"*}" == "$name" ]] || continue
        defined=1

        RENAME_COUNTER=$((RENAME_COUNTER + 1))
        suffix="$RENAME_COUNTER"
        rename_args "${head#*"$AST_FS"}" "$suffix"
        unify_args "$args" "$RENAMED_ARGS" "$subst" || continue
        matched=1
        next="$UNIFY_SUBST"

        rename_goals "${entry#*"$AST_FS"}" "$suffix" $((level + 1))
        body="$RENAMED_GOALS"
        solve "${body}${rest:+${GOAL_SEP}${rest}}" "$next" $((depth + 1)) \
            "${proof}${step}A${alt}"
    done

    # Remember why this branch failed, for explaining FALSE answers.
    if [[ "$defined" -eq 0 ]]; then
        add_unique UNDEFINED "$name"
    elif [[ "$matched" -eq 0 ]]; then
        resolve_args "$args" "$subst"
        format_goal "$name" "$RESOLVED"
        add_unique DEAD_ENDS "$FORMATTED"
    fi
    return 0
}

# Shows variables the way the user wrote them (drops "#7" rename suffixes).
source_name() {
    local text="$1"
    while [[ "$text" =~ (#[0-9]+) ]]; do
        text="${text/"${BASH_REMATCH[1]}"/}"
    done
    SOURCE_NAME="$text"
}

# number_value N -> NUMBER_VALUE, read as base 10 (so 007 is 7, not octal).
number_value() {
    local digits="$1" sign=1
    if [[ "$digits" == -* ]]; then
        sign=-1
        digits="${digits#-}"
    fi
    NUMBER_VALUE=$((sign * 10#$digits))
}

# solve_comparison OP ARGS SUBST: succeeds if the comparison holds.
solve_comparison() {
    local op="$1" subst="$3" left right a b
    left="${2%%"$AST_AS"*}"
    right="${2#*"$AST_AS"}"
    walk "$left" "$subst"
    a="$WALKED"
    walk "$right" "$subst"
    b="$WALKED"

    source_name "$left"
    local shown_left="$SOURCE_NAME"
    source_name "$right"
    local shown="$shown_left $op $SOURCE_NAME"
    if is_variable "$a"; then
        source_name "$a"
        add_unique ERRORS "'$shown' needs a value for '$SOURCE_NAME' (put the goal that sets it earlier)"
        return 1
    fi
    if is_variable "$b"; then
        source_name "$b"
        add_unique ERRORS "'$shown' needs a value for '$SOURCE_NAME' (put the goal that sets it earlier)"
        return 1
    fi

    local numbers=0 result=1 x=0 y=0
    if [[ "$a" =~ $NUMBER_PATTERN && "$b" =~ $NUMBER_PATTERN ]]; then
        numbers=1
        number_value "$a"
        x="$NUMBER_VALUE"
        number_value "$b"
        y="$NUMBER_VALUE"
    fi
    case "$op" in
        "==" | "!=")
            if [[ "$numbers" -eq 1 ]]; then
                ((x == y)) && result=0
            else
                [[ "$a" == "$b" ]] && result=0
            fi
            if [[ "$op" == "!=" ]]; then
                result=$((1 - result))
            fi
            ;;
        *)
            if [[ "$numbers" -eq 0 ]]; then
                add_unique ERRORS "'$a $op $b' can only compare numbers"
                return 1
            fi
            case "$op" in
                "<") ((x < y)) && result=0 ;;
                ">") ((x > y)) && result=0 ;;
                "<=") ((x <= y)) && result=0 ;;
                ">=") ((x >= y)) && result=0 ;;
            esac
            ;;
    esac

    if [[ "$result" -ne 0 ]]; then
        add_unique DEAD_ENDS "$a $op $b  (false)"
        return 1
    fi
    return 0
}

# solve_not NAME ARGS SUBST LEVEL DEPTH: succeeds if NAME(ARGS) can't be
# proved. Runs a separate search, saving and restoring the answer state.
solve_not() {
    local name="$1" subst="$3" level="$4" depth="$5" term
    local -a terms
    split_on "$AST_AS" "$2"
    terms=("${SPLIT[@]}")
    resolve_args "$2" "$subst"
    local ground="$RESOLVED"
    for term in "${terms[@]}"; do
        walk "$term" "$subst"
        if is_variable "$WALKED"; then
            format_goal "!$name" "$2"
            source_name "$FORMATTED"
            local shown="$SOURCE_NAME"
            source_name "$WALKED"
            add_unique ERRORS "'$shown' needs a value for '$SOURCE_NAME' (put the goal that sets it earlier)"
            return 1
        fi
    done

    local -a saved_vars=("${QUERY_VARS[@]}") saved_solutions=("${SOLUTIONS[@]}")
    local -a saved_proofs=("${SOLUTION_PROOFS[@]}") saved_dead=("${DEAD_ENDS[@]}")
    local -a saved_undefined=("${UNDEFINED[@]}")
    local saved_depth_hit="$DEPTH_LIMIT_HIT" found inner_depth_hit

    QUERY_VARS=()
    SOLUTIONS=()
    SOLUTION_PROOFS=()
    DEPTH_LIMIT_HIT=0
    solve "$((level + 1))${AST_FS}${name}${AST_FS}${ground}" "$SUBST_SEP" $((depth + 1)) ""
    found="${#SOLUTIONS[@]}"
    inner_depth_hit="$DEPTH_LIMIT_HIT"

    QUERY_VARS=("${saved_vars[@]}")
    SOLUTIONS=("${saved_solutions[@]}")
    SOLUTION_PROOFS=("${saved_proofs[@]}")
    DEAD_ENDS=("${saved_dead[@]}")
    UNDEFINED=("${saved_undefined[@]}")
    DEPTH_LIMIT_HIT="$saved_depth_hit"

    format_goal "!$name" "$ground"
    if [[ "$found" -gt 0 ]]; then
        add_unique DEAD_ENDS "$FORMATTED  (it can be proved)"
        return 1
    fi
    if [[ "$inner_depth_hit" -eq 1 ]]; then
        DEPTH_LIMIT_HIT=1
        return 1
    fi
    return 0
}

# Prints why a query failed: undefined predicates, then goals nothing matched.
explain_failure() {
    local entry shown=0
    for entry in "${UNDEFINED[@]}"; do
        echo "  No facts or rules define '$entry'"
    done
    [[ "${#DEAD_ENDS[@]}" -gt 0 ]] || return 0
    echo "  Dead ends (these goals could not be proved):"
    for entry in "${DEAD_ENDS[@]}"; do
        if [[ "$shown" -ge "$MAX_DEAD_ENDS" ]]; then
            echo "    ... and $((${#DEAD_ENDS[@]} - shown)) more"
            break
        fi
        echo "    $entry"
        shown=$((shown + 1))
    done
}

kb_ask() {
    local name="$1" args="$2" term var known i entry

    format_goal "$name" "$args"
    echo "ask $FORMATTED"

    QUERY_VARS=()
    SOLUTIONS=()
    SOLUTION_PROOFS=()
    DEAD_ENDS=()
    UNDEFINED=()
    ERRORS=()
    DEPTH_LIMIT_HIT=0
    split_on "$AST_AS" "$args"
    for term in "${SPLIT[@]}"; do
        is_variable "$term" || continue
        known=0
        for var in "${QUERY_VARS[@]}"; do
            [[ "$var" == "$term" ]] && known=1
        done
        [[ "$known" -eq 0 ]] && QUERY_VARS+=("$term")
    done

    solve "0${AST_FS}${name}${AST_FS}${args}" "$SUBST_SEP" 0 ""

    if [[ "${#SOLUTIONS[@]}" -gt 0 ]]; then
        for ((i = 0; i < ${#SOLUTIONS[@]}; i++)); do
            if [[ -n "${SOLUTIONS[$i]}" ]]; then
                echo "  ${SOLUTIONS[$i]}"
            elif [[ "$SOVA_BRIEF" -ne 1 ]]; then
                echo "  Proof:"
            fi
            [[ "$SOVA_BRIEF" -eq 1 ]] || echo "${SOLUTION_PROOFS[$i]}"
        done
        echo "  TRUE"
        if [[ "$DEPTH_LIMIT_HIT" -eq 1 ]]; then
            echo "  WARNING: stopped at depth limit ($SOVA_MAX_DEPTH); there may be more answers"
        fi
        for entry in "${ERRORS[@]}"; do
            echo "  WARNING: $entry; there may be more answers"
        done
    elif [[ "${#ERRORS[@]}" -gt 0 ]]; then
        echo "  UNKNOWN: some goals could not be checked"
        for entry in "${ERRORS[@]}"; do
            echo "  ERROR: $entry"
        done
        if [[ "$DEPTH_LIMIT_HIT" -eq 1 ]]; then
            echo "  WARNING: also stopped at depth limit ($SOVA_MAX_DEPTH)"
        fi
    elif [[ "$DEPTH_LIMIT_HIT" -eq 1 ]]; then
        echo "  UNKNOWN: depth limit ($SOVA_MAX_DEPTH) reached; a rule may be calling itself forever"
    else
        echo "  FALSE"
        [[ "$SOVA_BRIEF" -eq 1 ]] || explain_failure
    fi
}

kb_run_queries() {
    local query
    for query in "${KB_QUERIES[@]}"; do
        kb_ask "${query%%"$AST_FS"*}" "${query#*"$AST_FS"}"
        echo
    done
}
