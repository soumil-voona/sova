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
    local node kind rest existing duplicate op goal
    local current_rule="" current_alt=""
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
                duplicate=0
                for existing in "${KB_FACTS[@]}"; do
                    [[ "$existing" == "$rest" ]] && duplicate=1 && break
                done
                [[ "$duplicate" -eq 0 ]] && KB_FACTS+=("$rest")
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
    return 0
}

# Quoted strings and numbers are constants; any bare name is a variable.
is_variable() {
    [[ "$1" != [\"0-9-]* ]]
}

is_comparison() {
    case "$1" in
        "<" | ">" | "<=" | ">=" | "==" | "!=") return 0 ;;
    esac
    return 1
}

# format_goal NAME ARGS -> FORMATTED: how a goal reads in source code.
# ARGS are joined by $AST_AS.
format_goal() {
    local name="$1" args="$2"
    if is_comparison "$name"; then
        FORMATTED="${args%%"$AST_AS"*} $name ${args#*"$AST_AS"}"
    elif [[ "$name" == "!"* ]]; then
        FORMATTED="NOT ${name#!}(${args//$AST_AS/, })"
    else
        FORMATTED="$name(${args//$AST_AS/, })"
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
        entry="${entry/$AST_FS/(}"
        echo "  ${entry//$AST_AS/, })"
    done
    echo "Rules (${#KB_RULES[@]}):"
    local i goal op
    for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
        entry="${KB_RULES[$i]/$AST_FS/(}"
        echo "  ${entry//$AST_AS/, }):"
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
