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
#                 goal is nested inside rules (0 = the query itself). The
#                 level may be followed by $CHAIN_SEP and the chain of fully
#                 known rule calls this goal is part of (see run_search).
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
# The search stops at $SOVA_MAX_DEPTH levels of rules calling rules. This
# keeps rules that call themselves forever (e.g. left recursion) from
# running until they run out of memory.
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
CHAIN_SEP=$'\x03'
CHAIN_ITEM=$'\x02'
PROOF_SEP=$'\x1a'
SOVA_MAX_DEPTH="${SOVA_MAX_DEPTH:-200}"
SOVA_BRIEF="${SOVA_BRIEF:-0}"
MAX_DEAD_ENDS=5

RENAME_COUNTER=0
QUERY_VARS=()
SOLUTIONS=()
SOLUTION_PROOFS=()
SOLUTION_SUBSTS=()
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
#
# Finds a binding with ${subst%%pattern*} (which is fast) rather than
# ${subst#*pattern}, which Bash runs in time proportional to the square of
# the distance to the match: on deep searches that was most of the run time.
walk() {
    local term="$1" subst="$2" before rest
    while is_variable "$term"; do
        before="${subst%%"${SUBST_SEP}${term}="*}"
        [[ "${#before}" -eq "${#subst}" ]] && break
        rest="${subst:$((${#before} + ${#SUBST_SEP} + ${#term} + 1))}"
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
    RESOLVE_SUBST="$subst"
    for term in "${terms[@]}"; do
        if is_expression "$term"; then
            expr_map "$term" resolve_token
            term="$MAPPED"
        else
            resolve_token "$term"
            term="$MAPPED_TOKEN"
        fi
        out="${out:+${out}${AST_AS}}${term}"
    done
    RESOLVED="$out"
}

# resolve_token TERM -> MAPPED_TOKEN: its value in RESOLVE_SUBST as text
# (lists written out), with _ for anything that has no value yet.
#
# With RESOLVE_KEEP_NAMES=1, variables with no value show their names
# instead of _.
RESOLVE_KEEP_NAMES=0
resolve_token() {
    TT_KEEP_NAMES="$RESOLVE_KEEP_NAMES"
    term_text "$1" "$RESOLVE_SUBST"
    # shellcheck disable=SC2034 # read by term_text (src/terms.sh)
    TT_KEEP_NAMES=0
    MAPPED_TOKEN="$TERM_TEXT"
    return 0
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
        unify_terms "${left[$i]}" "${right[$i]}" "$subst" || return 1
        subst="$UNIFY_SUBST"
    done
    UNIFY_SUBST="$subst"
}

# rename_args ARGS SUFFIX -> RENAMED_ARGS
rename_args() {
    local suffix="$2" term out="" first=1
    local -a terms
    split_on "$AST_AS" "$1"
    terms=("${SPLIT[@]}")
    RENAME_SUFFIX="$suffix"
    for term in "${terms[@]}"; do
        if is_expression "$term"; then
            expr_map "$term" rename_token
            term="$MAPPED"
        elif is_variable "$term" || is_cell "$term"; then
            rename_term "$term" "$suffix"
            term="$RENAMED_TERM"
        fi
        if [[ "$first" -eq 1 ]]; then
            out="$term"
            first=0
        else
            out+="${AST_AS}${term}"
        fi
    done
    RENAMED_ARGS="$out"
}

rename_token() {
    MAPPED_TOKEN="$1#${RENAME_SUFFIX}"
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
    local term
    split_on "$AST_AS" "$1"
    for term in "${SPLIT[@]}"; do
        term_has_no_variables "$term" || return 0
    done
    return 1
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

        # In a collect or count, the template and the inner question's
        # variables take a value per answer, so show their names.
        [[ "$source" == "G" ]] && RESOLVE_KEEP_NAMES=1
        resolve_args "$args" "$subst"
        RESOLVE_KEEP_NAMES=0
        format_goal "$name" "$RESOLVED"
        case "$source" in
            F) LABEL="fact" ;;
            C) LABEL="comparison" ;;
            E)
                if [[ "$args" == *"$EXPR_SEP"* ]]; then
                    LABEL="calculation"
                else
                    LABEL="match"
                fi
                ;;
            N) LABEL="not provable" ;;
            G) LABEL="${name%%:*}" ;;
            B) LABEL="built-in" ;;
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
            term_text "$var" "$subst"
            answer+="$var = $TERM_TEXT"
        fi
    done
    for existing in "${SOLUTIONS[@]}"; do
        [[ "$existing" == "$answer" ]] && return 0
    done
    SOLUTIONS+=("$answer")
    SOLUTION_SUBSTS+=("$subst")
    if [[ "$SOVA_BRIEF" -eq 1 ]]; then
        SOLUTION_PROOFS+=("")
    else
        render_proof "$proof" "$subst"
        SOLUTION_PROOFS+=("$RENDERED")
    fi
}

