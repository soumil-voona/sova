#pseudocode.sh
# shellcheck shell=bash
#
# translate_to LANG TARGET shows how a predicate could be written in a
# conventional language. LANG is "pseudo" (language-independent pseudocode),
# "python", "javascript", or "functional" (Python written with list
# comprehensions instead of loops). TARGET is a predicate name (grandparent)
# or a call (ancestor("Ada", who)).
#
# How rules are translated:
#   - Facts are tables (lists of tuples), listed in a DATA section.
#   - Each rule predicate becomes a function. What it looks like depends on
#     which arguments are already known when it's called (its "mode"):
#       nothing known      all_ancestor()          -> every (x, y)
#       some known         ancestor_given_x(x)     -> every y
#       everything known   is_ancestor(x, y)       -> TRUE or FALSE
#     Modes are worked out left to right, the same order Sova's search uses,
#     and each mode a program needs gets its own function.
#   - Goals joined by AND become nested FOR EACH loops (for goals that find
#     new values) and IFs (for goals that only check). Each extra clause or
#     OR branch is another block that adds to the same results. A result is
#     added only if it isn't there yet, matching Sova's answers.
#   - Comparisons become IFs; NOT p(x) becomes IF NOT ... / NOT IN.
#
# All languages come from the same logic: every line goes through the
# code_* helpers below, which know each language's syntax. JavaScript also
# needs closing braces (code_close) and, since arrays can't be compared with
# ===, two small helpers in the output: key(row) and has(table, row).
#
# Functional style uses Python syntax, but instead of writing lines, the
# loops and IFs of each clause are collected (G_LEAD for checks before the
# first loop, G_LOOPS for the rest) and become one comprehension: [y for (v1, z) in parent if v1 == x for y in f(z)]. The
# clauses of a function are joined with + (or "or" for TRUE/FALSE
# functions) and wrapped in unique(), which drops repeated answers.
#
# Before generating, names that would clash are renamed with a trailing _
# (see code_sanitize): variables named like a table or a generated name
# (results, v1), and in Python or JavaScript, keywords and builtins the
# generated code relies on.
#
# Generation state for the block being written lives in G_* globals:
#   G_LEVEL  indent level        G_BOUND  " x y " variables known so far
#   G_RENAME "|x=x_|" renames    G_FRESH  counter for v1, v2, ... names

MAX_DATA_ROWS=4

CODE_LANG="pseudo"
PSEUDO_OUT=""
PSEUDO_QUEUE=()
PSEUDO_TABLES=()
FN_PARAMS=()
FN_NAME=""
FN_MODE=""
JS_HELPERS_USED=0
FUNCTIONAL_UNIQUE_USED=0
# 1 when the program uses lists (set by code_sanitize). Lists change a few
# things: Python can't put lists in a set, so repeats are checked by
# repr(); JavaScript can't compare arrays with ===, so it uses same().
CODE_USES_LISTS=0
G_LEAD=""
G_LOOPS=""
G_LAST_PART=""
G_NOTES=()
G_CLAUSES=()

G_LEVEL=0
G_BOUND=" "
G_RENAME="|"
G_FRESH=0
G_GOAL_INDEX=0
G_IN_FUNCTION=0

# Set to 1 to print only the generated functions (used by --compare).
TRANSLATE_FUNCTIONS_ONLY=0

PYTHON_RESERVED=" False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield print set seen "
JS_RESERVED=" break case catch class const continue debugger default delete do else enum export extends false finally for function if import in instanceof new null return super switch this throw true try typeof var void while with yield let static await implements package protected interface private public arguments eval undefined NaN Infinity console key has seen Set "

pseudo_emit() {
    local pad
    printf -v pad '%*s' $((4 * $1)) ''
    PSEUDO_OUT+="${pad}$2"$'\n'
}

# True for Python in either style; functional style only differs in how
# function bodies are written.
is_python() {
    [[ "$CODE_LANG" == "python" || "$CODE_LANG" == "functional" ]]
}

is_functional() {
    [[ "$CODE_LANG" == "functional" ]]
}

is_js() {
    [[ "$CODE_LANG" == "javascript" ]]
}

# --- Language helpers: each writes or builds one piece of syntax ---------

code_comment() {
    if is_functional && [[ "$G_IN_FUNCTION" -eq 1 ]]; then
        G_NOTES+=("# $2")
    elif is_js; then
        pseudo_emit "$1" "// $2"
    else
        pseudo_emit "$1" "# $2"
    fi
}

code_if() {
    if is_functional && [[ "$G_IN_FUNCTION" -eq 1 ]]; then
        # Consecutive checks merge into one: if a and b
        if [[ -z "$G_LOOPS" ]]; then
            G_LEAD="${G_LEAD:+${G_LEAD} and }$1"
        elif [[ "$G_LAST_PART" == "if" ]]; then
            G_LOOPS+=" and $1"
        else
            G_LOOPS+=" if $1"
        fi
        G_LAST_PART="if"
    elif is_python; then
        pseudo_emit "$G_LEVEL" "if $1:"
    elif is_js; then
        pseudo_emit "$G_LEVEL" "if ($1) {"
    else
        pseudo_emit "$G_LEVEL" "IF $1:"
    fi
    G_LEVEL=$((G_LEVEL + 1))
}

code_for() {
    if is_functional && [[ "$G_IN_FUNCTION" -eq 1 ]]; then
        G_LOOPS+=" for $1 in $2"
        G_LAST_PART="for"
    elif is_python; then
        pseudo_emit "$G_LEVEL" "for $1 in $2:"
    elif is_js; then
        pseudo_emit "$G_LEVEL" "for (const $1 of $2) {"
    else
        pseudo_emit "$G_LEVEL" "FOR EACH $1 IN $2:"
    fi
    G_LEVEL=$((G_LEVEL + 1))
}

# code_close BASE: closes open blocks down to indent level BASE (JavaScript
# needs a "}" for each; the other languages end blocks by indentation).
code_close() {
    while ((G_LEVEL > $1)); do
        G_LEVEL=$((G_LEVEL - 1))
        is_js && pseudo_emit "$G_LEVEL" "}"
    done
    return 0
}

code_assign() {
    if is_functional; then
        G_LOOPS+=" for $1 in [$2]"
        G_LAST_PART="for"
    elif is_python; then
        pseudo_emit "$G_LEVEL" "$1 = $2"
    elif is_js; then
        # Each clause declares its own names, so give it its own block
        # (otherwise two clauses would declare the same const).
        if ((G_LEVEL == 1)); then
            pseudo_emit 1 "{"
            G_LEVEL=2
        fi
        pseudo_emit "$G_LEVEL" "const $1 = $2;"
    else
        pseudo_emit "$G_LEVEL" "$1 ← $2"
    fi
}

# code_declare NAME VALUE [mutable]: starts a new variable (a list or a
# counter that the code then adds to). In JavaScript it gets its own block
# at the top level of a clause, like code_assign, and "let" if it changes.
code_declare() {
    if is_js; then
        if ((G_LEVEL == 1)); then
            pseudo_emit 1 "{"
            G_LEVEL=2
        fi
        if [[ "$3" == "mutable" ]]; then
            pseudo_emit "$G_LEVEL" "let $1 = $2;"
        else
            pseudo_emit "$G_LEVEL" "const $1 = $2;"
        fi
    elif is_python; then
        pseudo_emit "$G_LEVEL" "$1 = $2"
    else
        pseudo_emit "$G_LEVEL" "$1 ← $2"
    fi
}

# code_gather_step KIND NAME ROW: inside the loops of a collect or count,
# add ROW to the list NAME, or add 1 to the counter NAME.
code_gather_step() {
    if [[ "$1" == "count" ]]; then
        if is_js; then
            pseudo_emit "$G_LEVEL" "$2 += 1;"
        elif is_python; then
            pseudo_emit "$G_LEVEL" "$2 += 1"
        else
            pseudo_emit "$G_LEVEL" "$2 ← $2 + 1"
        fi
    elif is_js; then
        pseudo_emit "$G_LEVEL" "$2.push($3);"
    elif is_python; then
        pseudo_emit "$G_LEVEL" "$2.append($3)"
    else
        pseudo_emit "$G_LEVEL" "ADD $3 TO $2"
    fi
}

