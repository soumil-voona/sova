#knowledge_base.sh
# shellcheck shell=bash
#
# kb_load builds the knowledge base from the AST produced by parse_program:
#   KB_FACTS    "<name> FS <args>"                 (duplicates are skipped)
#   KB_RULES    "<name> FS <params>"
#   KB_GOALS    "<rule index> FS <op> FS <name> FS <args>"
#   KB_QUERIES  "<name> FS <args>"
#   KB_ALTS     "<rule index> FS <goal> GS <goal> ..."
#               One entry per alternative body of a rule. OR binds loosest, so
#               "a AND b OR c" gives two alternatives: [a, b] and [c]. Each goal
#               is "<name> FS <args>" and goals are joined by $GOAL_SEP.
# Queries are answered by the inference engine (src/inference.sh).

GOAL_SEP=$'\x1d'

KB_FACTS=()
KB_RULES=()
KB_GOALS=()
KB_QUERIES=()
KB_ALTS=()

kb_load() {
    local node kind rest op goal fact
    local current_rule="" current_alt=""
    local -a facts=()
    KB_FACTS=()
    KB_RULES=()
    KB_GOALS=()
    KB_QUERIES=()
    KB_ALTS=()

    for node in "${AST[@]}"; do
        kind="${node%%"$AST_FS"*}"
        rest="${node#*"$AST_FS"}"
        case "$kind" in
            FACT)
                facts+=("$rest")
                ;;
            RULE)
                [[ -n "$current_alt" ]] && KB_ALTS+=("${current_rule}${AST_FS}${current_alt}")
                current_alt=""
                KB_RULES+=("$rest")
                current_rule=$((${#KB_RULES[@]} - 1))
                ;;
            GOAL)
                KB_GOALS+=("${current_rule}${AST_FS}${rest}")
                op="${rest%%"$AST_FS"*}"
                goal="${rest#*"$AST_FS"}"
                if [[ "$op" == "OR" ]]; then
                    KB_ALTS+=("${current_rule}${AST_FS}${current_alt}")
                    current_alt=""
                fi
                current_alt="${current_alt:+${current_alt}${GOAL_SEP}}${goal}"
                ;;
            ASK)
                KB_QUERIES+=("$rest")
                ;;
        esac
    done
    [[ -n "$current_alt" ]] && KB_ALTS+=("${current_rule}${AST_FS}${current_alt}")

    # Drop repeated facts, keeping the first of each in order. Comparing each
    # fact with every earlier one took seconds for a few thousand facts, and
    # Bash 3.2 has no associative arrays, so one awk pass does it instead.
    # (Facts never contain a newline: the parser reads one line at a time.)
    if [[ "${#facts[@]}" -le 1 ]]; then
        KB_FACTS=("${facts[@]}")
    else
        while IFS= read -r fact; do
            KB_FACTS+=("$fact")
        done < <(printf '%s\n' "${facts[@]}" | LC_ALL=C awk '!seen[$0]++')
    fi
    kb_build_index
    return 0
}