# The search keeps pending states on an explicit stack instead of calling
# itself, because Bash looks up every global variable through all the
# function calls in progress: a recursive search gets slower the deeper it
# goes. A state is four parallel entries (goals, substitution, depth, proof).
# Successors are pushed in reverse, so they are explored in source order,
# exactly as a recursive depth-first search would.
ST_GOALS=()
ST_SUBST=()
ST_DEPTH=()
ST_PROOF=()
ST_TOP=0

push_state() {
    ST_GOALS[ST_TOP]="$1"
    ST_SUBST[ST_TOP]="$2"
    ST_DEPTH[ST_TOP]="$3"
    ST_PROOF[ST_TOP]="$4"
    ST_TOP=$((ST_TOP + 1))
}

# run_search GOALS SUBST DEPTH PROOF: proves every goal in GOALS and records
# each solution it finds. A nested search (for NOT) starts above the current
# top of the stack and finishes when the stack is back to where it began, so
# it never touches the states of the search that started it.
run_search() {
    local base="$ST_TOP"
    local goals subst depth proof goal rest level name args clause_args entry
    local rule_index head body suffix step alt i id ref defined matched
    local first first_value fact_first level_field chain key term ground
    local -a next_goals next_subst next_proof fact_ids alt_ids call_terms

    push_state "$1" "$2" "$3" "$4"
    while ((ST_TOP > base)); do
        ST_TOP=$((ST_TOP - 1))
        goals="${ST_GOALS[ST_TOP]}"
        subst="${ST_SUBST[ST_TOP]}"
        depth="${ST_DEPTH[ST_TOP]}"
        proof="${ST_PROOF[ST_TOP]}"

        if [[ -z "$goals" ]]; then
            record_solution "$subst" "$proof"
            continue
        fi

        goal="${goals%%"$GOAL_SEP"*}"
        rest=""
        [[ "$goals" == *"$GOAL_SEP"* ]] && rest="${goals#*"$GOAL_SEP"}"
        level_field="${goal%%"$AST_FS"*}"
        level="${level_field%%"$CHAIN_SEP"*}"
        chain=""
        [[ "$level_field" == *"$CHAIN_SEP"* ]] && chain="${level_field#*"$CHAIN_SEP"}"
        goal="${goal#*"$AST_FS"}"
        name="${goal%%"$AST_FS"*}"
        args="${goal#*"$AST_FS"}"
        step="${level}${AST_FS}${name}${AST_FS}${args}${AST_FS}"

        # The depth limit is on how deeply rule calls are nested, not on how
        # many steps a proof takes, so long computations (fib(15)) are fine
        # while a rule that keeps calling itself is stopped.
        if ((level >= SOVA_MAX_DEPTH)); then
            DEPTH_LIMIT_HIT=1
            continue
        fi
        proof="${proof:+${proof}${PROOF_SEP}}"

        if is_comparison "$name"; then
            if solve_comparison "$name" "$args" "$subst"; then
                if [[ "$name" == "=" ]]; then
                    push_state "$rest" "$COMPARE_SUBST" $((depth + 1)) "${proof}${step}E"
                else
                    push_state "$rest" "$COMPARE_SUBST" $((depth + 1)) "${proof}${step}C"
                fi
            fi
            continue
        fi
        if [[ "$name" == "!"* ]]; then
            if solve_not "${name#!}" "$args" "$subst" "$level" "$depth"; then
                push_state "$rest" "$subst" $((depth + 1)) "${proof}${step}N"
            fi
            continue
        fi
        if is_gather "$name"; then
            if solve_gather "$name" "$args" "$subst" "$level" "$depth" "$rest"; then
                push_state "$rest" "$GATHER_SUBST" $((depth + 1)) "${proof}${step}G"
            fi
            continue
        fi
        if builtin_applies "$name" "$args"; then
            if solve_text_builtin "$name" "$args" "$subst"; then
                # shellcheck disable=SC2153 # set by solve_text_builtin
                local -a builtin_substs=("${BUILTIN_SUBSTS[@]}")
                for ((i = ${#builtin_substs[@]} - 1; i >= 0; i--)); do
                    push_state "$rest" "${builtin_substs[i]}" $((depth + 1)) "${proof}${step}B"
                done
            fi
            continue
        fi

        next_goals=()
        next_subst=()
        next_proof=()
        defined=0
        matched=0

        # First-argument indexing: if the goal's first argument already has
        # a value, a fact whose first argument is a different value can't
        # match, so skip it without trying to unify.
        first="${args%%"$AST_AS"*}"
        walk "$first" "$subst"
        first_value=""
        is_variable "$WALKED" || first_value="$WALKED"

        # Facts
        ref="KBF_${name}[@]"
        fact_ids=("${!ref}")
        [[ "${#fact_ids[@]}" -gt 0 ]] && defined=1
        for id in "${fact_ids[@]}"; do
            clause_args="${KB_FACTS[id]#*"$AST_FS"}"
            if [[ -n "$first_value" ]]; then
                fact_first="${clause_args%%"$AST_AS"*}"
                # Two different lists can still match ([1 | t] and [1, 2]),
                # so only skip when neither side is a list or a variable.
                if [[ "$fact_first" != "$first_value" ]] && ! is_variable "$fact_first" &&
                    ! is_cell "$fact_first" && ! is_cell "$first_value"; then
                    continue
                fi
            fi
            if has_variables "$clause_args"; then
                RENAME_COUNTER=$((RENAME_COUNTER + 1))
                rename_args "$clause_args" "$RENAME_COUNTER"
                clause_args="$RENAMED_ARGS"
            fi
            if unify_args "$args" "$clause_args" "$subst"; then
                matched=1
                next_goals+=("$rest")
                next_subst+=("$UNIFY_SUBST")
                next_proof+=("${proof}${step}F")
            fi
        done

        # Rules: one entry per alternative body
        ref="KBA_${name}[@]"
        alt_ids=("${!ref}")
        [[ "${#alt_ids[@]}" -gt 0 ]] && defined=1

        # Loop check: a fully known goal that is already being proved further
        # up this chain of rule calls can't gain anything from being proved
        # again (any proof through the repeat has a shorter one without it),
        # so its rules are skipped. This stops cycles in graphs and
        # symmetric rules from looping. Goals with unknowns aren't skipped:
        # that could lose answers.
        key=""
        if [[ "${#alt_ids[@]}" -gt 0 ]]; then
            split_on "$AST_AS" "$args"
            call_terms=("${SPLIT[@]}")
            ground=1
            for term in "${call_terms[@]}"; do
                if ! term_is_ground "$term" "$subst"; then
                    ground=0
                    break
                fi
            done
            if [[ "$ground" -eq 1 ]]; then
                resolve_args "$args" "$subst"
                key="${name}(${RESOLVED})"
                if [[ "$chain" == *"${CHAIN_ITEM}${key}${CHAIN_ITEM}"* ]]; then
                    alt_ids=()
                    matched=1
                    format_goal "$name" "$RESOLVED"
                    add_unique DEAD_ENDS "$FORMATTED  (would need itself to be proved first)"
                    key=""
                fi
            fi
        fi
        local body_level=$((level + 1))
        if [[ -n "$key" ]]; then
            body_level+="${CHAIN_SEP}${chain:-$CHAIN_ITEM}${key}${CHAIN_ITEM}"
        elif [[ -n "$chain" ]]; then
            body_level+="${CHAIN_SEP}${chain}"
        fi

        for alt in "${alt_ids[@]}"; do
            entry="${KB_ALTS[alt]}"
            rule_index="${entry%%"$AST_FS"*}"
            head="${KB_RULES[rule_index]}"

            RENAME_COUNTER=$((RENAME_COUNTER + 1))
            suffix="$RENAME_COUNTER"
            rename_args "${head#*"$AST_FS"}" "$suffix"
            unify_args "$args" "$RENAMED_ARGS" "$subst" || continue
            matched=1
            rename_goals "${entry#*"$AST_FS"}" "$suffix" "$body_level"
            body="$RENAMED_GOALS"
            next_goals+=("${body}${rest:+${GOAL_SEP}${rest}}")
            next_subst+=("$UNIFY_SUBST")
            next_proof+=("${proof}${step}A${alt}")
        done

        # Remember why this branch failed, for explaining FALSE answers.
        if [[ "$defined" -eq 0 ]]; then
            add_unique UNDEFINED "$name"
        elif [[ "$matched" -eq 0 ]]; then
            resolve_args "$args" "$subst"
            format_goal "$name" "$RESOLVED"
            add_unique DEAD_ENDS "$FORMATTED"
        fi

        for ((i = ${#next_goals[@]} - 1; i >= 0; i--)); do
            push_state "${next_goals[i]}" "${next_subst[i]}" $((depth + 1)) "${next_proof[i]}"
        done
    done
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

# side_value SIDE SUBST -> SIDE_VALUE: a side of a comparison or =, worked
# out. A term is looked up; SIDE_UNBOUND=1 if it is a variable with no value
# yet. An expression is computed; on an error, fails with SIDE_ERROR set to
# the end of a message (it is added after the goal, e.g. "divides by zero").
side_value() {
    SIDE_UNBOUND=0
    SIDE_ERROR=""
    if is_expression "$1"; then
        # shellcheck disable=SC2034 # EX_SUBST is read by src/arith.sh
        EX_SUBST="$2"
        if expr_run eval "$1"; then
            SIDE_VALUE="$EX_V"
            return 0
        fi
        local kind="${EX_ERROR%%"$AST_FS"*}" detail="${EX_ERROR#*"$AST_FS"}"
        case "$kind" in
            needs-value)
                source_name "$detail"
                SIDE_ERROR="needs a value for '$SOURCE_NAME' (put the goal that sets it earlier)"
                ;;
            not-number)
                source_name "${detail%%"$AST_FS"*}"
                term_text "${detail#*"$AST_FS"}" "$2"
                SIDE_ERROR="needs a number for '$SOURCE_NAME', but it is $TERM_TEXT"
                ;;
            *)
                SIDE_ERROR="divides by zero"
                ;;
        esac
        return 1
    fi
    walk "$1" "$2"
    SIDE_VALUE="$WALKED"
    is_variable "$WALKED" && SIDE_UNBOUND=1
    return 0
}

# solve_comparison OP ARGS SUBST: succeeds if the comparison holds, or for
# "=", if the two sides can be made equal -> COMPARE_SUBST (SUBST, plus the
# new binding when "=" gave an unknown variable a value).
solve_comparison() {
    local op="$1" args="$2" subst="$3" a b shown
    COMPARE_SUBST="$subst"
    format_goal "$op" "$args"
    source_name "$FORMATTED"
    shown="$SOURCE_NAME"

    if ! side_value "${args%%"$AST_AS"*}" "$subst"; then
        add_unique ERRORS "'$shown' $SIDE_ERROR"
        return 1
    fi
    a="$SIDE_VALUE"
    local a_unbound="$SIDE_UNBOUND"
    if ! side_value "${args#*"$AST_AS"}" "$subst"; then
        add_unique ERRORS "'$shown' $SIDE_ERROR"
        return 1
    fi
    b="$SIDE_VALUE"
    local b_unbound="$SIDE_UNBOUND"

    # = matches the two sides: an unknown gets a value, lists are matched
    # item by item ([h | t] = [1, 2, 3] gives h = 1 and t = [2, 3]).
    if [[ "$op" == "=" ]]; then
        if unify_terms "$a" "$b" "$subst"; then
            COMPARE_SUBST="$UNIFY_SUBST"
            return 0
        fi
        term_text "$a" "$subst"
        a="$TERM_TEXT"
        term_text "$b" "$subst"
        add_unique DEAD_ENDS "$a = $TERM_TEXT  (false)"
        return 1
    elif [[ "$a_unbound" -eq 1 || "$b_unbound" -eq 1 ]]; then
        if [[ "$a_unbound" -eq 1 ]]; then
            source_name "$a"
        else
            source_name "$b"
        fi
        add_unique ERRORS "'$shown' needs a value for '$SOURCE_NAME' (put the goal that sets it earlier)"
        return 1
    fi

    # Lists are compared by what they contain, so write them out (they must
    # be fully known).
    local side
    for side in a b; do
        if is_cell "${!side}"; then
            if ! term_is_ground "${!side}" "$subst"; then
                add_unique ERRORS "'$shown' needs a list with no unknowns in it"
                return 1
            fi
            term_text "${!side}" "$subst"
            printf -v "$side" '%s' "$TERM_TEXT"
        fi
    done

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

# solve_gather NAME ARGS SUBST LEVEL DEPTH: collect or count. Runs the inner
# question as a separate search (like NOT), whose answers are the distinct
# answers Sova would print for it, in the same order. collect makes a list
# of the template for each answer; count counts them. The result is then
# matched with the last argument -> GATHER_SUBST.
solve_gather() {
    local name="$1" args="$2" subst="$3" level="$4" depth="$5" rest="$6" term var
    gather_parts "$name" "$args"
    local kind="$GATHER_KIND" pred="$GATHER_PRED" template="$GATHER_TEMPLATE"
    local inner_args="$GATHER_ARGS" result="$GATHER_RESULT"

    # An inner variable with no value yet is gathered over, unless it is
    # still needed afterwards (in a later goal, or in the question being
    # asked): then which value it should have is ambiguous, so say so
    # instead of quietly gathering over every value.
    local -a later=() template_vars=()
    gather_later_vars "$rest" "$subst"
    later=("${GATHER_LATER[@]}")
    # The question's own variables may be bound to the rule's (p -> p#3).
    for var in "${QUERY_VARS[@]}"; do
        walk "$var" "$subst"
        is_variable "$WALKED" && later+=("$WALKED")
    done
    TERM_VARS=()
    term_vars "$template"
    for var in "${TERM_VARS[@]}"; do
        walk "$var" "$subst"
        template_vars+=("$WALKED")
    done
    TERM_VARS=()
    split_on "$AST_AS" "$inner_args"
    local -a inner_terms=("${SPLIT[@]}")
    for term in "${inner_terms[@]}"; do
        term_vars "$term"
    done
    local -a inner_vars=("${TERM_VARS[@]}")
    local other
    for var in "${inner_vars[@]}"; do
        walk "$var" "$subst"
        is_variable "$WALKED" || continue
        local needed=0
        for other in "${later[@]}"; do
            [[ "$other" == "$WALKED" ]] && needed=1
        done
        for other in "${template_vars[@]}"; do
            [[ "$other" == "$WALKED" ]] && needed=0
        done
        if [[ "$needed" -eq 1 ]]; then
            format_goal "$name" "$args"
            source_name "$FORMATTED"
            local shown="$SOURCE_NAME"
            source_name "$WALKED"
            add_unique ERRORS "'$shown' needs a value for '$SOURCE_NAME' first (otherwise it would $kind over every $SOURCE_NAME)"
            return 1
        fi
    done

    local -a saved_vars=("${QUERY_VARS[@]}") saved_solutions=("${SOLUTIONS[@]}")
    local -a saved_proofs=("${SOLUTION_PROOFS[@]}") saved_dead=("${DEAD_ENDS[@]}")
    local -a saved_undefined=("${UNDEFINED[@]}") saved_substs=("${SOLUTION_SUBSTS[@]}")
    local saved_depth_hit="$DEPTH_LIMIT_HIT" saved_brief="$SOVA_BRIEF"

    # The answers are told apart by the inner question's variables that
    # have no value yet (as when it is asked on its own).
    QUERY_VARS=()
    TERM_VARS=()
    split_on "$AST_AS" "$inner_args"
    for term in "${SPLIT[@]}"; do
        term_vars "$term"
    done
    for var in "${TERM_VARS[@]}"; do
        walk "$var" "$subst"
        is_variable "$WALKED" && add_unique QUERY_VARS "$WALKED"
    done
    SOLUTIONS=()
    SOLUTION_PROOFS=()
    SOLUTION_SUBSTS=()
    DEPTH_LIMIT_HIT=0
    SOVA_BRIEF=1
    run_search "$((level + 1))${AST_FS}${pred}${AST_FS}${inner_args}" "$subst" $((depth + 1)) ""
    local -a found=("${SOLUTION_SUBSTS[@]}")
    local inner_depth_hit="$DEPTH_LIMIT_HIT"

    QUERY_VARS=("${saved_vars[@]}")
    SOLUTIONS=("${saved_solutions[@]}")
    SOLUTION_PROOFS=("${saved_proofs[@]}")
    SOLUTION_SUBSTS=("${saved_substs[@]}")
    DEAD_ENDS=("${saved_dead[@]}")
    UNDEFINED=("${saved_undefined[@]}")
    DEPTH_LIMIT_HIT="$saved_depth_hit"
    SOVA_BRIEF="$saved_brief"

    if [[ "$inner_depth_hit" -eq 1 ]]; then
        DEPTH_LIMIT_HIT=1
        return 1
    fi

    local value i
    if [[ "$kind" == "count" ]]; then
        value="${#found[@]}"
    else
        value="[]"
        for ((i = ${#found[@]} - 1; i >= 0; i--)); do
            resolve_term "$template" "${found[i]}"
            new_cell "$RESOLVED_TERM" "$value"
            value="$NEW_CELL"
        done
    fi
    if unify_terms "$result" "$value" "$subst"; then
        GATHER_SUBST="$UNIFY_SUBST"
        return 0
    fi
    RESOLVE_KEEP_NAMES=1
    resolve_args "$args" "$subst"
    RESOLVE_KEEP_NAMES=0
    format_goal "$name" "$RESOLVED"
    term_text "$value"
    add_unique DEAD_ENDS "$FORMATTED  (gives $TERM_TEXT)"
    return 1
}

# gather_later_vars GOALS SUBST -> GATHER_LATER: the variables (looked up
# in SUBST) that the goals still to be proved use.
gather_later_vars() {
    local goals="$1" subst="$2" goal term var
    local -a goal_list terms
    GATHER_LATER=()
    [[ -n "$goals" ]] || return 0
    split_on "$GOAL_SEP" "$goals"
    goal_list=("${SPLIT[@]}")
    TERM_VARS=()
    for goal in "${goal_list[@]}"; do
        goal="${goal#*"$AST_FS"}"
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
    local -a found=("${TERM_VARS[@]}")
    for var in "${found[@]}"; do
        walk "$var" "$subst"
        is_variable "$WALKED" && GATHER_LATER+=("$WALKED")
    done
    return 0
}

# solve_not NAME ARGS SUBST LEVEL DEPTH: succeeds if NAME(ARGS) can't be
# proved. Runs a separate search, saving and restoring the answer state.
solve_not() {
    local name="$1" subst="$3" level="$4" depth="$5" term
    local -a terms
    split_on "$AST_AS" "$2"
    terms=("${SPLIT[@]}")
    for term in "${terms[@]}"; do
        if ! term_is_ground "$term" "$subst"; then
            format_goal "!$name" "$2"
            source_name "$FORMATTED"
            local shown="$SOURCE_NAME"
            TERM_VARS=()
            term_vars "$term"
            local missing var
            for var in "${TERM_VARS[@]}"; do
                walk "$var" "$subst"
                if is_variable "$WALKED"; then
                    missing="$WALKED"
                    break
                fi
            done
            source_name "$missing"
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
    # The inner search starts from the current bindings, so it sees the
    # values the arguments have (all known, checked above).
    run_search "$((level + 1))${AST_FS}${name}${AST_FS}${2}" "$subst" $((depth + 1)) ""
    found="${#SOLUTIONS[@]}"
    inner_depth_hit="$DEPTH_LIMIT_HIT"

    QUERY_VARS=("${saved_vars[@]}")
    SOLUTIONS=("${saved_solutions[@]}")
    SOLUTION_PROOFS=("${saved_proofs[@]}")
    DEAD_ENDS=("${saved_dead[@]}")
    UNDEFINED=("${saved_undefined[@]}")
    DEPTH_LIMIT_HIT="$saved_depth_hit"

    resolve_args "$2" "$subst"
    format_goal "!$name" "$RESOLVED"
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
    TERM_VARS=()
    for term in "${SPLIT[@]}"; do
        term_vars "$term"
    done
    for term in "${TERM_VARS[@]}"; do
        known=0
        for var in "${QUERY_VARS[@]}"; do
            [[ "$var" == "$term" ]] && known=1
        done
        [[ "$known" -eq 0 ]] && QUERY_VARS+=("$term")
    done

    run_search "0${AST_FS}${name}${AST_FS}${args}" "$SUBST_SEP" 0 ""

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