# Conditions are built as strings -> COND
cond_eq() {
    if is_python; then
        COND="$1 == $2"
    elif is_js && [[ "$CODE_USES_LISTS" -eq 1 ]]; then
        COND="same($1, $2)"
        JS_HELPERS_USED=1
    elif is_js; then
        COND="$1 === $2"
    else
        COND="$1 = $2"
    fi
}

# cond_in ROW TABLE. In JavaScript a row with several values is an array,
# which needs the has() helper; a single value can use includes().
cond_in() {
    if is_python; then
        COND="$1 in $2"
    elif is_js; then
        if [[ "$1" == "["* || "$CODE_USES_LISTS" -eq 1 ]]; then
            COND="has($2, $1)"
            JS_HELPERS_USED=1
        else
            COND="$2.includes($1)"
        fi
    else
        COND="$1 IN $2"
    fi
}

cond_not_in() {
    if is_js; then
        cond_in "$1" "$2"
        COND="!$COND"
    elif is_python; then
        COND="$1 not in $2"
    else
        COND="$1 NOT IN $2"
    fi
}

cond_not() {
    if is_python; then
        COND="not $1"
    elif is_js; then
        COND="!$1"
    else
        COND="NOT $1"
    fi
}

# cond_and_append EXISTING NEW -> COND
cond_and_append() {
    if [[ -z "$1" ]]; then
        COND="$2"
    elif is_python; then
        COND="$1 and $2"
    elif is_js; then
        COND="$1 && $2"
    else
        COND="$1 AND $2"
    fi
}

# Comparison operators: JavaScript uses === and !== for exact equality.
code_comparison_op() {
    OP="$1"
    if is_js; then
        case "$OP" in
            "==") OP="===" ;;
            "!=") OP="!==" ;;
        esac
    fi
}

code_return() {
    local value="$1"
    if is_functional && [[ "$G_IN_FUNCTION" -eq 1 ]]; then
        [[ "$value" == "TRUE" ]] && functional_clause ""
        return 0
    elif is_python; then
        case "$value" in
            TRUE) value="True" ;;
            FALSE) value="False" ;;
        esac
        pseudo_emit "$G_LEVEL" "return $value"
    elif is_js; then
        case "$value" in
            TRUE) value="true" ;;
            FALSE) value="false" ;;
        esac
        pseudo_emit "$G_LEVEL" "return $value;"
    else
        pseudo_emit "$G_LEVEL" "RETURN $value"
    fi
}

# Adds a result only if it isn't already there (Sova shows each answer
# once, in the order first found). Python and JavaScript keep a set for
# fast checks; JavaScript stores rows in it by their key().
code_add_result() {
    local row="$1" member="$1"
    if is_functional; then
        functional_clause "$row"
    elif is_python; then
        [[ "$CODE_USES_LISTS" -eq 1 ]] && member="repr($row)"
        pseudo_emit "$G_LEVEL" "if $member not in seen:"
        pseudo_emit $((G_LEVEL + 1)) "seen.add($member)"
        pseudo_emit $((G_LEVEL + 1)) "results.append($row)"
    elif is_js; then
        if [[ "$row" == "["* || "$CODE_USES_LISTS" -eq 1 ]]; then
            member="key($row)"
            JS_HELPERS_USED=1
        fi
        pseudo_emit "$G_LEVEL" "if (!seen.has($member)) {"
        pseudo_emit $((G_LEVEL + 1)) "seen.add($member);"
        pseudo_emit $((G_LEVEL + 1)) "results.push($row);"
        pseudo_emit "$G_LEVEL" "}"
    else
        pseudo_emit "$G_LEVEL" "IF $row NOT IN results:"
        pseudo_emit $((G_LEVEL + 1)) "ADD $row TO results"
    fi
}

# functional_clause ROW: turns G_LEAD and G_LOOPS into one expression
# and saves it (with any notes) in G_CLAUSES. ROW is the result each match
# produces, or empty for a TRUE/FALSE function.
#
# A comprehension has to start with "for", so IFs that come before the
# first loop (checks on values that are already known) become a condition
# around it: ([...] if cond else []), or (cond and any(...)).
functional_clause() {
    local row="$1" lead="$G_LEAD" loops="$G_LOOPS" expr note

    if [[ -n "$row" ]]; then
        if [[ -n "$loops" ]]; then
            expr="[${row}${loops}]"
        else
            expr="[$row]"
        fi
        [[ -n "$lead" ]] && expr="($expr if $lead else [])"
    elif [[ -n "$loops" ]]; then
        expr="any(True${loops})"
        [[ -n "$lead" ]] && expr="($lead and $expr)"
    else
        expr="($lead)"
    fi

    note=""
    if [[ "${#G_NOTES[@]}" -gt 0 ]]; then
        local IFS=$'\x01'
        note="${G_NOTES[*]}"
    fi
    G_CLAUSES+=("${note}${AST_FS}${expr}")
    G_NOTES=()
    functional_reset
}

functional_reset() {
    G_LEAD=""
    G_LOOPS=""
    G_LAST_PART=""
}