# kb_build_index: for each predicate name, KBF_<name> lists the indexes of
# its facts in KB_FACTS and KBA_<name> the indexes of its rule bodies in
# KB_ALTS, so the search only looks at clauses that could match.
# (Predicate names are valid shell names, so they can be part of one.)
KB_INDEXED_NAMES=()
kb_build_index() {
    local name i entry
    for name in "${KB_INDEXED_NAMES[@]}"; do
        unset "KBF_${name}" "KBA_${name}"
    done
    KB_INDEXED_NAMES=()
    for ((i = 0; i < ${#KB_FACTS[@]}; i++)); do
        name="${KB_FACTS[i]%%"$AST_FS"*}"
        add_unique KB_INDEXED_NAMES "$name"
        eval "KBF_${name}+=($i)"
    done
    for ((i = 0; i < ${#KB_ALTS[@]}; i++)); do
        entry="${KB_ALTS[i]}"
        name="${KB_RULES[${entry%%"$AST_FS"*}]%%"$AST_FS"*}"
        add_unique KB_INDEXED_NAMES "$name"
        eval "KBA_${name}+=($i)"
    done
}

# A variable is a name: it starts with a letter or _ (renamed variables
# like x#7 too). Strings, numbers, [] and lists (@N) are not variables.
is_variable() {
    [[ "$1" == [a-zA-Z_]* ]]
}

# Built-in goals with two sides: comparisons and = (calculation).
is_comparison() {
    case "$1" in
        "<" | ">" | "<=" | ">=" | "==" | "!=" | "=") return 0 ;;
    esac
    return 1
}

# side_pretty SIDE -> PRETTY: a side of a comparison as written in source.
side_pretty() {
    if is_expression "$1"; then
        expr_pretty "$1"
    elif is_cell "$1"; then
        term_text "$1"
        PRETTY="$TERM_TEXT"
    else
        PRETTY="$1"
    fi
}

# is_gather NAME: collect:p or count:p (see src/parser.sh)
is_gather() {
    [[ "$1" == collect:* || "$1" == count:* ]]
}

# gather_parts NAME ARGS -> GATHER_KIND (collect or count), GATHER_PRED,
# GATHER_TEMPLATE (collect only), GATHER_ARGS (joined by $AST_AS), and
# GATHER_RESULT.
gather_parts() {
    local -a parts
    GATHER_KIND="${1%%:*}"
    GATHER_PRED="${1#*:}"
    split_on "$AST_AS" "$2"
    parts=("${SPLIT[@]}")
    GATHER_RESULT="${parts[${#parts[@]} - 1]}"
    unset 'parts[${#parts[@]}-1]'
    GATHER_TEMPLATE=""
    if [[ "$GATHER_KIND" == "collect" ]]; then
        GATHER_TEMPLATE="${parts[0]}"
        parts=("${parts[@]:1}")
    fi
    local IFS="$AST_AS"
    GATHER_ARGS="${parts[*]}"
}

# format_goal NAME ARGS -> FORMATTED: how a goal reads in source code.
# ARGS are joined by $AST_AS.
format_goal() {
    local name="$1" args="$2"
    if is_gather "$name"; then
        gather_parts "$name" "$args"
        local kind="$GATHER_KIND" template="$GATHER_TEMPLATE" result="$GATHER_RESULT"
        format_goal "$GATHER_PRED" "$GATHER_ARGS"
        local inner="$FORMATTED"
        side_pretty "$result"
        result="$PRETTY"
        if [[ "$kind" == "collect" ]]; then
            side_pretty "$template"
            FORMATTED="collect($PRETTY, $inner, $result)"
        else
            FORMATTED="count($inner, $result)"
        fi
        return 0
    fi
    if is_comparison "$name"; then
        side_pretty "${args%%"$AST_AS"*}"
        FORMATTED="$PRETTY $name "
        side_pretty "${args#*"$AST_AS"}"
        FORMATTED+="$PRETTY"
    else
        local term shown=""
        local -a terms
        split_on "$AST_AS" "$args"
        terms=("${SPLIT[@]}")
        for term in "${terms[@]}"; do
            is_cell "$term" && term_text "$term" && term="$TERM_TEXT"
            shown="${shown:+${shown}, }${term}"
        done
        if [[ "$name" == "!"* ]]; then
            FORMATTED="NOT ${name#!}($shown)"
        else
            FORMATTED="$name($shown)"
        fi
    fi
}

# add_unique ARRAY_NAME VALUE: appends VALUE to the named array if absent.
add_unique() {
    local array_name="$1" value="$2" existing
    eval "local -a items=(\"\${${array_name}[@]}\")"
    # shellcheck disable=SC2154 # items is declared by the eval above
    for existing in "${items[@]}"; do
        [[ "$existing" == "$value" ]] && return 0
    done
    eval "${array_name}+=(\"\$value\")"
}

# arg_count ARGS -> ARG_COUNT (ARGS joined by $AST_AS)
arg_count() {
    local separators="${1//[!$AST_AS]/}"
    ARG_COUNT=$((${#separators} + 1))
}

# kb_check_arity -> ARITY_WARNINGS: one message per predicate that is used
# with different numbers of arguments, e.g. parent/2 in a fact and
# parent/3 in a query. That's usually a typo, and it would otherwise show up
# only as a puzzling FALSE.
kb_check_arity() {
    local -a uses=() names=()
    local entry name args use arities
    ARITY_WARNINGS=()

    for entry in "${KB_FACTS[@]}" "${KB_RULES[@]}" "${KB_QUERIES[@]}"; do
        [[ -n "$entry" ]] || continue
        name="${entry%%"$AST_FS"*}"
        args="${entry#*"$AST_FS"}"
        arg_count "$args"
        uses+=("${name}/${ARG_COUNT}")
    done
    for entry in "${KB_GOALS[@]}"; do
        entry="${entry#*"$AST_FS"}"
        entry="${entry#*"$AST_FS"}"
        name="${entry%%"$AST_FS"*}"
        is_comparison "$name" && continue
        if is_gather "$name"; then
            gather_parts "$name" "${entry#*"$AST_FS"}"
            name="$GATHER_PRED"
            arg_count "$GATHER_ARGS"
            uses+=("${name}/${ARG_COUNT}")
            continue
        fi
        name="${name#!}"
        arg_count "${entry#*"$AST_FS"}"
        uses+=("${name}/${ARG_COUNT}")
    done

    for use in "${uses[@]}"; do
        add_unique names "${use%/*}"
    done
    for name in "${names[@]}"; do
        local -a seen=()
        for use in "${uses[@]}"; do
            [[ "${use%/*}" == "$name" ]] && add_unique seen "${use##*/}"
        done
        if [[ "${#seen[@]}" -gt 1 ]]; then
            arities="${seen[*]}"
            arities="${arities// /, }"
            ARITY_WARNINGS+=("'$name' is used with different numbers of arguments (${arities})")
        fi
    done
}

# Prints ARITY_WARNINGS to stderr.
kb_print_arity_warnings() {
    local warning
    kb_check_arity
    for warning in "${ARITY_WARNINGS[@]}"; do
        echo "Warning: $warning" >&2
    done
}

kb_print() {
    local entry
    echo "Facts (${#KB_FACTS[@]}):"
    for entry in "${KB_FACTS[@]}"; do
        format_goal "${entry%%"$AST_FS"*}" "${entry#*"$AST_FS"}"
        echo "  $FORMATTED"
    done
    echo "Rules (${#KB_RULES[@]}):"
    local i goal op
    for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
        entry="${KB_RULES[$i]}"
        format_goal "${entry%%"$AST_FS"*}" "${entry#*"$AST_FS"}"
        echo "  $FORMATTED:"
        for goal in "${KB_GOALS[@]}"; do
            [[ "${goal%%"$AST_FS"*}" == "$i" ]] || continue
            goal="${goal#*"$AST_FS"}"
            op="${goal%%"$AST_FS"*}"
            goal="${goal#*"$AST_FS"}"
            format_goal "${goal%%"$AST_FS"*}" "${goal#*"$AST_FS"}"
            if [[ "$op" == "FIRST" ]]; then
                echo "    $FORMATTED"
            else
                echo "    $op $FORMATTED"
            fi
        done
    done
}
