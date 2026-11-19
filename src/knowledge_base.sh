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

# A quoted string is a constant; any bare name is a variable.
is_variable() {
    [[ "$1" != \"* ]]
}

kb_print() {
    local entry
    echo "Facts (${#KB_FACTS[@]}):"
    for entry in "${KB_FACTS[@]}"; do
        entry="${entry/$AST_FS/(}"
        echo "  ${entry//$AST_AS/, })"
    done
    echo "Rules (${#KB_RULES[@]}):"
    local i goal
    for ((i = 0; i < ${#KB_RULES[@]}; i++)); do
        entry="${KB_RULES[$i]/$AST_FS/(}"
        echo "  ${entry//$AST_AS/, }):"
        for goal in "${KB_GOALS[@]}"; do
            [[ "${goal%%"$AST_FS"*}" == "$i" ]] || continue
            goal="${goal#*"$AST_FS"}"
            goal="${goal/$AST_FS/ }"
            goal="${goal/$AST_FS/(}"
            goal="${goal#FIRST }"
            echo "    ${goal//$AST_AS/, })"
        done
    done
}