# functional_body MODE: writes "return unique(c1 + c2)" (or "c1 or c2" for
# a TRUE/FALSE function), one clause per line with its comments above it.
functional_body() {
    local mode="$1" entry note expr joiner="+ " i
    local -a notes
    [[ "$mode" != *u* ]] && joiner="or "
    if [[ "$mode" == *u* ]]; then
        pseudo_emit 1 "return unique("
        FUNCTIONAL_UNIQUE_USED=1
    else
        pseudo_emit 1 "return ("
    fi
    for ((i = 0; i < ${#G_CLAUSES[@]}; i++)); do
        entry="${G_CLAUSES[$i]}"
        note="${entry%%"$AST_FS"*}"
        expr="${entry#*"$AST_FS"}"
        if [[ -n "$note" ]]; then
            split_on $'\x01' "$note"
            notes=("${SPLIT[@]}")
            for note in "${notes[@]}"; do
                pseudo_emit 2 "$note"
            done
        fi
        if [[ "$i" -eq 0 ]]; then
            pseudo_emit 2 "$expr"
        else
            pseudo_emit 2 "${joiner}${expr}"
        fi
    done
    pseudo_emit 1 ")"
}

code_any() {
    if is_python; then
        ANY_VALUE="None"
    elif is_js; then
        ANY_VALUE="null"
    else
        ANY_VALUE="ANY"
    fi
}

# --- Knowledge base queries ---------------------------------------------

pred_has_rules() {
    local rule
    for rule in "${KB_RULES[@]}"; do
        [[ "${rule%%"$AST_FS"*}" == "$1" ]] && return 0
    done
    return 1
}

pred_has_facts() {
    local fact
    for fact in "${KB_FACTS[@]}"; do
        [[ "${fact%%"$AST_FS"*}" == "$1" ]] && return 0
    done
    return 1
}

# Facts without variables are rows of data. A fact with variables, like
# gcd(a, 0, a), holds for any value of them: it's a rule with no body, so
# it is written as a clause of the predicate's function instead.
pred_has_ground_facts() {
    local fact
    for fact in "${KB_FACTS[@]}"; do
        [[ "${fact%%"$AST_FS"*}" == "$1" ]] || continue
        has_variables "${fact#*"$AST_FS"}" || return 0
    done
    return 1
}

pred_has_variable_facts() {
    local fact
    for fact in "${KB_FACTS[@]}"; do
        [[ "${fact%%"$AST_FS"*}" == "$1" ]] || continue
        has_variables "${fact#*"$AST_FS"}" && return 0
    done
    return 1
}

# A predicate becomes a function if it has rules or facts with variables;
# otherwise it is only a table.
pred_needs_function() {
    pred_has_rules "$1" || pred_has_variable_facts "$1"
}

# pred_params NAME -> PARAMS: parameter names for a predicate's functions,
# taken from its first rule head. Constants and repeated variables become
# arg1, arg2, ... For facts-only predicates, every parameter is argN.
pred_params() {
    local rule fact term i=0 seen=" "
    PARAMS=()
    for rule in "${KB_RULES[@]}"; do
        [[ "${rule%%"$AST_FS"*}" == "$1" ]] || continue
        split_on "$AST_AS" "${rule#*"$AST_FS"}"
        for term in "${SPLIT[@]}"; do
            i=$((i + 1))
            if is_variable "$term" && [[ "$seen" != *" $term "* ]]; then
                PARAMS+=("$term")
                seen+="$term "
            elif is_cell "$term" || [[ "$term" == "[]" ]]; then
                PARAMS+=("list$i")
            else
                PARAMS+=("arg$i")
            fi
        done
        return 0
    done
    for fact in "${KB_FACTS[@]}"; do
        [[ "${fact%%"$AST_FS"*}" == "$1" ]] || continue
        split_on "$AST_AS" "${fact#*"$AST_FS"}"
        for term in "${SPLIT[@]}"; do
            i=$((i + 1))
            PARAMS+=("arg$i")
        done
        return 0
    done
}

# function_name NAME MODE -> FUNC_NAME. MODE has one letter per argument:
# k (known) or u (unknown).
function_name() {
    local name="$1" mode="$2" i known=""
    if [[ "$mode" != *k* ]]; then
        FUNC_NAME="all_$name"
        return 0
    fi
    if [[ "$mode" != *u* ]]; then
        FUNC_NAME="is_$name"
        return 0
    fi
    pred_params "$name"
    for ((i = 0; i < ${#mode}; i++)); do
        [[ "${mode:$i:1}" == "k" ]] && known="${known:+${known}_and_}${PARAMS[$i]}"
    done
    FUNC_NAME="${name}_given_${known}"
}

# --- Renaming names that would clash ------------------------------------

CODE_RESERVED=" "

lang_reserved() {
    if is_python; then
        LANG_RESERVED="$PYTHON_RESERVED"
    elif is_js; then
        LANG_RESERVED="$JS_RESERVED"
    else
        LANG_RESERVED=" "
    fi
}

# safe_term TERM -> SAFE: a variable gets a trailing _ if its name is
# reserved or looks like a generated v1, v2, ... name.
safe_term() {
    SAFE="$1"
    is_variable "$SAFE" || return 0
    if [[ "$CODE_RESERVED" == *" $SAFE "* || "$SAFE" =~ ^v[0-9]+$ ]]; then
        SAFE="${SAFE}_"
    fi
}

# safe_pred NAME -> SAFE: predicate (table) names that are keywords.
safe_pred() {
    SAFE="$1"
    lang_reserved
    if [[ "$LANG_RESERVED" == *" $SAFE "* ]]; then
        SAFE="${SAFE}_"
    fi
}

# safe_args ARGS -> SAFE_ARGS (also renames variables inside expressions
# and lists, and notes whether the program uses lists)
safe_args() {
    local term out=""
    local -a terms
    split_on "$AST_AS" "$1"
    terms=("${SPLIT[@]}")
    for term in "${terms[@]}"; do
        if is_expression "$term"; then
            expr_map "$term" safe_token
            SAFE="$MAPPED"
        elif is_cell "$term"; then
            CODE_USES_LISTS=1
            map_term "$term" safe_token
            SAFE="$MAPPED_TERM"
        else
            [[ "$term" == "[]" ]] && CODE_USES_LISTS=1
            safe_term "$term"
        fi
        out="${out:+${out}${AST_AS}}${SAFE}"
    done
    SAFE_ARGS="$out"
}

safe_token() {
    safe_term "$1"
    # shellcheck disable=SC2034 # read by expr_map (src/arith.sh)
    MAPPED_TOKEN="$SAFE"
}

# safe_goal_name NAME -> SAFE (keeps comparisons, the NOT marker, and the
# collect:/count: prefix)
safe_goal_name() {
    local name="$1"
    if is_gather "$name"; then
        safe_pred "${name#*:}"
        SAFE="${name%%:*}:$SAFE"
    elif is_comparison "$name"; then
        SAFE="$name"
    elif [[ "$name" == "!"* ]]; then
        safe_pred "${name#!}"
        SAFE="!$SAFE"
    else
        safe_pred "$name"
    fi
}

SAVED_FACTS=()
SAVED_RULES=()
SAVED_ALTS=()

# code_sanitize: renames clashing names in the knowledge base (restored by
# code_restore). Reserved variable names are "results", every predicate
# name (a variable named parent would hide the parent table), and in
# Python or JavaScript, keywords plus the builtins the generated code uses.
code_sanitize() {
    local entry name goal out i
    local -a goals

    SAVED_FACTS=("${KB_FACTS[@]}")
    SAVED_RULES=("${KB_RULES[@]}")
    SAVED_ALTS=("${KB_ALTS[@]}")

    lang_reserved
    CODE_RESERVED=" results ${LANG_RESERVED# }"
    for entry in "${KB_FACTS[@]}" "${KB_RULES[@]}"; do
        [[ -n "$entry" ]] || continue
        CODE_RESERVED+="${entry%%"$AST_FS"*} "
    done
    for entry in "${KB_ALTS[@]}"; do
        split_on "$GOAL_SEP" "${entry#*"$AST_FS"}"
        for goal in "${SPLIT[@]}"; do
            name="${goal%%"$AST_FS"*}"
            is_gather "$name" && name="${name#*:}"
            is_comparison "$name" || CODE_RESERVED+="${name#!} "
        done
    done

    CODE_USES_LISTS=0
    for ((i = 0; i < ${#KB_FACTS[@]}; i++)); do
        entry="${KB_FACTS[$i]}"
        safe_pred "${entry%%"$AST_FS"*}"
        name="$SAFE"
        safe_args "${entry#*"$AST_FS"}"
        KB_FACTS[i]="${name}${AST_FS}${SAFE_ARGS}"
    done
    for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
        entry="${KB_RULES[$i]}"
        safe_pred "${entry%%"$AST_FS"*}"
        name="$SAFE"
        safe_args "${entry#*"$AST_FS"}"
        KB_RULES[i]="${name}${AST_FS}${SAFE_ARGS}"
    done
    for ((i = 0; i < ${#KB_ALTS[@]}; i++)); do
        entry="${KB_ALTS[$i]}"
        split_on "$GOAL_SEP" "${entry#*"$AST_FS"}"
        goals=("${SPLIT[@]}")
        out=""
        for goal in "${goals[@]}"; do
            safe_goal_name "${goal%%"$AST_FS"*}"
            name="$SAFE"
            safe_args "${goal#*"$AST_FS"}"
            out="${out:+${out}${GOAL_SEP}}${name}${AST_FS}${SAFE_ARGS}"
        done
        KB_ALTS[i]="${entry%%"$AST_FS"*}${AST_FS}${out}"
    done
}

code_restore() {
    KB_FACTS=("${SAVED_FACTS[@]}")
    KB_RULES=("${SAVED_RULES[@]}")
    KB_ALTS=("${SAVED_ALTS[@]}")
}

# --- Small helpers ------------------------------------------------------

# pseudo_tuple ITEM... -> TUPLE: "x" for one item; "(x, y)" for several
# ("[x, y]" in JavaScript, which has arrays instead of tuples).
pseudo_tuple() {
    if [[ "$#" -eq 1 ]]; then
        TUPLE="$1"
    else
        local IFS=$'\x01' joined
        joined="$*"
        joined="${joined//$'\x01'/, }"
        if is_js; then
            TUPLE="[$joined]"
        else
            TUPLE="($joined)"
        fi
    fi
}

# pseudo_join ITEM... -> JOINED: "a, b, c"
pseudo_join() {
    local IFS=$'\x01' joined
    joined="$*"
    JOINED="${joined//$'\x01'/, }"
}

# pseudo_disp TERM -> DISP: how a term is written in the output.
pseudo_disp() {
    local term="$1"
    if is_variable "$term"; then
        if [[ "$G_RENAME" == *"|${term}="* ]]; then
            term="${G_RENAME#*"|${term}="}"
            term="${term%%|*}"
        fi
    elif { is_python || is_js; } && [[ "$term" == *\\* ]]; then
        term="${term//\\/\\\\}"
    fi
    DISP="$term"
}

pseudo_bound() {
    [[ "$G_BOUND" == *" $1 "* ]]
}

pseudo_bind() {
    pseudo_bound "$1" || G_BOUND+="$1 "
}

pseudo_fresh() {
    G_FRESH=$((G_FRESH + 1))
    FRESH="v$G_FRESH"
}

# pseudo_term_known TERM: succeeds if every variable in TERM (a variable,
# constant, or list) has a value at this point.
pseudo_term_known() {
    local term="$1" var
    if is_variable "$term"; then
        pseudo_disp "$term"
        pseudo_bound "$DISP"
        return
    fi
    is_cell "$term" || return 0
    TERM_VARS=()
    term_vars "$term"
    local -a vars=("${TERM_VARS[@]}")
    for var in "${vars[@]}"; do
        pseudo_disp "$var"
        pseudo_bound "$DISP" || return 1
    done
    return 0
}

# pseudo_missing TERM...: adds the variables in the terms that have no
# value yet to MISSING (display names).
pseudo_missing() {
    local term var
    for term in "$@"; do
        TERM_VARS=()
        if is_expression "$term"; then
            expr_vars "$term"
            TERM_VARS=("${EXPR_VARS[@]}")
        else
            term_vars "$term"
        fi
        local -a vars=("${TERM_VARS[@]}")
        for var in "${vars[@]}"; do
            pseudo_disp "$var"
            pseudo_bound "$DISP" || add_unique MISSING "$DISP"
        done
    done
    return 0
}

# pseudo_build TERM -> BUILT: code that makes TERM's value. Variables that
# have no value yet become ANY (None, null). [x | rest] is [x] + rest
# ([x, ...rest] in JavaScript).
pseudo_build() {
    local term="$1" tail
    local -a items=()
    if is_variable "$term"; then
        pseudo_disp "$term"
        if pseudo_bound "$DISP"; then
            BUILT="$DISP"
        else
            code_any
            BUILT="$ANY_VALUE"
        fi
        return 0
    fi
    if ! is_cell "$term"; then
        pseudo_disp "$term"
        BUILT="$DISP"
        return 0
    fi
    while is_cell "$term"; do
        pseudo_build "${CELL_HEAD[${term#@}]}"
        items+=("$BUILT")
        term="${CELL_TAIL[${term#@}]}"
    done
    pseudo_join "${items[@]}"
    if [[ "$term" == "[]" ]]; then
        BUILT="[$JOINED]"
        return 0
    fi
    local joined="$JOINED"
    pseudo_build "$term"
    tail="$BUILT"
    if is_js; then
        BUILT="[$joined, ...$tail]"
    else
        BUILT="[$joined] + $tail"
    fi
}

# cond_list_shape VALUE N EXACT -> COND: VALUE is a list with exactly N
# items (EXACT=1) or at least N.
cond_list_shape() {
    local value="$1" n="$2" exact="$3" op word="ITEMS"
    [[ "$n" -eq 1 ]] && word="ITEM"
    if [[ "$n" -eq 0 && "$exact" -eq 1 ]] && ! is_js; then
        if is_python; then
            COND="$value == []"
        else
            COND="$value IS AN EMPTY LIST"
        fi
        return 0
    fi
    if is_python; then
        op=">="
        [[ "$exact" -eq 1 ]] && op="=="
        COND="isinstance($value, list) and len($value) $op $n"
    elif is_js; then
        op=">="
        [[ "$exact" -eq 1 ]] && op="==="
        COND="Array.isArray($value) && $value.length $op $n"
    elif [[ "$exact" -eq 1 ]]; then
        COND="$value IS A LIST OF $n $word"
    else
        COND="$value IS A LIST OF AT LEAST $n $word"
    fi
}

# code_rest VALUE N -> REST: VALUE without its first N items.
code_rest() {
    if is_js; then
        REST="$1.slice($2)"
    else
        REST="$1[$2:]"
    fi
}

# pseudo_match TERM VALUE: code that checks the known value VALUE has the
# shape of TERM and gives TERM's unknown variables their values from it.
#   x, no value yet      x = VALUE
#   x, known             IF x = VALUE
#   [a, b | rest]        IF VALUE IS A LIST OF AT LEAST 2 ITEMS, then match
#                        a with VALUE[0], b with VALUE[1], rest with VALUE[2:]
pseudo_match() {
    local term="$1" value="$2" tail i n
    local -a items=()
    if is_variable "$term"; then
        pseudo_disp "$term"
        if pseudo_bound "$DISP"; then
            [[ "$DISP" == "$value" ]] && return 0
            cond_eq "$DISP" "$value"
            code_if "$COND"
        else
            [[ "$DISP" != "$value" ]] && code_assign "$DISP" "$value"
            pseudo_bind "$DISP"
        fi
        return 0
    fi
    if [[ "$term" == "[]" ]]; then
        cond_list_shape "$value" 0 1
        code_if "$COND"
        return 0
    fi
    if ! is_cell "$term" || pseudo_term_known "$term"; then
        pseudo_build "$term"
        cond_eq "$value" "$BUILT"
        code_if "$COND"
        return 0
    fi
    while is_cell "$term"; do
        items+=("${CELL_HEAD[${term#@}]}")
        term="${CELL_TAIL[${term#@}]}"
    done
    tail="$term"
    n="${#items[@]}"
    if [[ "$tail" == "[]" ]]; then
        cond_list_shape "$value" "$n" 1
    else
        cond_list_shape "$value" "$n" 0
    fi
    code_if "$COND"
    for ((i = 0; i < n; i++)); do
        pseudo_match "${items[i]}" "${value}[$i]"
    done
    if [[ "$tail" != "[]" ]]; then
        code_rest "$value" "$n"
        pseudo_match "$tail" "$REST"
    fi
    return 0
}

# Warns when a built-in is reached before its variables have values:
# one note naming all of them ("a, b and c have no value yet here").
pseudo_check_known() {
    local value text=""
    local -a missing=()
    for value in "$@"; do
        if is_variable "$value" && ! pseudo_bound "$value"; then
            add_unique missing "$value"
        fi
    done
    [[ "${#missing[@]}" -gt 0 ]] || return 0
    if [[ "${#missing[@]}" -eq 1 ]]; then
        text="${missing[0]} has"
    else
        local last="${missing[${#missing[@]} - 1]}"
        pseudo_join "${missing[@]:0:${#missing[@]}-1}"
        text="$JOINED and $last have"
    fi
    code_comment "$G_LEVEL" "NOTE: $text no value yet here, so Sova would answer UNKNOWN"
}

# pseudo_side SIDE: one side of a comparison or = in the target language ->
# SIDE_TEXT; SIDE_KNOWN=1 if all its values are known at this point;
# SIDE_VAR is set if the side is a single variable with no value yet;
# SIDE_MISSING lists the variables that have no value yet.
pseudo_side() {
    local side="$1" value
    SIDE_VAR=""
    SIDE_KNOWN=1
    SIDE_MISSING=()
    if is_expression "$side"; then
        # shellcheck disable=SC2034 # EX_LANG is read by src/arith.sh
        EX_LANG="$CODE_LANG"
        expr_run text "$side"
        SIDE_TEXT="$EX_V"
        expr_vars "$side"
        local -a vars=("${EXPR_VARS[@]}")
        for value in "${vars[@]}"; do
            pseudo_disp "$value"
            if ! pseudo_bound "$DISP"; then
                SIDE_KNOWN=0
                SIDE_MISSING+=("$DISP")
            fi
        done
    elif is_cell "$side"; then
        pseudo_build "$side"
        SIDE_TEXT="$BUILT"
        if ! pseudo_term_known "$side"; then
            SIDE_KNOWN=0
            MISSING=()
            pseudo_missing "$side"
            SIDE_MISSING=("${MISSING[@]}")
        fi
    else
        pseudo_disp "$side"
        SIDE_TEXT="$DISP"
        if is_variable "$DISP" && ! pseudo_bound "$DISP"; then
            SIDE_KNOWN=0
            SIDE_VAR="$DISP"
            SIDE_MISSING+=("$DISP")
        fi
    fi
    return 0
}

# --- Code generation ----------------------------------------------------

# pseudo_goal NAME ARGS [table]: writes the loop or IF for one goal and
# updates G_LEVEL and G_BOUND. "table" forces looping over the facts of
# NAME even if it also has rules (used inside NAME's own function).
pseudo_goal() {
    local name="$1" args="$2" force_table="$3"
    local term value mode="" checks="" seen=" " i
    local -a terms built=() outs=() known_args=() patterns=() pattern_values=()
    split_on "$AST_AS" "$args"
    terms=("${SPLIT[@]}")

    if is_comparison "$name"; then
        local left_text left_known left_var right_text right_known right_var
        local -a missing=()
        pseudo_side "${terms[0]}"
        left_text="$SIDE_TEXT" left_known="$SIDE_KNOWN" left_var="$SIDE_VAR"
        missing+=("${SIDE_MISSING[@]}")
        pseudo_side "${terms[1]}"
        right_text="$SIDE_TEXT" right_known="$SIDE_KNOWN" right_var="$SIDE_VAR"
        missing+=("${SIDE_MISSING[@]}")

        # "=" with one side known and the other not is an assignment (or,
        # for a list pattern like [h | t], taking the known list apart).
        if [[ "$name" == "=" ]]; then
            if [[ "$left_known" -eq 0 && "$right_known" -eq 1 ]] &&
                { [[ -n "$left_var" ]] || is_cell "${terms[0]}"; }; then
                pseudo_match "${terms[0]}" "$right_text"
                return 0
            fi
            if [[ "$right_known" -eq 0 && "$left_known" -eq 1 ]] &&
                { [[ -n "$right_var" ]] || is_cell "${terms[1]}"; }; then
                pseudo_match "${terms[1]}" "$left_text"
                return 0
            fi
            [[ "${#missing[@]}" -gt 0 ]] && pseudo_check_known "${missing[@]}"
            cond_eq "$left_text" "$right_text"
            code_if "$COND"
            return 0
        fi
        [[ "${#missing[@]}" -gt 0 ]] && pseudo_check_known "${missing[@]}"
        code_comparison_op "$name"
        if is_js && [[ "$CODE_USES_LISTS" -eq 1 && ( "$name" == "==" || "$name" == "!=" ) ]]; then
            cond_eq "$left_text" "$right_text"
            [[ "$name" == "!=" ]] && COND="!$COND"
            code_if "$COND"
        else
            code_if "$left_text $OP $right_text"
        fi
        return 0
    fi

    if is_gather "$name"; then
        pseudo_gather "$name" "$args"
        return 0
    fi
    if pseudo_builtin_applies "$name" "${#terms[@]}"; then
        pseudo_text_builtin "$name" "${terms[@]}"
        return 0
    fi

    for term in "${terms[@]}"; do
        pseudo_build "$term"
        built+=("$BUILT")
    done

    if [[ "$name" == "!"* ]]; then
        name="${name#!}"
        MISSING=()
        pseudo_missing "${terms[@]}"
        [[ "${#MISSING[@]}" -gt 0 ]] && pseudo_check_known "${MISSING[@]}"
        if pred_needs_function "$name"; then
            mode="$(printf 'k%.0s' "${built[@]}")"
            add_unique PSEUDO_QUEUE "${name}:${mode}"
            function_name "$name" "$mode"
            pseudo_join "${built[@]}"
            cond_not "${FUNC_NAME}(${JOINED})"
        else
            add_unique PSEUDO_TABLES "$name"
            pseudo_tuple "${built[@]}"
            cond_not_in "$TUPLE" "$name"
        fi
        code_if "$COND"
        return 0
    fi

    for term in "${terms[@]}"; do
        if pseudo_term_known "$term"; then
            mode+="k"
        else
            mode+="u"
        fi
    done

    # Each unknown argument is read from the loop: a variable directly (or
    # through a fresh name and a check if it repeats), and a list pattern
    # through a fresh name that is then taken apart with pseudo_match.
    local use_function=0
    [[ "$force_table" != "table" ]] && pred_needs_function "$name" && use_function=1
    if [[ "$use_function" -eq 0 ]]; then
        add_unique PSEUDO_TABLES "$name"
        if [[ "$mode" != *u* ]]; then
            pseudo_tuple "${built[@]}"
            cond_in "$TUPLE" "$name"
            code_if "$COND"
            return 0
        fi
    else
        add_unique PSEUDO_QUEUE "${name}:${mode}"
        function_name "$name" "$mode"
        # Calling itself first, with exactly the input it was given, can
        # never finish. (Calling itself on something smaller, like the
        # rest of a list, is ordinary recursion.)
        if [[ "$G_GOAL_INDEX" -eq 0 && "$name" == "$FN_NAME" && "$mode" == "$FN_MODE" ]]; then
            local same_input=1
            for ((i = 0; i < ${#terms[@]}; i++)); do
                [[ "${mode:$i:1}" == "k" ]] || continue
                [[ "${built[$i]}" == "${FN_PARAMS[$i]}" ]] || same_input=0
            done
            if [[ "$same_input" -eq 1 ]]; then
                code_comment "$G_LEVEL" "WARNING: this calls $FUNC_NAME before doing anything else,"
                code_comment "$G_LEVEL" "with the same input, so it would call itself forever"
            fi
        fi
        if [[ "$mode" != *u* ]]; then
            pseudo_join "${built[@]}"
            code_if "${FUNC_NAME}(${JOINED})"
            return 0
        fi
    fi

    for ((i = 0; i < ${#terms[@]}; i++)); do
        term="${terms[$i]}"
        if [[ "${mode:$i:1}" == "k" ]]; then
            if [[ "$use_function" -eq 1 ]]; then
                known_args+=("${built[$i]}")
            else
                pseudo_fresh
                outs+=("$FRESH")
                cond_eq "$FRESH" "${built[$i]}"
                cond_and_append "$checks" "$COND"
                checks="$COND"
            fi
            continue
        fi
        if is_variable "$term"; then
            pseudo_disp "$term"
            value="$DISP"
            if [[ "$seen" == *" $value "* ]]; then
                pseudo_fresh
                outs+=("$FRESH")
                cond_eq "$FRESH" "$value"
                cond_and_append "$checks" "$COND"
                checks="$COND"
            else
                outs+=("$value")
                seen+="$value "
            fi
        else
            pseudo_fresh
            outs+=("$FRESH")
            patterns+=("$term")
            pattern_values+=("$FRESH")
        fi
    done

    pseudo_tuple "${outs[@]}"
    if [[ "$use_function" -eq 1 ]]; then
        JOINED=""
        [[ "${#known_args[@]}" -gt 0 ]] && pseudo_join "${known_args[@]}"
        code_for "$TUPLE" "${FUNC_NAME}(${JOINED})"
    else
        code_for "$TUPLE" "$name"
    fi

    for value in $seen; do
        pseudo_bind "$value"
    done
    for value in "${pattern_values[@]}"; do
        pseudo_bind "$value"
    done
    [[ -n "$checks" ]] && code_if "$checks"
    for ((i = 0; i < ${#patterns[@]}; i++)); do
        pseudo_match "${patterns[i]}" "${pattern_values[i]}"
    done
    return 0
}

# pseudo_gather NAME ARGS: collect(template, call, result) or
# count(call, result). The inner call is written as usual, inside a block
# that adds each answer to a list (or 1 to a counter); afterwards its
# variables have no values again. In functional style the block is a
# comprehension: [template for ...], or sum(1 for ...).
pseudo_gather() {
    gather_parts "$1" "$2"
    local kind="$GATHER_KIND" pred="$GATHER_PRED" template="$GATHER_TEMPLATE"
    local inner_args="$GATHER_ARGS" result="$GATHER_RESULT"
    local base="$G_LEVEL" saved_bound="$G_BOUND" saved_index="$G_GOAL_INDEX" target row
    local fresh_target=0

    if is_variable "$result" && ! pseudo_term_known "$result"; then
        pseudo_disp "$result"
        target="$DISP"
    else
        pseudo_fresh
        target="$FRESH"
        fresh_target=1
    fi
    G_GOAL_INDEX=-1

    if is_functional && [[ "$G_IN_FUNCTION" -eq 1 ]]; then
        local saved_lead="$G_LEAD" saved_loops="$G_LOOPS" saved_last="$G_LAST_PART" expr
        functional_reset
        pseudo_goal "$pred" "$inner_args"
        local lead="$G_LEAD" loops="$G_LOOPS"
        if [[ "$kind" == "collect" ]]; then
            pseudo_build "$template"
            if [[ -n "$loops" ]]; then
                expr="[${BUILT}${loops}]"
            else
                expr="[$BUILT]"
            fi
            [[ -n "$lead" ]] && expr="($expr if $lead else [])"
        else
            if [[ -n "$loops" ]]; then
                expr="sum(1${loops})"
            else
                expr="1"
            fi
            [[ -n "$lead" ]] && expr="($expr if $lead else 0)"
        fi
        G_LEAD="$saved_lead"
        G_LOOPS="$saved_loops"
        G_LAST_PART="$saved_last"
        G_LEVEL="$base"
        G_BOUND="$saved_bound"
        code_assign "$target" "$expr"
    else
        if [[ "$kind" == "collect" ]]; then
            if is_python || is_js; then
                code_declare "$target" "[]"
            else
                code_declare "$target" "empty list"
            fi
        else
            code_declare "$target" "0" mutable
        fi
        base="$G_LEVEL"
        pseudo_goal "$pred" "$inner_args"
        row=""
        if [[ "$kind" == "collect" ]]; then
            pseudo_build "$template"
            row="$BUILT"
        fi
        code_gather_step "$kind" "$target" "$row"
        code_close "$base"
        G_BOUND="$saved_bound"
    fi
    G_GOAL_INDEX="$saved_index"
    pseudo_bind "$target"
    [[ "$fresh_target" -eq 1 ]] && pseudo_match "$result" "$target"
    return 0
}

# A text built-in (src/builtins.sh) applies when the program doesn't
# define its own facts or rules with that name.
pseudo_builtin_applies() {
    local name="$1" count="$2" expected=2
    is_text_builtin "$name" || return 1
    pred_has_rules "$name" && return 1
    pred_has_facts "$name" && return 1
    [[ "$name" == "concat" ]] && expected=3
    [[ "$count" -eq "$expected" ]]
}

# code_text_op OP A [B] -> TEXT_CODE: one text operation in the target
# language: len, starts, ends, drop (A without its first len(B)
# characters), keep (A without its last len(B) characters), chars, join.
code_text_op() {
    local op="$1" a="$2" b="$3"
    if is_python; then
        case "$op" in
            len) TEXT_CODE="len($a)" ;;
            starts) TEXT_CODE="$a.startswith($b)" ;;
            ends) TEXT_CODE="$a.endswith($b)" ;;
            drop) TEXT_CODE="${a}[len($b):]" ;;
            keep) TEXT_CODE="${a}[:len($a) - len($b)]" ;;
            chars) TEXT_CODE="list($a)" ;;
            join) TEXT_CODE="\"\".join($a)" ;;
        esac
    elif is_js; then
        case "$op" in
            len) TEXT_CODE="$a.length" ;;
            starts) TEXT_CODE="$a.startsWith($b)" ;;
            ends) TEXT_CODE="$a.endsWith($b)" ;;
            drop) TEXT_CODE="$a.slice($b.length)" ;;
            keep) TEXT_CODE="$a.slice(0, $a.length - $b.length)" ;;
            chars) TEXT_CODE="[...$a]" ;;
            join) TEXT_CODE="$a.join(\"\")" ;;
        esac
    else
        case "$op" in
            len) TEXT_CODE="LENGTH($a)" ;;
            starts) TEXT_CODE="$a STARTS WITH $b" ;;
            ends) TEXT_CODE="$a ENDS WITH $b" ;;
            drop) TEXT_CODE="${a}[LENGTH($b):]" ;;
            keep) TEXT_CODE="${a}[:LENGTH($a) - LENGTH($b)]" ;;
            chars) TEXT_CODE="CHARACTERS OF $a" ;;
            join) TEXT_CODE="JOIN $a" ;;
        esac
    fi
}

# pseudo_text_builtin NAME TERM...: concat, text_length, or chars, written
# for the arguments that are known at this point.
pseudo_text_builtin() {
    local name="$1"
    shift
    local -a terms=("$@") built=() known=()
    local term i
    for term in "${terms[@]}"; do
        pseudo_build "$term"
        built+=("$BUILT")
        if pseudo_term_known "$term"; then
            known+=(1)
        else
            known+=(0)
        fi
    done
    case "$name" in
        concat)
            local a="${built[0]}" b="${built[1]}" c="${built[2]}"
            if [[ "${known[0]}" -eq 1 && "${known[1]}" -eq 1 ]]; then
                pseudo_match "${terms[2]}" "$a + $b"
            elif [[ "${known[2]}" -eq 1 && "${known[0]}" -eq 1 ]]; then
                code_text_op starts "$c" "$a"
                code_if "$TEXT_CODE"
                code_text_op drop "$c" "$a"
                pseudo_match "${terms[1]}" "$TEXT_CODE"
            elif [[ "${known[2]}" -eq 1 && "${known[1]}" -eq 1 ]]; then
                code_text_op ends "$c" "$b"
                code_if "$TEXT_CODE"
                code_text_op keep "$c" "$b"
                pseudo_match "${terms[0]}" "$TEXT_CODE"
            elif [[ "${known[2]}" -eq 1 ]]; then
                # Every way to split c: i is where the second part starts.
                pseudo_fresh
                local i_var="$FRESH"
                code_split_loop "$i_var" "$c"
                pseudo_bind "$i_var"
                if is_js; then
                    pseudo_match "${terms[0]}" "$c.slice(0, $i_var)"
                    pseudo_match "${terms[1]}" "$c.slice($i_var)"
                else
                    pseudo_match "${terms[0]}" "${c}[:$i_var]"
                    pseudo_match "${terms[1]}" "${c}[$i_var:]"
                fi
            else
                MISSING=()
                pseudo_missing "${terms[@]}"
                pseudo_check_known "${MISSING[@]}"
                pseudo_match "${terms[2]}" "$a + $b"
            fi
            ;;
        text_length)
            if [[ "${known[0]}" -ne 1 ]]; then
                MISSING=()
                pseudo_missing "${terms[0]}"
                pseudo_check_known "${MISSING[@]}"
            fi
            code_text_op len "${built[0]}"
            pseudo_match "${terms[1]}" "$TEXT_CODE"
            ;;
        chars)
            if [[ "${known[0]}" -eq 1 ]]; then
                code_text_op chars "${built[0]}"
                pseudo_match "${terms[1]}" "$TEXT_CODE"
            elif [[ "${known[1]}" -eq 1 ]]; then
                code_text_op join "${built[1]}"
                pseudo_match "${terms[0]}" "$TEXT_CODE"
            else
                MISSING=()
                pseudo_missing "${terms[@]}"
                pseudo_check_known "${MISSING[@]}"
                code_text_op chars "${built[0]}"
                pseudo_match "${terms[1]}" "$TEXT_CODE"
            fi
            ;;
    esac
    return 0
}

# code_split_loop VAR TEXT: a loop where VAR goes from 0 to the length of
# TEXT (so TEXT can be split at every position).
code_split_loop() {
    local var="$1" text="$2"
    if is_functional && [[ "$G_IN_FUNCTION" -eq 1 ]]; then
        code_for "$var" "range(len($text) + 1)"
    elif is_python; then
        code_for "$var" "range(len($text) + 1)"
    elif is_js; then
        pseudo_emit "$G_LEVEL" "for (let $var = 0; $var <= $text.length; $var++) {"
        G_LEVEL=$((G_LEVEL + 1))
    else
        pseudo_emit "$G_LEVEL" "FOR $var FROM 0 TO LENGTH($text):"
        G_LEVEL=$((G_LEVEL + 1))
    fi
}

# pseudo_success HEAD_ARGS: the line that runs once every goal has passed.
pseudo_success() {
    local term i
    local -a terms outs=()
    if [[ "$FN_MODE" != *u* ]]; then
        code_return TRUE
        return 0
    fi
    code_any
    split_on "$AST_AS" "$1"
    terms=("${SPLIT[@]}")
    for ((i = 0; i < ${#terms[@]}; i++)); do
        [[ "${FN_MODE:$i:1}" == "u" ]] || continue
        pseudo_build "${terms[$i]}"
        outs+=("$BUILT")
    done
    pseudo_tuple "${outs[@]}"
    code_add_result "$TUPLE"
}

# pseudo_clause ALT_INDEX: one block of the current function for one rule
# body alternative (a clause, or one OR branch of it).
pseudo_clause() {
    local alt="$1" entry rule_index head
    entry="${KB_ALTS[$alt]}"
    rule_index="${entry%%"$AST_FS"*}"
    head="${KB_RULES[$rule_index]}"
    rule_label "$alt"
    # shellcheck disable=SC2153 # LABEL is set by rule_label
    pseudo_block "$LABEL" "${head%%"$AST_FS"*}" "${head#*"$AST_FS"}" "${entry#*"$AST_FS"}"
}

# pseudo_block LABEL NAME HEAD_ARGS GOALS: one block of the current
# function: match the head against the parameters, then the goals (joined
# by $GOAL_SEP; empty for a fact with variables), then add the result.
pseudo_block() {
    local label="$1" name="$2" head_args="$3" body="$4" goal param term i text=""
    local -a head_terms goals=()
    split_on "$AST_AS" "$head_args"
    head_terms=("${SPLIT[@]}")
    if [[ -n "$body" ]]; then
        split_on "$GOAL_SEP" "$body"
        goals=("${SPLIT[@]}")
    fi

    G_LEVEL=1
    G_BOUND=" "
    G_RENAME="|"
    G_FRESH=0
    functional_reset

    # A clause variable named like a parameter at a different position would
    # be confused with it, so rename it (x -> x_).
    for ((i = 0; i < ${#FN_PARAMS[@]}; i++)); do
        [[ "${head_terms[$i]}" == "${FN_PARAMS[$i]}" ]] || G_RENAME+="${FN_PARAMS[$i]}=${FN_PARAMS[$i]}_|"
    done

    format_goal "$name" "$head_args"
    text="$FORMATTED"
    [[ "${#goals[@]}" -gt 0 ]] && text+=" if "
    for ((i = 0; i < ${#goals[@]}; i++)); do
        goal="${goals[$i]}"
        format_goal "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
        [[ "$i" -gt 0 ]] && text+=" AND "
        text+="$FORMATTED"
    done
    code_comment 1 "$label: $text"

    for ((i = 0; i < ${#FN_PARAMS[@]}; i++)); do
        [[ "${FN_MODE:$i:1}" == "k" ]] || continue
        param="${FN_PARAMS[$i]}"
        pseudo_bind "$param"
        pseudo_match "${head_terms[$i]}" "$param"
    done

    for ((i = 0; i < ${#goals[@]}; i++)); do
        G_GOAL_INDEX="$i"
        goal="${goals[$i]}"
        pseudo_goal "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
    done
    G_GOAL_INDEX=-1
    pseudo_success "$head_args"
    code_close 1
}

# pseudo_function NAME MODE: writes the whole function for one mode.
pseudo_function() {
    local name="$1" mode="$2" i alt rule_index params_args summary
    local -a known=() unknown=()
    pred_params "$name"
    FN_PARAMS=("${PARAMS[@]}")
    FN_NAME="$name"
    FN_MODE="$mode"
    function_name "$name" "$mode"

    for ((i = 0; i < ${#FN_PARAMS[@]}; i++)); do
        if [[ "${mode:$i:1}" == "k" ]]; then
            known+=("${FN_PARAMS[$i]}")
        else
            unknown+=("${FN_PARAMS[$i]}")
        fi
    done
    JOINED=""
    [[ "${#known[@]}" -gt 0 ]] && pseudo_join "${known[@]}"

    params_args="$(join_args "${FN_PARAMS[@]}")"
    format_goal "$name" "$params_args"
    if [[ "$mode" != *u* ]]; then
        summary="Returns TRUE if $FORMATTED is true."
        is_python && summary="Return True if $FORMATTED is true."
        is_js && summary="Returns true if $FORMATTED is true."
    else
        pseudo_tuple "${unknown[@]}"
        summary="Returns every $TUPLE where $FORMATTED is true."
        is_python && summary="Return every $TUPLE where $FORMATTED is true."
    fi

    G_LEVEL=1
    G_CLAUSES=()
    G_NOTES=()
    G_IN_FUNCTION=1
    if is_functional; then
        pseudo_emit 0 "def ${FUNC_NAME}(${JOINED}):"
        pseudo_emit 1 "\"\"\"$summary\"\"\""
    elif is_python; then
        pseudo_emit 0 "def ${FUNC_NAME}(${JOINED}):"
        pseudo_emit 1 "\"\"\"$summary\"\"\""
        if [[ "$mode" == *u* ]]; then
            pseudo_emit 1 "results = []"
            pseudo_emit 1 "seen = set()"
        fi
    elif is_js; then
        pseudo_emit 0 "function ${FUNC_NAME}(${JOINED}) {"
        pseudo_emit 1 "// $summary"
        if [[ "$mode" == *u* ]]; then
            pseudo_emit 1 "const results = [];"
            pseudo_emit 1 "const seen = new Set();"
        fi
    else
        pseudo_emit 0 "FUNCTION ${FUNC_NAME}(${JOINED}):"
        pseudo_emit 1 "# $summary"
        [[ "$mode" == *u* ]] && pseudo_emit 1 "results ← empty list"
    fi

    if pred_has_ground_facts "$name"; then
        G_LEVEL=1
        G_BOUND=" "
        G_RENAME="|"
        G_FRESH=0
        G_GOAL_INDEX=-1
        functional_reset
        for ((i = 0; i < ${#FN_PARAMS[@]}; i++)); do
            [[ "${mode:$i:1}" == "k" ]] && pseudo_bind "${FN_PARAMS[$i]}"
        done
        code_comment 1 "facts"
        pseudo_goal "$name" "$params_args" table
        pseudo_success "$params_args"
        code_close 1
    fi

    local fact
    for fact in "${KB_FACTS[@]}"; do
        [[ "${fact%%"$AST_FS"*}" == "$name" ]] || continue
        has_variables "${fact#*"$AST_FS"}" || continue
        pseudo_block "fact" "$name" "${fact#*"$AST_FS"}" ""
    done

    for ((alt = 0; alt < ${#KB_ALTS[@]}; alt++)); do
        rule_index="${KB_ALTS[$alt]%%"$AST_FS"*}"
        [[ "${KB_RULES[$rule_index]%%"$AST_FS"*}" == "$name" ]] || continue
        pseudo_clause "$alt"
    done

    G_LEVEL=1
    if is_functional; then
        functional_body "$mode"
    elif [[ "$mode" != *u* ]]; then
        code_return FALSE
    else
        code_return results
    fi
    G_IN_FUNCTION=0
    is_js && pseudo_emit 0 "}"
    pseudo_emit 0 ""
    is_python && pseudo_emit 0 ""
    return 0
}

# pseudo_data: the facts of every table that was used. Pseudocode shows
# the first few rows; Python and JavaScript list them all so they run.
pseudo_data() {
    local table fact args count shown limit="$MAX_DATA_ROWS" prefix="" suffix=""
    local -a rows terms
    [[ "${#PSEUDO_TABLES[@]}" -gt 0 ]] || return 0
    { is_python || is_js; } && limit=999999
    is_js && prefix="const " && suffix=";"
    code_any
    if is_python || is_js; then
        code_comment 0 "Facts"
    else
        pseudo_emit 0 "DATA"
    fi
    for table in "${PSEUDO_TABLES[@]}"; do
        rows=()
        count=0
        for fact in "${KB_FACTS[@]}"; do
            [[ "${fact%%"$AST_FS"*}" == "$table" ]] || continue
            has_variables "${fact#*"$AST_FS"}" && continue
            count=$((count + 1))
            [[ "$count" -le "$limit" ]] || continue
            args="${fact#*"$AST_FS"}"
            split_on "$AST_AS" "$args"
            terms=()
            for shown in "${SPLIT[@]}"; do
                if is_variable "$shown"; then
                    shown="$ANY_VALUE"
                elif is_cell "$shown"; then
                    pseudo_build "$shown"
                    shown="$BUILT"
                else
                    pseudo_disp "$shown"
                    shown="$DISP"
                fi
                terms+=("$shown")
            done
            pseudo_tuple "${terms[@]}"
            rows+=("$TUPLE")
        done
        if is_python || is_js; then
            if [[ "${#rows[@]}" -le "$MAX_DATA_ROWS" ]]; then
                JOINED=""
                [[ "${#rows[@]}" -gt 0 ]] && pseudo_join "${rows[@]}"
                pseudo_emit 0 "${prefix}$table = [$JOINED]${suffix}"
            else
                pseudo_emit 0 "${prefix}$table = ["
                for shown in "${rows[@]}"; do
                    pseudo_emit 1 "$shown,"
                done
                pseudo_emit 0 "]${suffix}"
            fi
        else
            JOINED=""
            [[ "${#rows[@]}" -gt 0 ]] && pseudo_join "${rows[@]}"
            if [[ "$count" -gt "$MAX_DATA_ROWS" ]]; then
                JOINED+=", ... ($((count - MAX_DATA_ROWS)) more)"
            fi
            pseudo_emit 1 "$table ← [$JOINED]"
        fi
    done
}

# pseudo_main NAME ARGS: the MAIN section that makes the call and prints.
# JavaScript runs it at the top level; the others indent it under a header.
pseudo_main() {
    local name="$1" args="$2" value base=1
    local -a vars=()
    FN_NAME=""
    FN_MODE=""
    G_BOUND=" "
    G_RENAME="|"
    G_FRESH=0
    G_GOAL_INDEX=-1
    if is_python; then
        pseudo_emit 0 "if __name__ == \"__main__\":"
    elif is_js; then
        base=0
        pseudo_emit 0 "// Main"
    else
        pseudo_emit 0 "MAIN"
    fi
    G_LEVEL="$base"
    pseudo_goal "$name" "$args"

    split_on "$AST_AS" "$args"
    for value in "${SPLIT[@]}"; do
        is_variable "$value" && add_unique vars "$value"
    done
    if [[ "${#vars[@]}" -gt 0 ]]; then
        if is_python || is_js; then
            pseudo_join "${vars[@]}"
            if is_js && [[ "$CODE_USES_LISTS" -eq 1 ]]; then
                # console.log shortens nested arrays; JSON shows them in full.
                local -a shown=()
                for value in "${vars[@]}"; do
                    shown+=("JSON.stringify($value)")
                done
                pseudo_join "${shown[@]}"
                pseudo_emit "$G_LEVEL" "console.log($JOINED);"
            elif is_js; then
                pseudo_emit "$G_LEVEL" "console.log($JOINED);"
            else
                pseudo_emit "$G_LEVEL" "print($JOINED)"
            fi
        else
            pseudo_tuple "${vars[@]}"
            pseudo_emit "$G_LEVEL" "PRINT $TUPLE"
        fi
        code_close "$base"
    elif is_python; then
        pseudo_emit "$G_LEVEL" "print(\"TRUE\")"
        pseudo_emit 1 "else:"
        pseudo_emit 2 "print(\"FALSE\")"
    elif is_js; then
        pseudo_emit "$G_LEVEL" "console.log(\"TRUE\");"
        pseudo_emit 0 "} else {"
        pseudo_emit 1 "console.log(\"FALSE\");"
        pseudo_emit 0 "}"
        G_LEVEL=0
    else
        pseudo_emit "$G_LEVEL" "PRINT \"TRUE\""
        pseudo_emit 1 "ELSE:"
        pseudo_emit 2 "PRINT \"FALSE\""
    fi
}

# translate_to LANG TARGET
translate_to() {
    local target="$2" name args main functions data i item
    CODE_LANG="$1"
    JS_HELPERS_USED=0
    FUNCTIONAL_UNIQUE_USED=0
    G_IN_FUNCTION=0

    if [[ "$target" =~ $NAME_PATTERN ]]; then
        name="$target"
        pred_params "$name"
        args=""
        [[ "${#PARAMS[@]}" -gt 0 ]] && args="$(join_args "${PARAMS[@]}")"
    elif parse_call "$target"; then
        name="$CALL_NAME"
        args="$CALL_ARGS"
    else
        echo "${E_RED}Expected a predicate name or call, like ancestor or ancestor(\"Ada\", who)${E_RESET}" >&2
        return 1
    fi
    if ! pred_has_rules "$name" && ! pred_has_facts "$name"; then
        echo "${E_RED}No facts or rules define '$name'${E_RESET}" >&2
        return 1
    fi

    code_sanitize
    safe_pred "$name"
    name="$SAFE"
    safe_args "$args"
    args="$SAFE_ARGS"

    PSEUDO_QUEUE=()
    PSEUDO_TABLES=()

    # MAIN first, since it decides which function modes are needed.
    PSEUDO_OUT=""
    pseudo_main "$name" "$args"
    main="$PSEUDO_OUT"

    PSEUDO_OUT=""
    for ((i = 0; i < ${#PSEUDO_QUEUE[@]}; i++)); do
        item="${PSEUDO_QUEUE[$i]}"
        pseudo_function "${item%%:*}" "${item#*:}"
    done
    functions="$PSEUDO_OUT"

    PSEUDO_OUT=""
    pseudo_data
    data="$PSEUDO_OUT"

    format_goal "$name" "$args"
    if [[ "$TRANSLATE_FUNCTIONS_ONLY" -eq 1 ]]; then
        printf '%s' "$functions"
    elif is_functional; then
        echo "# Functional-style Python translation of $FORMATTED, generated by Sova."
        echo "# Facts are lists of tuples. Each rule becomes a function that returns"
        echo "# a list comprehension instead of using loops: each loop becomes a"
        echo "# \"for\", each check an \"if\", and each extra clause or OR branch"
        echo "# another list joined with +."
        echo
        if [[ -n "$data" ]]; then
            printf '%s' "$data"
            echo
            echo
        fi
        if [[ "$FUNCTIONAL_UNIQUE_USED" -eq 1 ]]; then
            echo "def unique(items):"
            echo "    \"\"\"Drop repeated answers, keeping the order they were found in.\"\"\""
            if [[ "$CODE_USES_LISTS" -eq 1 ]]; then
                # Lists can't be dictionary keys, so key each item by repr().
                echo "    return list({repr(item): item for item in items}.values())"
            else
                echo "    return list(dict.fromkeys(items))"
            fi
            echo
            echo
        fi
        printf '%s' "$functions"
        printf '%s' "$main"
    elif is_python; then
        echo "# Python translation of $FORMATTED, generated by Sova."
        echo "# Facts are lists of tuples. Each rule becomes a function: AND becomes"
        echo "# nested loops and ifs, and each extra clause or OR branch adds to the"
        echo "# same results."
        echo
        if [[ -n "$data" ]]; then
            printf '%s' "$data"
            echo
            echo
        fi
        printf '%s' "$functions"
        printf '%s' "$main"
    elif is_js; then
        echo "// JavaScript translation of $FORMATTED, generated by Sova."
        echo "// Facts are arrays of rows. Each rule becomes a function: AND becomes"
        echo "// nested loops and ifs, and each extra clause or OR branch adds to the"
        echo "// same results."
        echo
        if [[ "$JS_HELPERS_USED" -eq 1 ]]; then
            echo "// Arrays can't be compared with ===, so rows are compared by their text."
            echo "const key = (row) => JSON.stringify(row);"
            echo "const has = (table, row) => table.some((r) => key(r) === key(row));"
            [[ "$CODE_USES_LISTS" -eq 1 ]] && echo "const same = (a, b) => key(a) === key(b);"
            echo
        fi
        if [[ -n "$data" ]]; then
            printf '%s' "$data"
            echo
        fi
        printf '%s' "$functions"
        printf '%s' "$main"
    else
        echo "# Pseudocode for $FORMATTED, generated by Sova."
        if [[ -n "$functions" ]]; then
            echo "# Each rule becomes a function. AND becomes nested loops and IFs,"
            echo "# and each extra clause or OR branch adds to the same results."
        fi
        if [[ "$CODE_USES_LISTS" -eq 1 ]]; then
            echo "# Lists are numbered from 0: l[0] is the first item and l[1:] is the"
            echo "# rest. [x] + rest makes a list with x in front of rest."
        fi
        echo
        printf '%s' "$functions"
        printf '%s' "$main"
        if [[ -n "$data" ]]; then
            echo
            printf '%s' "$data"
        fi
    fi

    code_restore
    return 0
}

# Kept for callers that only want pseudocode.
pseudocode_for() {
    translate_to pseudo "$1"
}
